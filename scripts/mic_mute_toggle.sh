#!/usr/bin/env bash
# Toggle default source mute and drive MicOsd.qml directly.
set -uo pipefail
pactl set-source-mute @DEFAULT_SOURCE@ toggle
muted=$(pactl get-source-mute @DEFAULT_SOURCE@)
if [[ "$muted" == *"yes"* ]]; then
    echo "muted" > /tmp/qs_mic_osd
else
    echo "live" > /tmp/qs_mic_osd
fi
