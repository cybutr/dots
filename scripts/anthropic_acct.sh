#!/bin/bash
# Anthropic account / API-key switcher.
# One source of truth: ~/.config/anthropic/accounts.json  (registry + active id)
# Derived state: ~/.config/anthropic/current.json  (read by fish wrapper, widget, bar, OSD)
# Account entries swap ~/.claude/.credentials.json on disk. Key entries are env-only.

set -euo pipefail

DIR="$HOME/.config/anthropic"
ACC_DIR="$DIR/accounts"
REG="$DIR/accounts.json"
CUR="$DIR/current.json"
CREDS="$HOME/.claude/.credentials.json"
PROXY_URL="https://cc.freemodel.dev/"
OSD="/tmp/qs_acct_osd"

mkdir -p "$ACC_DIR"
[ -f "$REG" ] || echo '{"active":"","entries":[]}' > "$REG"

# Guard: CLAUDECODE=1 is set in the env of every running `claude` process,
# including one invoking this script via its own Bash tool on itself. Any
# command below that overwrites ~/.claude/.credentials.json (set/apply/
# update/snapshot) would be swapping the live session's own OAuth token out
# from under the exact process reading it right now — the session's in-memory
# token and the file it might refresh against go out of sync, and the next
# refresh/relogin prompt is that corruption surfacing, not a real rate limit.
# Confirmed as the actual cause of repeated forced /logins during this
# script's own development — never let it happen again from inside a session.
if [ "${CLAUDECODE:-}" = "1" ] && [ "${QS_ACCT_ALLOW_SELF_MUTATE:-}" != "1" ]; then
    case "${1:-}" in
        set|apply|update|snapshot|save-account|save-current)
            echo "refusing '$1': this script is running inside a live Claude Code session (CLAUDECODE=1)." >&2
            echo "Mutating ~/.claude/.credentials.json here would corrupt THIS session's own auth, forcing a relogin." >&2
            echo "Run this command yourself in a separate terminal instead, or SUPER+ALT+A / the fish 'claude' wrapper." >&2
            exit 3
            ;;
    esac
fi

find_claude() {
    command -v claude 2>/dev/null && return
    for c in "$HOME/.local/bin/claude" /usr/bin/claude /usr/local/bin/claude; do
        [ -x "$c" ] && { echo "$c"; return; }
    done
    echo claude
}
CLAUDE=$(find_claude)

reg() { jq "$@" "$REG"; }
save_reg() { local tmp; tmp=$(mktemp); jq "$@" "$REG" > "$tmp" && mv "$tmp" "$REG"; }

entry_json() { jq -c --arg id "$1" '.entries[] | select(.id==$id)' "$REG"; }
active_id()  { jq -r '.active' "$REG"; }

# ---- one-time bootstrap: register the freemodel proxy key if a key file exists ----
init() {
    if [ -f "$DIR/key" ] && [ -z "$(entry_json freemodel)" ]; then
        cp "$DIR/key" "$ACC_DIR/freemodel.key"
        chmod 600 "$ACC_DIR/freemodel.key"
        save_reg --arg url "$PROXY_URL" \
            '.entries += [{"id":"freemodel","label":"FreeModel","type":"key","base_url":$url,"email":""}]'
    fi
    [ "$(active_id)" = "" ] && [ "$(reg -r '.entries|length')" -gt 0 ] \
        && save_reg '.active = (.entries[0].id)'
    apply
}

# ---- snapshot the account currently logged into claude CLI ----
save_account() {
    local id="$1" label="${2:-}"
    [ -f "$CREDS" ] || { echo "no ~/.claude/.credentials.json — log in first"; exit 1; }
    cp "$CREDS" "$ACC_DIR/$id.credentials.json"
    chmod 600 "$ACC_DIR/$id.credentials.json"
    local email="" sub=""
    if st=$("$CLAUDE" auth status 2>/dev/null); then
        email=$(echo "$st" | jq -r '.email // ""')
        sub=$(echo "$st" | jq -r '.subscriptionType // ""')
    fi
    [ -z "$label" ] && label="${sub:-account}"
    label="${label^}"   # always capitalize first letter (pro -> Pro)
    # dedup: drop any existing entry with this id OR the same email, then add
    save_reg --arg id "$id" --arg label "$label" --arg email "$email" \
        'del(.entries[] | select(.id==$id or (.email==$email and $email!=""))) | .entries += [{"id":$id,"label":$label,"type":"account","email":$email}]'
    [ "$(active_id)" = "" ] && save_reg --arg id "$id" '.active=$id'
    apply
    echo "saved account '$id' ($email)"
}

