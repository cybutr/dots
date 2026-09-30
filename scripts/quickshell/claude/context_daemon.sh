#!/usr/bin/env bash

CTX="$HOME/.config/hypr/scripts/quickshell/claude/context.py"
MIN_INTERVAL=3   # seconds floor between rebuilds, coalesces bursts
PIDFILE="/tmp/qs_context_daemon.pid"

# self-dedup: never stack instances
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

build() { python3 "$CTX" 2>/dev/null; }

# Job control: each "( ... ) &" below gets its own process group, so killing
# -PID (negative) on RETURN reaps the whole pipeline (pactl/udevadm/etc + grep)
# instead of just the subshell wrapper — leaving pactl subscribe orphaned was
# leaking one process every wait_event cycle and exhausting pipewire-pulse's
# client limit ("too many client application connections"), same bug already
# fixed in sys_waiter.sh.
set -m

wait_event() {
    trap 'for j in $(jobs -p); do kill -TERM -- "-$j" 2>/dev/null; done; wait 2>/dev/null' RETURN

    # trailing " #" excludes sink-input / source-output volume spam (per-stream churn)
    ( pactl subscribe 2>/dev/null | grep --line-buffered -E "on (sink|source) #" | head -n 1 || sleep infinity ) &
    ( udevadm monitor --subsystem-match=power_supply 2>/dev/null | grep --line-buffered "change" | head -n 1 || sleep infinity ) &
    ( nmcli monitor 2>/dev/null | grep --line-buffered -E "connected|disconnected" | head -n 1 || sleep infinity ) &
    ( inotifywait -q -e close_write /tmp/qs_current_event.json "$HOME/.local/share/qs_schedule_cache.json" 2>/dev/null || sleep infinity ) &

    sleep 30 &

    wait -n
}

build
last=$(date +%s)
while true; do
    wait_event
    delta=$(( $(date +%s) - last ))
    [ "$delta" -lt "$MIN_INTERVAL" ] && sleep $(( MIN_INTERVAL - delta ))
    build
    last=$(date +%s)
done
