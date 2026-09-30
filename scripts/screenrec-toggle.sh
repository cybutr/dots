#!/usr/bin/env bash
# Toggle screen recording (wf-recorder). First press starts, second press stops.
# Usage: screenrec-toggle.sh [full|region]   (default full)
#   Writes live state to /tmp/qs_recording.json for the bar indicator.
#   Saves to ~/Videos/Recordings, notifies on save with an Open action.
set -uo pipefail

MODE="${1:-full}"
SAVE_DIR="$HOME/Videos/Recordings"
mkdir -p "$SAVE_DIR"

STATE="/tmp/qs_recording.json"
PIDFILE="/tmp/qs_screenrec.pid"
OUTFILE="/tmp/qs_screenrec.out"
THUMB="/tmp/qs_rec_thumb.png"

# slurp styling matched to screenshot.sh
SLURP_ARGS="-b 1B1F2844 -c E06B74ff -s C778DD0D -w 2"

is_recording() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; }

start() {
    local ts out
    ts=$(date +'%Y-%m-%d-%H%M%S')
    out="$SAVE_DIR/Recording_$ts.mp4"
    printf '%s' "$out" > "$OUTFILE"

    local args=(-f "$out" -c libx264 -p preset=veryfast -p crf=23 -p movflags=+faststart)
    if [ "$MODE" = "region" ]; then
        local geo
        geo=$(slurp $SLURP_ARGS) || exit 0
        [ -z "$geo" ] && exit 0
        args+=(-g "$geo")
    fi

    wf-recorder "${args[@]}" >/tmp/qs_screenrec.log 2>&1 &
    local pid=$!
    echo "$pid" > "$PIDFILE"
    printf '{"recording":true,"since":%s,"path":"%s","mode":"%s"}' \
        "$(date +%s)" "$out" "$MODE" > "$STATE"

    notify-send -a "Screen Recording" -i media-record -t 1800 \
        "Recording started" "${MODE^} screen · press the hotkey again to stop"
}

stop() {
    local pid out base size
    pid=$(cat "$PIDFILE" 2>/dev/null)
    out=$(cat "$OUTFILE" 2>/dev/null)

    kill -INT "$pid" 2>/dev/null
    for _ in $(seq 1 60); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    rm -f "$PIDFILE"
    printf '{"recording":false}' > "$STATE"

    if [ ! -s "$out" ]; then
        notify-send -a "Screen Recording" -u critical "Recording failed" "Nothing was captured."
        exit 1
    fi

    base=$(basename "$out")
    size=$(du -h "$out" 2>/dev/null | cut -f1)

    local icon="video-x-generic"
    if command -v ffmpeg >/dev/null && ffmpeg -y -i "$out" -vframes 1 -vf scale=256:-1 "$THUMB" >/dev/null 2>&1; then
        icon="$THUMB"
    fi

    # non-blocking: wait for the action click in a detached subshell
    (
        action=$(notify-send -a "Screen Recording" -i "$icon" -t 8000 \
            -A "open=Open" -A "folder=Show in Folder" \
            "Recording Saved" "File: $base ($size)\nFolder: $SAVE_DIR")
        case "$action" in
            open)   xdg-open "$out" ;;
            folder) xdg-open "$SAVE_DIR" ;;
        esac
    ) >/dev/null 2>&1 &
    disown
}

if is_recording; then stop; else start; fi
