#!/usr/bin/env bash
# Discord background profiler — updates person profiles for known contacts when they message

PID_FILE="/tmp/qs_discord_profiler.pid"
LOG_FILE="/tmp/qs_discord_profiler.log"

PROFILER_PROMPT='You are a background Discord contact profiler. Run this loop continuously:

LOOP (run for at least 25 event cycles, then stop so I can restart you fresh):
1. Call mcp__discord-mcp__discord_wait_events — pass {"since": <last_seq>} after the first call (omit on first call)
2. Store the returned seq value for next call
3. For each event of type "message" or "MESSAGE_CREATE":
   - Extract the author user_id and their message content
   - Skip bots (is_bot: true), skip yourself
   - Call mcp__discord-mcp__person_get with {user_id}
   - If the result is non-empty (person has an existing profile), call mcp__discord-mcp__person_note with a brief 1-2 sentence insight: what topic did they bring up, any writing style notes, relationship context, mood. Keep it tight.
   - If person_get is empty, do nothing — skip this person.
4. Go back to step 1

Rules:
- Never send any messages
- Never start new conversations
- Only update people who already have profiles (person_get non-empty)
- Keep person_note updates short and informative
- After ~25 event cycles output exactly "LOOP_DONE" and stop

Start immediately.'

run_session() {
    claude --no-continue -p "$PROFILER_PROMPT" >> "$LOG_FILE" 2>&1
}

case "${1:-status}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "already running (PID $(cat "$PID_FILE"))"
            exit 0
        fi
        (
            touch "$PID_FILE"
            echo $$ > "$PID_FILE"
            echo "[$(date)] profiler started" >> "$LOG_FILE"
            while kill -0 "$(cat "$PID_FILE")" 2>/dev/null && [ "$(cat "$PID_FILE")" = "$$" ]; do
                run_session
                sleep 3
            done
            echo "[$(date)] profiler loop exited" >> "$LOG_FILE"
        ) &
        disown $!
        sleep 0.3
        echo $! > "$PID_FILE"
        notify-send "Discord Profiler" "Contact profiling started" -i dialog-information -t 3000
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            local_pid=$(cat "$PID_FILE")
            kill "$local_pid" 2>/dev/null
            pkill -f "discord_profiler" 2>/dev/null
            rm -f "$PID_FILE"
            echo "[$(date)] profiler stopped" >> "$LOG_FILE"
        fi
        notify-send "Discord Profiler" "Contact profiling stopped" -i dialog-information -t 3000
        ;;
    toggle)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            bash "$0" stop
        else
            bash "$0" start
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    sync)
        # One-shot massive initial sync — profiles a list of known contacts from DMs
        bash "$0" _run_sync
        ;;
    _run_sync)
        SYNC_PROMPT='You are doing a one-time Discord contact profile sync. Go through each DM conversation listed below, read recent messages, and build/update person profiles using person_note.

DMs to profile (channel_id → person):
- 1185254809645895771 → fortrens (𝓕𝓸𝓻𝓽𝓻𝓮𝓷𝓼)
- 931471380053131274 → titanmarek (Titanmarek)
- 1343966202564841535 → real_matejj (matej)
- 1510387493667606618 → kate_125_xx (Kate)
- 1178034353863925953 → spralfie1109 (Spralfey)
- 1185590978975907990 → nauticfox (Nautic)
- 1333558544359886848 → thebluestickman (BlueStickman)
- 1280884062659149826 → michal_strnad (Majkl)
- 1283667536424079386 → petrkrotky_20 (Petr_Krotky20)
- 1336617105843290142 → just.me.bored0 (JaMB0)
- 1291438592475791391 → wrong_way.
- 1460952013557862453 → _epsln (Epsilon)
- 1189645147479224461 (group: Game Pass Together) → nauticfox, berdlydr, spralfie1109, __peepo
- 1338121595406913643 (group: BrassBound Owners) → berdlydr (GielDBL), spralfie1109 (Spralfey)
- 1186751282275430440 (group: bedwars/smp) → __peepo, berdlydr, nauticfox, spralfie1109

For each channel:
1. Call mcp__discord-mcp__read_messages with {channel_id, limit: 50}
2. Identify the other participants (not Adam)
3. For each participant, call person_get to see existing notes
4. Call person_note with a rich profile update: relationship to Adam, communication style, topics, vibe, any in-jokes or recurring themes you notice, language they use, how close they seem

After DMs, check these servers for relevant members:
- Server 1183762487456305192 (yeahmonke'"'"'s server): list channels, read active ones, profile active posters
- Server 1019523857717133315 (SSPŠ 🎓): list channels, read active ones, profile students

Focus on quality over speed. Build real profiles. Person notes should be useful for future conversation context.
Output a summary when done: how many people profiled.'
        claude --no-continue -p "$SYNC_PROMPT" >> "$LOG_FILE" 2>&1
        ;;
esac
