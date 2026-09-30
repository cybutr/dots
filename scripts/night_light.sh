#!/usr/bin/env bash
SETTINGS="$HOME/.config/hypr/settings.json"
OVERRIDE="/tmp/qs_nightlight_override"

START=$(jq -r '.nightLightStart // "18:00"' "$SETTINGS" 2>/dev/null)
END=$(jq -r '.nightLightEnd   // "07:00"' "$SETTINGS" 2>/dev/null)
TEMP=$(jq -r '.nightLightTemp // 4000'    "$SETTINGS" 2>/dev/null)

pkill -x wlsunset 2>/dev/null
sleep 0.1

if [ -f "$OVERRIDE" ]; then
    MODE=$(cat "$OVERRIDE")
    if [ "$MODE" = "on" ]; then
        wlsunset -t "$TEMP" -T "$TEMP" -s 00:00 -S 12:00 &
    else
        wlsunset -t 6500 -T 6500 -s 00:00 -S 12:00 &
    fi
else
    wlsunset -t "$TEMP" -T 6500 -s "$START" -S "$END" -d 1800 &
fi
