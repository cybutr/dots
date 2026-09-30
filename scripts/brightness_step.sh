#!/usr/bin/env bash
# Adjust screen brightness and drive BrightnessOsd.qml directly.
# Usage: brightness_step.sh raise|lower|set <percent>
set -uo pipefail
STEP=5

case "${1:-raise}" in
    lower) brightnessctl set "${STEP}%-" >/dev/null 2>&1 ;;
    raise) brightnessctl set "+${STEP}%" >/dev/null 2>&1 ;;
    set)
        pct="${2:-50}"
        [[ "$pct" -lt 1 ]] && pct=1
        [[ "$pct" -gt 100 ]] && pct=100
        brightnessctl set "${pct}%" >/dev/null 2>&1
        ;;
esac

pct=$(brightnessctl -m | awk -F, '{gsub("%","",$4); print $4}')
echo "${pct:-0}" > /tmp/qs_brightness_osd