# ---- snapshot the account currently logged into the CLI, auto-deriving id/label ----
save_current() {
    local st email sub id
    st=$("$CLAUDE" auth status 2>/dev/null) || { echo "not logged in"; exit 1; }
    email=$(echo "$st" | jq -r '.email // ""')
    sub=$(echo "$st" | jq -r '.subscriptionType // ""')
    [ -z "$email" ] && { echo "no account logged in"; exit 1; }
    id=$(echo "$email" | sed 's/@.*//; s/[^a-zA-Z0-9_-]/_/g')
    [ -z "$id" ] && id="account"
    save_account "$id" "${sub:-account}"
}

# ---- register an API key (e.g. another proxy / org key) ----
add_key() {
    local id="$1" label="$2" key="$3" url="${4:-$PROXY_URL}"
    # dedup by key value — if this exact key is already registered, just select it
    for f in "$ACC_DIR"/*.key; do
        [ -f "$f" ] || continue
        if [ "$(cat "$f")" = "$key" ]; then
            local existing; existing=$(basename "$f" .key)
            echo "key already registered as '$existing'"
            set_active "$existing"
            return
        fi
    done
    printf '%s' "$key" > "$ACC_DIR/$id.key"
    chmod 600 "$ACC_DIR/$id.key"
    save_reg --arg id "$id" --arg label "$label" --arg url "$url" \
        'del(.entries[] | select(.id==$id)) | .entries += [{"id":$id,"label":$label,"type":"key","base_url":$url,"email":""}]'
    [ "$(active_id)" = "" ] && save_reg --arg id "$id" '.active=$id'
    apply
    echo "added key '$id'"
}

# ---- register an opencode-backed provider (e.g. github-copilot). opencode
# keeps its own multi-provider auth.json (~/.local/share/opencode/auth.json)
# so there's no credentials file to swap here — just remember provider+model
# so the fish wrapper knows to shell out to `opencode` instead of `claude`. ----
add_opencode() {
    local id="$1" label="$2" provider="$3" model="${4:-}"
    command -v opencode >/dev/null 2>&1 || { echo "opencode not installed"; exit 1; }
    if ! opencode auth list 2>/dev/null | grep -q "$provider"; then
        echo "warning: opencode has no credentials for '$provider' yet — run: opencode auth login -p $provider"
    fi
    save_reg --arg id "$id" --arg label "$label" --arg provider "$provider" --arg model "$model" \
        'del(.entries[] | select(.id==$id)) | .entries += [{"id":$id,"label":$label,"type":"opencode","provider":$provider,"model":$model,"email":""}]'
    [ "$(active_id)" = "" ] && save_reg --arg id "$id" '.active=$id'
    apply
    echo "added opencode provider '$id' ($provider)"
}

add_key_b64() {
    local id="$1" label key url
    label=$(printf '%s' "$2" | base64 -d 2>/dev/null)
    key=$(printf '%s' "$3" | base64 -d 2>/dev/null)
    url=$(printf '%s' "${4:-}" | base64 -d 2>/dev/null)
    [ -z "$url" ] && url="$PROXY_URL"
    add_key "$id" "$label" "$key" "$url"
}

remove() {
    local id="$1"
    rm -f "$ACC_DIR/$id.credentials.json" "$ACC_DIR/$id.key"
    save_reg --arg id "$id" 'del(.entries[] | select(.id==$id))'
    if [ "$(active_id)" = "$id" ]; then
        save_reg 'if (.entries|length)>0 then .active=(.entries[0].id) else .active="" end'
    fi
    apply
    echo "removed '$id'"
}

set_active() {
    [ -n "$(entry_json "$1")" ] || { echo "no entry '$1'"; exit 1; }
    snapshot_current
    save_reg --arg id "$1" '.active=$id'
    apply "${2:-}"
}

# ---- persist whatever creds are currently on disk back into the account we're
# leaving, before swapping in the next one. The claude CLI auto-refreshes OAuth
# tokens during use and writes the refresh to ~/.claude/.credentials.json only —
# our stored snapshot doesn't see that. Without this, switching away and back
# restores the pre-refresh token and the account 401s until a manual /login.
#
# Identity guard: ~/.claude.json's oauthAccount field is a stale UI cache tied
# to the last /login event — it does NOT reflect which credentials file is
# actually active (confirmed: swapping files and even making a real successful
# API call under a different account left it unchanged). It can't be trusted
# to detect mislabeling. Instead, cross-check by content hash: if the live
# credentials file is byte-identical to a DIFFERENT account's saved snapshot,
# that token has already been captured under the wrong id — block instead of
# re-saving the same mislabeled token into yet another slot. ----
snapshot_current() {
    local cur; cur=$(active_id)
    [ -z "$cur" ] && return 0
    local e; e=$(entry_json "$cur")
    [ -n "$e" ] || return 0
    [ "$(echo "$e" | jq -r '.type')" = "account" ] || return 0
    [ -f "$CREDS" ] || return 0
    local live_hash; live_hash=$(sha256sum "$CREDS" | cut -d' ' -f1)
    local other
    for other in "$ACC_DIR"/*.credentials.json; do
        [ -f "$other" ] || continue
        local oid; oid=$(basename "$other" .credentials.json)
        [ "$oid" = "$cur" ] && continue
        if [ "$(sha256sum "$other" | cut -d' ' -f1)" = "$live_hash" ]; then
            echo "warning: current session matches saved account '$oid', not '$cur' — slot left untouched to avoid mislabeling" >&2
            return 0
        fi
    done
    cp "$CREDS" "$ACC_DIR/$cur.credentials.json"
    chmod 600 "$ACC_DIR/$cur.credentials.json"
    return 0
}

# ---- refresh an existing account entry from the current CLI login, keeping its id ----
update() {
    local id="$1"
    [ -n "$id" ] || { echo "usage: update <id>"; exit 1; }
    local e; e=$(entry_json "$id")
    [ -n "$e" ] || { echo "no entry '$id'"; exit 1; }
    if [ "$(echo "$e" | jq -r '.type')" = "key" ]; then echo "'$id' is a key, nothing to refresh"; exit 0; fi
    [ -f "$CREDS" ] || { echo "no ~/.claude/.credentials.json — log in first"; exit 1; }
    cp "$CREDS" "$ACC_DIR/$id.credentials.json"
    chmod 600 "$ACC_DIR/$id.credentials.json"
    local email sub label
    email=$(echo "$e" | jq -r '.email // ""')
    if st=$("$CLAUDE" auth status 2>/dev/null); then
        sub=$(echo "$st" | jq -r '.subscriptionType // ""')
        [ -n "$(echo "$st" | jq -r '.email // ""')" ] && email=$(echo "$st" | jq -r '.email')
    fi
    label="${sub:-account}"; label="${label^}"
    save_reg --arg id "$id" --arg label "$label" --arg email "$email" \
        '(.entries[] | select(.id==$id)) |= (.label=$label | .email=$email)'
    apply
    echo "updated '$id' -> $label ($email)"
}

# ---- one-time: capitalize the first letter of every entry label ----
relabel() {
    save_reg '.entries |= map(.label = ((.label[0:1] | ascii_upcase) + .label[1:]))'
    apply silent
    echo "relabeled"
}

disable() { save_reg --arg id "$1" '(.entries[]|select(.id==$id)).disabled = true'; echo "disabled '$1'"; }
enable()  { save_reg --arg id "$1" '(.entries[]|select(.id==$id)) |= (.disabled=false | del(.disabled_until) | del(.disabled_reason))'; echo "enabled '$1'"; }

# ---- disable an account with a known resume time (e.g. a Claude usage-limit
# reset timestamp pulled from `claude --output-format json`'s rate_limit_event.
# resetsAt). auto_resume sweeps expired ones back on automatically. ----
auto_disable() {
    local id="$1" until_epoch="$2" reason="${3:-limit}"
    save_reg --arg id "$id" --argjson until "$until_epoch" --arg reason "$reason" \
        '(.entries[]|select(.id==$id)) |= (.disabled=true | .disabled_until=$until | .disabled_reason=$reason)'
    echo "disabled '$id' until $(date -d "@$until_epoch" 2>/dev/null || echo "$until_epoch") ($reason)"
}

auto_resume() {
    local now; now=$(date +%s)
    save_reg --argjson now "$now" \
        '.entries |= map(if (.disabled_until? and .disabled_until <= $now) then (.disabled=false | del(.disabled_until) | del(.disabled_reason)) else . end)'
}

cycle() {
    local ids cur n i nxt
    # skip disabled accounts when cycling via the pill
    mapfile -t ids < <(jq -r '.entries[] | select(.disabled != true) | .id' "$REG")
    n=${#ids[@]}
    [ "$n" -eq 0 ] && { echo "no accounts"; exit 0; }
    cur=$(active_id); i=-1
    for j in "${!ids[@]}"; do [ "${ids[$j]}" = "$cur" ] && i=$j; done
    nxt=${ids[$(( (i + 1) % n ))]}
    snapshot_current
    save_reg --arg id "$nxt" '.active=$id'
    apply "${1:-}"
}

# ---- materialize active selection: swap creds (accounts) + write current.json + OSD ----
apply() {
    local silent="${1:-}"
    auto_resume
    local id; id=$(active_id)
    if [ -z "$id" ]; then echo '{}' > "$CUR"; return; fi
    local e; e=$(entry_json "$id")
    local type label email url model provider
    type=$(echo "$e" | jq -r '.type')
    label=$(echo "$e" | jq -r '.label')
    email=$(echo "$e" | jq -r '.email // ""')
    url=$(echo "$e" | jq -r '.base_url // ""')
    model=$(echo "$e" | jq -r '.model // ""')
    provider=$(echo "$e" | jq -r '.provider // ""')

    if [ "$type" = "account" ] && [ -f "$ACC_DIR/$id.credentials.json" ]; then
        mkdir -p "$(dirname "$CREDS")"
        cp "$ACC_DIR/$id.credentials.json" "$CREDS"
        chmod 600 "$CREDS"
    fi

    jq -n --arg id "$id" --arg label "$label" --arg type "$type" \
          --arg email "$email" --arg url "$url" --arg model "$model" --arg provider "$provider" \
        '{id:$id,label:$label,type:$type,email:$email,base_url:$url,model:$model,provider:$provider}' > "$CUR"

    # OSD trigger (close_write) — short code + label, like the kb-layout OSD
    [ "$silent" = "silent" ] || printf '%s\t%s\t%s' "$label" "$type" "$email" > "$OSD"
}

case "${1:-current}" in
    snapshot)      snapshot_current ;;
    init)          init ;;
    save-account)  save_account "$2" "${3:-}" ;;
    save-current)  save_current ;;
    add-key)       add_key "$2" "$3" "$4" "${5:-}" ;;
    add-key-b64)   add_key_b64 "$2" "$3" "$4" "${5:-}" ;;
    add-opencode)  add_opencode "$2" "$3" "$4" "${5:-}" ;;
    remove)        remove "$2" ;;
    update)        update "$2" ;;
    relabel)       relabel ;;
    set)           set_active "$2" "${3:-}" ;;
    disable)       disable "$2" ;;
    enable)        enable "$2" ;;
    auto-disable)  auto_disable "$2" "$3" "${4:-limit}" ;;
    auto-resume)   auto_resume ;;
    cycle)         cycle "${2:-}" ;;
    apply)         apply "${2:-}" ;;
    current)       cat "$CUR" 2>/dev/null || echo '{}' ;;
    list)          jq -c '.entries[]' "$REG" 2>/dev/null ;;
    active)        active_id ;;
    *)             echo "usage: $0 {init|save-account <id> [label]|save-current|add-key <id> <label> <key> [url]|add-opencode <id> <label> <provider> [model]|remove <id>|update <id>|relabel|set <id>|cycle|apply|current|list|active}"; exit 1 ;;
esac
