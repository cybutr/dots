#!/usr/bin/env bash
# Discord background profiler — reactive per-message profile updates + periodic full sweep of real contacts

PID_FILE="/tmp/qs_discord_profiler.pid"
SWEEP_PID_FILE="/tmp/qs_discord_profiler_sweep.pid"
LOG_FILE="/tmp/qs_discord_profiler.log"
STATE_DIR="$HOME/.local/state/discord-profiler"
LAST_SWEEP_FILE="$STATE_DIR/last_sweep"
SWEEP_STARTED_FILE="$STATE_DIR/sweep_started"
SETTINGS_FILE="$HOME/.config/hypr/settings.json"

SWEEP_GUILDS="1183762487456305192 1019523857717133315"
SWEEP_INTERVAL_DAYS=7
SWEEP_RETRY_HOURS=6
SWEEP_MAX_PASSES=12
SWEEP_BATCH=8

DISALLOWED=(
    Bash Write Edit NotebookEdit
    mcp__discord-mcp__send_message mcp__discord-mcp__send_dm mcp__discord-mcp__edit_message
    mcp__discord-mcp__delete_message mcp__discord-mcp__add_reaction mcp__discord-mcp__remove_reaction
    mcp__discord-mcp__set_status mcp__discord-mcp__join_voice mcp__discord-mcp__leave_voice
    mcp__discord-mcp__create_channel mcp__discord-mcp__delete_channel mcp__discord-mcp__create_thread
    mcp__discord-mcp__start_typing mcp__discord-mcp__pin_message mcp__discord-mcp__unpin_message
    mcp__discord-mcp__set_nickname mcp__discord-mcp__discord_send_gif mcp__discord-mcp__discord_send_file
    mcp__discord-mcp__discord_queue mcp__discord-mcp__discord_style
)

log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

run_claude() {
    claude --no-continue --disallowedTools "${DISALLOWED[@]}" -p "$1"
}

profiler_prompt() {
    cat <<EOF
You are a background Discord contact profiler. Your only job is to build and maintain short, accurate person profiles. You never act on Discord.

Setup:
- Call mcp__discord-mcp__get_current_user once and remember your own user id (this is the account owner).

Event loop (repeat for about 25 event cycles, then stop):
1. Call mcp__discord-mcp__discord_wait_events, passing {"since": <seq>} from the previous call (omit since on the very first call). Keep the returned seq.
2. Ignore every event whose type is not "message". Ignore bots and the account owner.
3. For each remaining message, call mcp__discord-mcp__person_get with the author id.
   - Profile exists: only if the message reveals something durable and new (a fact, plan, preference, relationship signal, recurring topic, notable mood shift, language habit), call mcp__discord-mcp__person_note with one tight sentence. Skip small talk, logistics, single words, and anything already in the profile. At most one note per person per session unless something significant happens.
   - No profile, and the message is a DM or group DM (is_dm true), or its guild_id is one of: ${SWEEP_GUILDS}: create a thin first-contact profile. Read the last 20 messages of that channel with mcp__discord-mcp__read_messages for context, then call mcp__discord-mcp__person_note with their username and 2-4 lines: first seen ${1} and where, apparent relationship to the owner, language, tone. Leave anything unclear out.
   - No profile and none of the above (a stranger in some other server): do nothing.
4. Go back to step 1.

Hard rules:
- Never send, edit, react to, or delete messages. Never start conversations. Never change status.
- Do not record secrets, passwords, codes, addresses, or health details.
- Facts only from what was actually said. No guessing, no padding.
- Quality over volume; most messages deserve no note.
- After about 25 event cycles output exactly LOOP_DONE and stop.

Build profiles quietly. Start now.
EOF
}

sweep_prompt() {
    cat <<EOF
You are doing a full review pass to build and refresh Discord person profiles. Today is ${1}. This review started on ${2}. Never act on Discord, only read and write profiles.

1. Call mcp__discord-mcp__get_current_user (the account owner; never profile them) and mcp__discord-mcp__person_list.
2. Candidates, in this order:
   a. Every conversation from mcp__discord-mcp__list_dms: the recipient of each direct DM, and every participant of each group DM.
   b. Servers in scope, and only these: ${SWEEP_GUILDS}. For each, call mcp__discord-mcp__list_channels, pick at most 4 text channels with recent activity, read up to 50 messages each. Candidates are only people who actually interact with the owner there (replies, mentions, back-and-forth in the same thread). Never profile bystanders who never talked with the owner. Never touch any other server.
3. Skip any candidate whose profile already starts with "Last full review:" dated ${2} or later. Process at most ${SWEEP_BATCH} remaining candidates in this pass.
4. For each processed person:
   - mcp__discord-mcp__person_get for the existing profile.
   - mcp__discord-mcp__read_messages on their DM or group DM (limit 50), plus what you read in the scoped servers.
   - Write a consolidated profile with mcp__discord-mcp__person_note using replace true and their username. Merge the old notes with what you just read: keep every fact that still holds, drop duplicates and stale noise, correct anything contradicted. Format:
     Last full review: ${1}
     ## Relationship
     ## How they talk (language, tone, length, slang, emoji)
     ## Topics and interests
     ## Shared history and in-jokes
     ## Notes for conversations (do / avoid)
     Keep it tight, bullet points, only what was actually observed. Leave sections out rather than guess.
   - If there is no readable conversation with them, leave the profile untouched.
5. Do not record secrets, passwords, codes, addresses, or health details. Never send, edit, react to, or delete messages.

Finish with exactly one final line:
- SWEEP_COMPLETE if no unreviewed candidates remain after this pass
- SWEEP_PARTIAL if some remain
EOF
}

