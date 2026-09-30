#!/usr/bin/env bash
# Toggle the "yo kandor" wake-word daemon fully on/off (actually stops the
# process, not just muting it). State mirrored to /tmp/qs_kandor_enabled
# (1 = listening, 0 = off) for anything that wants to read it (e.g. a future
# TopBar button).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="/tmp/qs_wake_daemon.pid"
ENABLED_FLAG="/tmp/qs_kandor_enabled"

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

if is_running; then
    PID="$(cat "$PID_FILE")"
    kill -TERM "$PID" 2>/dev/null
    for _ in $(seq 1 20); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.1
    done
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    rm -f "$PID_FILE" /tmp/qs_wake_active /tmp/qs_wake_listening
    echo "0" > "$ENABLED_FLAG"
    echo "kandor: off"
else
    bash "$DIR/wake.sh"
    echo "kandor: on"
fi
