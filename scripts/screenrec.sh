#!/usr/bin/env bash
# Screen capture wrapper around wf-recorder (wlroots-native, hardware/CPU encode).
# Usage: screenrec.sh <duration_sec> <output.mp4> [mode] [--audio]
#   mode: full (default) | region (slurp pick) | "X,Y WxH" explicit geometry
#   stop early: touch /tmp/qs_screenrec.stop   (or send SIGINT)
set -uo pipefail

DUR="${1:-10}"
OUT="${2:-/tmp/qs_showcase.mp4}"
MODE="${3:-full}"
AUDIO="${4:-}"
STOP="/tmp/qs_screenrec.stop"
rm -f "$STOP"

ARGS=(-f "$OUT" -c libx264 -p preset=veryfast -p crf=23 -p movflags=+faststart)
case "$MODE" in
    full) : ;;
    region) ARGS+=(-g "$(slurp)") ;;
    *) ARGS+=(-g "$MODE") ;;
esac
[ "$AUDIO" = "--audio" ] && ARGS+=(--audio)

echo "capturing ${DUR}s -> $OUT (stop early: touch $STOP)"
wf-recorder "${ARGS[@]}" &
PID=$!

end=$(( $(date +%s) + DUR ))
while kill -0 "$PID" 2>/dev/null; do
    [ -f "$STOP" ] && break
    [ "$(date +%s)" -ge "$end" ] && break
    sleep 0.3
done
kill -INT "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
rm -f "$STOP"
echo "done: $OUT ($(du -h "$OUT" 2>/dev/null | cut -f1))"
