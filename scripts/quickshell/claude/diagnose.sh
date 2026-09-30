#!/usr/bin/env bash
# Full ecosystem health check: Anthropic/GLM/opencode accounts, quickshell
# daemons, widget IPC, and the Python/QML source that has bitten us before
# (a stray comma turned SYSTEM into a tuple and crashed every single agent
# turn silently — a static/import check would never have caught it, only
# pyright did, so that's a permanent step here now).
#
# Usage: diagnose.sh [--live] [--json]
#   --live   also send a real, cheap ping through every enabled backend
#            (costs tokens/quota — off by default)
#   --json   machine-readable summary instead of the human report
#
# Exit code: 0 = all OK, 1 = warnings only, 2 = at least one failure.
set -uo pipefail

BASE="$HOME/.config/hypr/scripts/quickshell/claude"
ACCT_DIR="$HOME/.config/anthropic"
ACCT_SH="$HOME/.config/hypr/scripts/anthropic_acct.sh"
LIVE=0
JSON=0
for a in "$@"; do
    case "$a" in
        --live) LIVE=1 ;;
        --json) JSON=1 ;;
    esac
done

RESULTS=()   # each entry: "STATUS|category|message"
WORST=0      # 0 ok, 1 warn, 2 fail

record() {
    local status="$1" cat="$2" msg="$3"
    RESULTS+=("$status|$cat|$msg")
    case "$status" in
        WARN) [ "$WORST" -lt 1 ] && WORST=1 ;;
        FAIL) [ "$WORST" -lt 2 ] && WORST=2 ;;
    esac
}

now_epoch() { date +%s; }