sweep_due() {
    [ -f "$LAST_SWEEP_FILE" ] || return 0
    [ $(( $(date +%s) - $(cat "$LAST_SWEEP_FILE") )) -ge $(( SWEEP_INTERVAL_DAYS * 86400 )) ]
}

run_sweep() {
    if alive "$SWEEP_PID_FILE" && [ "$(cat "$SWEEP_PID_FILE")" != "$$" ]; then
        log "sweep already running (PID $(cat "$SWEEP_PID_FILE"))"
        return 0
    fi
    echo $$ > "$SWEEP_PID_FILE"
    mkdir -p "$STATE_DIR"
    local last started pass out
    last=$(cat "$LAST_SWEEP_FILE" 2>/dev/null || echo 0)
    started=$(cat "$SWEEP_STARTED_FILE" 2>/dev/null || echo 0)
    if [ "$started" -le "$last" ]; then
        started=$(date +%s)
        echo "$started" > "$SWEEP_STARTED_FILE"
    fi
    log "sweep started (review since $(date -d "@$started" +%F))"
    for (( pass = 1; pass <= SWEEP_MAX_PASSES; pass++ )); do
        out=$(run_claude "$(sweep_prompt "$(date +%F)" "$(date -d "@$started" +%F)")" 2>&1)
        echo "$out" >> "$LOG_FILE"
        if grep -q "SWEEP_COMPLETE" <<< "$out"; then
            date +%s > "$LAST_SWEEP_FILE"
            log "sweep complete after $pass pass(es)"
            rm -f "$SWEEP_PID_FILE"
            return 0
        fi
        grep -q "SWEEP_PARTIAL" <<< "$out" || break
        sleep 5
    done
    echo $(( $(date +%s) - SWEEP_INTERVAL_DAYS * 86400 + SWEEP_RETRY_HOURS * 3600 )) > "$LAST_SWEEP_FILE"
    log "sweep incomplete, retrying in ${SWEEP_RETRY_HOURS}h"
    rm -f "$SWEEP_PID_FILE"
}

run_session() {
    local t0=$SECONDS
    log "session start"
    run_claude "$(profiler_prompt "$(date +%F)")" >> "$LOG_FILE" 2>&1
    [ $(( SECONDS - t0 )) -lt 60 ] && { log "session ended early, backing off"; sleep 300; }
}

case "${1:-status}" in
    start|autostart)
        if alive "$PID_FILE"; then
            echo "already running (PID $(cat "$PID_FILE"))"
            exit 0
        fi
        if [ "$1" = autostart ] && [ "$(jq -r '.discordProfiler' "$SETTINGS_FILE" 2>/dev/null)" = "false" ]; then
            exit 0
        fi
        setsid -f bash "$0" _loop >/dev/null 2>&1
        [ "$1" = start ] && notify-send "Discord Profiler" "Contact profiling started" -i dialog-information -t 3000
        ;;
    _loop)
        echo $$ > "$PID_FILE"
        log "profiler started"
        while [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; do
            sweep_due && run_sweep
            [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ] || break
            run_session
            sleep 3
        done
        log "profiler loop exited"
        ;;
    stop)
        for f in "$PID_FILE" "$SWEEP_PID_FILE"; do
            alive "$f" && kill -- -"$(cat "$f")" 2>/dev/null
            rm -f "$f"
        done
        log "profiler stopped"
        notify-send "Discord Profiler" "Contact profiling stopped" -i dialog-information -t 3000
        ;;
    toggle)
        if alive "$PID_FILE"; then
            bash "$0" stop
        else
            bash "$0" start
        fi
        ;;
    status)
        if alive "$PID_FILE"; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    sweep|sync)
        if alive "$SWEEP_PID_FILE"; then
            echo "sweep already running (PID $(cat "$SWEEP_PID_FILE"))"
            exit 0
        fi
        setsid -f bash "$0" _sweep >/dev/null 2>&1
        echo "sweep started, log: $LOG_FILE"
        ;;
    _sweep)
        run_sweep
        ;;
esac
