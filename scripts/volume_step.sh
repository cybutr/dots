#!/usr/bin/env bash
# Adjust default sink volume and drive VolumeOsd.qml directly - single owner
# of the output-volume OSD, no more racing swayosd + volume_listener.sh.
# Usage: volume_step.sh raise|lower|mute-toggle|set [max|value]
set -uo pipefail

ACTION="${1:-raise}"
MAX="${2:-100}"
STEP=5
TRIGGER="/tmp/qs_volume_osd"

get_vol() { pamixer --get-volume; }
get_mute() { pamixer --get-mute; }

if [[ "$ACTION" == "mute-toggle" ]]; then
    pamixer --toggle-mute >/dev/null 2>&1
elif [[ "$ACTION" == "set" ]]; then
    new="${2:-0}"
    [[ "$new" -lt 0 ]] && new=0
    [[ "$new" -gt 150 ]] && new=150
    pamixer --set-volume "$new" --allow-boost >/dev/null 2>&1
    if [[ "$new" -gt 0 ]] && [[ "$(get_mute)" == "true" ]]; then
        pamixer --unmute >/dev/null 2>&1
    fi
else
    cur=$(get_vol)
    if [[ "$ACTION" == "lower" ]]; then
        new=$(( cur - STEP ))
        [[ "$new" -lt 0 ]] && new=0
    else
        new=$(( cur + STEP ))
        [[ "$new" -gt "$MAX" ]] && new="$MAX"
    fi
    pamixer --set-volume "$new" --allow-boost >/dev/null 2>&1
    # raising from 0/muted should audibly unmute, matching normal expectation
    if [[ "$new" -gt 0 ]] && [[ "$(get_mute)" == "true" ]]; then
        pamixer --unmute >/dev/null 2>&1
    fi
fi

if [[ "$(get_mute)" == "true" ]]; then
    echo "muted" > "$TRIGGER"
else
    get_vol > "$TRIGGER"
fi