# ---------------------------------------------------------------- registry
check_registry() {
    local reg="$ACCT_DIR/accounts.json" cur="$ACCT_DIR/current.json"
    if ! jq -e . "$reg" >/dev/null 2>&1; then
        record FAIL registry "accounts.json missing or invalid JSON ($reg)"
        return
    fi
    if ! jq -e . "$cur" >/dev/null 2>&1; then
        record WARN registry "current.json missing or invalid — run: $ACCT_SH apply"
    fi
    local active; active=$(jq -r '.active // ""' "$reg")
    if [ -z "$active" ]; then
        record FAIL registry "no active entry set in accounts.json"
    fi

    local n; n=$(jq -r '.entries | length' "$reg")
    if [ "$n" -eq 0 ]; then
        record FAIL registry "no accounts registered at all"
        return
    fi

    while IFS= read -r entry; do
        local id type disabled disabled_until email
        id=$(jq -r '.id' <<<"$entry")
        type=$(jq -r '.type' <<<"$entry")
        disabled=$(jq -r '.disabled // false' <<<"$entry")
        disabled_until=$(jq -r '.disabled_until // empty' <<<"$entry")
        email=$(jq -r '.email // ""' <<<"$entry")

        # stuck-disabled: reset time already passed but never got swept back on
        if [ "$disabled" = "true" ] && [ -n "$disabled_until" ]; then
            if [ "$disabled_until" -le "$(now_epoch)" ] 2>/dev/null; then
                record WARN registry "'$id' disabled_until is in the past but still disabled — run: $ACCT_SH apply"
            fi
        fi

        case "$type" in
            account)
                local cf="$ACCT_DIR/accounts/$id.credentials.json"
                if [ ! -f "$cf" ]; then
                    record WARN registry "'$id' (account, $email) has no saved credentials snapshot"
                else
                    local exp
                    exp=$(jq -r '.claudeAiOauth.expiresAt // 0' "$cf" 2>/dev/null)
                    if [ "${exp:-0}" -le 0 ] 2>/dev/null; then
                        record FAIL registry "'$id' (account, $email) has a placeholder/zero expiresAt — token was never captured correctly, needs fresh /login + update"
                    fi
                fi
                # cross-account mislabel check: same content hash saved under two ids
                for other in "$ACCT_DIR"/accounts/*.credentials.json; do
                    [ -f "$other" ] || continue
                    local oid; oid=$(basename "$other" .credentials.json)
                    [ "$oid" = "$id" ] && continue
                    if [ -f "$cf" ] && [ "$(sha256sum "$cf" | cut -d' ' -f1)" = "$(sha256sum "$other" | cut -d' ' -f1)" ]; then
                        record FAIL registry "'$id' and '$oid' have byte-identical credentials — one was mislabeled during a /login, run save-account to fix"
                    fi
                done
                ;;
            key)
                local kf="$ACCT_DIR/accounts/$id.key"
                if [ "$disabled" != "true" ] && [ ! -s "$kf" ]; then
                    record FAIL registry "'$id' (key) has no key file or it's empty ($kf)"
                fi
                ;;
            opencode)
                if ! command -v opencode >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/opencode" ]; then
                    record FAIL registry "'$id' (opencode) registered but opencode binary not found"
                fi
                ;;
        esac
    done < <(jq -c '.entries[]' "$reg")

    record OK registry "$n entries registered, active='$active'"
}

# ------------------------------------------------------------- credentials
check_creds_sync() {
    local cur="$ACCT_DIR/current.json" creds="$HOME/.claude/.credentials.json"
    [ -f "$cur" ] || return
    local id type; id=$(jq -r '.id // ""' "$cur"); type=$(jq -r '.type // ""' "$cur")
    if [ "$type" = "account" ] && [ -n "$id" ]; then
        local snap="$ACCT_DIR/accounts/$id.credentials.json"
        if [ -f "$creds" ] && [ -f "$snap" ]; then
            if [ "$(sha256sum "$creds" | cut -d' ' -f1)" != "$(sha256sum "$snap" | cut -d' ' -f1)" ]; then
                record WARN creds "~/.claude/.credentials.json doesn't match '$id' snapshot — run: claude (self-heals) or $ACCT_SH apply"
            else
                record OK creds "live credentials match active account '$id'"
            fi
        fi
    fi
}

# ------------------------------------------------------------ python files
check_python() {
    local f base failed=0
    for f in "$BASE"/*.py; do
        base=$(basename "$f")
        if ! python3 -m py_compile "$f" 2>/tmp/diag_pyc_err; then
            record FAIL python "$base: syntax error — $(tail -1 /tmp/diag_pyc_err)"
            failed=1
        fi
    done
    rm -f /tmp/diag_pyc_err

    if command -v pyright >/dev/null 2>&1; then
        # pyright catches type/attribute bugs py_compile can't (e.g. the
        # SYSTEM-became-a-tuple incident: valid syntax, valid import, only
        # blows up when .replace() is actually called at runtime). Reported
        # as WARN not FAIL — most hits are pre-existing minor type nits, not
        # proven crashes; read the one-liners and judge case by case.
        local out errcount
        out=$(pyright --outputjson "$BASE"/*.py 2>/dev/null)
        errcount=$(jq -r '.summary.errorCount // 0' <<<"$out" 2>/dev/null)
        if [ "${errcount:-0}" -gt 0 ] 2>/dev/null; then
            local first_line
            first_line=$(jq -r '[.generalDiagnostics[] | select(.severity=="error") |
                (.file | split("/") | last) + ":" + (.range.start.line+1|tostring) + " " + (.message | split("\n")[0])] |
                join("; ")' <<<"$out" 2>/dev/null | cut -c1-300)
            record WARN python "pyright found $errcount error(s) — $first_line (full: pyright --outputjson $BASE/*.py)"
        else
            record OK python "pyright: 0 errors across $(ls "$BASE"/*.py | wc -l) files"
        fi
    else
        record WARN python "pyright not installed — skipping type-level check (this is how the SYSTEM-tuple bug was caught, don't skip it long-term)"
    fi
    [ "$failed" -eq 0 ]
}

# --------------------------------------------------------------- qml files
check_qml() {
    if ! command -v qmllint >/dev/null 2>&1; then
        record WARN qml "qmllint not installed — skipping QML syntax check"
        return
    fi
    local f base bad=0
    for f in "$BASE"/*.qml; do
        base=$(basename "$f")
        local out
        out=$(qmllint "$f" 2>&1)
        if [ -n "$out" ] && grep -qi "error" <<<"$out"; then
            record FAIL qml "$base: $(head -1 <<<"$out")"
            bad=1
        fi
    done
    [ "$bad" -eq 0 ] && record OK qml "qmllint clean on $(ls "$BASE"/*.qml | wc -l) files"
}

# --------------------------------------------------------------- processes
check_processes() {
    local expect=("quickshell.*Main" "quickshell.*TopBar" "quickshell.*BatteryAlarm")
    local name pid
    for name in "${expect[@]}"; do
        pid=$(pgrep -f "$name" | head -1)
        if [ -z "$pid" ]; then
            record WARN process "$name not running"
        fi
    done
    [ -f /tmp/qs_claude_daemon.pid ] && kill -0 "$(cat /tmp/qs_claude_daemon.pid)" 2>/dev/null \
        && record OK process "claude_daemon.py alive (pid $(cat /tmp/qs_claude_daemon.pid))" \
        || record WARN process "claude_daemon.py not running (starts on first CAW open, so this is normal if it's never been opened this session)"
    pgrep -f "context_daemon.sh" >/dev/null && record OK process "context_daemon.sh alive" \
        || record WARN process "context_daemon.sh not running"
    pgrep -f "claude_resident.py" >/dev/null && record OK process "claude_resident.py alive" \
        || record WARN process "claude_resident.py not running"
}

# --------------------------------------------------------------------- ipc
check_ipc() {
    local f age max
    for f in /tmp/qs_widget_state /tmp/qs_active_widget; do
        [ -f "$f" ] || record WARN ipc "$f missing (normal if quickshell never toggled a widget this boot)"
    done
    if [ -f /tmp/qs_workspaces.json ]; then
        age=$(( $(now_epoch) - $(stat -c %Y /tmp/qs_workspaces.json 2>/dev/null || echo 0) ))
        [ "$age" -gt 300 ] && record WARN ipc "qs_workspaces.json stale (${age}s old) — workspaces.sh watcher may have died"
    fi
    if [ -f "$HOME/.config/hypr/graphify-out/graph.json" ] 2>/dev/null; then
        :
    fi
    local colors="$HOME/.config/hypr/scripts/quickshell/qs_colors.json"
    [ -f "$colors" ] || colors=$(find "$HOME/.config/hypr" -maxdepth 3 -iname "qs_colors.json" 2>/dev/null | head -1)
    if [ -n "${colors:-}" ] && [ -f "$colors" ]; then
        record OK ipc "matugen colors present ($colors)"
    else
        record WARN ipc "qs_colors.json not found — widgets will fall back to hardcoded Catppuccin defaults"
    fi
}

# --------------------------------------------------------------------- logs
check_logs() {
    local log
    log=$(find /run/user/"$(id -u)"/quickshell/by-id -iname "log.qslog" 2>/dev/null | head -1)
    if [ -z "$log" ]; then
        record WARN logs "no quickshell log file found under /run/user/$(id -u)/quickshell"
        return
    fi
    local errs
    errs=$(tail -n 500 "$log" 2>/dev/null | grep -ciE "error|exception|fail" || true)
    if [ "${errs:-0}" -gt 0 ]; then
        record WARN logs "$errs error-looking line(s) in the last 500 lines of $log"
    else
        record OK logs "no recent errors in quickshell log"
    fi
}

# ------------------------------------------------------------------- live
check_live() {
    [ "$LIVE" -eq 1 ] || return
    export PATH="$HOME/.local/bin:$PATH"
    local reg="$ACCT_DIR/accounts.json"
    while IFS= read -r entry; do
        local id type
        id=$(jq -r '.id' <<<"$entry")
        type=$(jq -r '.type' <<<"$entry")
        local before; before=$(jq -r '.active' "$reg")
        bash "$ACCT_SH" set "$id" silent >/dev/null 2>&1 </dev/null
        local out st
        case "$type" in
            account|key)
                out=$(timeout 20 fish -c 'claude -p "reply with exactly: PING"' 2>&1 </dev/null)
                st=$?
                ;;
            opencode)
                out=$(timeout 20 opencode run "reply with exactly: PING" 2>&1 </dev/null)
                st=$?
                ;;
        esac
        if [ "$st" -eq 0 ] && grep -q "PING" <<<"$out"; then
            record OK live "'$id' responded to a real ping"
        else
            record FAIL live "'$id' did not respond correctly: $(head -c 200 <<<"$out")"
        fi
        bash "$ACCT_SH" set "$before" silent >/dev/null 2>&1 </dev/null
    done < <(jq -c '.entries[] | select(.disabled != true)' "$reg")
}

# ------------------------------------------------------------------- main
check_registry
check_creds_sync
check_python
check_qml
check_processes
check_ipc
check_logs
check_live

date +%s > "$HOME/.cache/quickshell/claude/last_diagnose" 2>/dev/null || {
    mkdir -p "$HOME/.cache/quickshell/claude"
    date +%s > "$HOME/.cache/quickshell/claude/last_diagnose"
}

if [ "$JSON" -eq 1 ]; then
    printf '['
    first=1
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r status cat msg <<<"$r"
        msg="${msg%$'\n'}"
        [ "$first" -eq 0 ] && printf ','
        first=0
        printf '{"status":"%s","category":"%s","message":%s}' \
            "$status" "$cat" "$(printf '%s' "$msg" | jq -Rs .)"
    done
    printf ']\n'
else
    echo "=== ecosystem diagnose · $(date '+%Y-%m-%d %H:%M') ==="
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r status cat msg <<<"$r"
        msg="${msg%$'\n'}"
        case "$status" in
            OK)   icon="✓" ;;
            WARN) icon="⚠" ;;
            FAIL) icon="✗" ;;
        esac
        printf "%s [%-9s] %s\n" "$icon" "$cat" "$msg"
    done
    echo "---"
    case "$WORST" in
        0) echo "all clear" ;;
        1) echo "warnings present — nothing broken, worth a look" ;;
        2) echo "FAILURES present — see ✗ lines above" ;;
    esac
fi

exit "$WORST"
