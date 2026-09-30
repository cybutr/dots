#!/usr/bin/env bash
# Reads the caps-lock LED state (set by XKB natively on keypress - this
# script doesn't toggle anything, just reports) and drives CapsOsd.qml.
set -uo pipefail
LED=$(find /sys/class/leds -maxdepth 1 -iname "*capslock*" | head -n1)
[[ -z "$LED" ]] && exit 0
state=$(cat "$LED/brightness" 2>/dev/null || echo 0)
if [[ "$state" -gt 0 ]]; then
    echo "on" > /tmp/qs_caps_osd
else
    echo "off" > /tmp/qs_caps_osd
fi
