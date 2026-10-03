#!/usr/bin/env bash
SETTINGS="$HOME/.config/hypr/settings.json"
OVERRIDE="/tmp/qs_nightlight_override"

START=$(jq -r '.nightLightStart // "18:00"' "$SETTINGS" 2>/dev/null)
END=$(jq -r '.nightLightEnd   // "07:00"' "$SETTINGS" 2>/dev/null)
TEMP=$(jq -r '.nightLightTemp // 4000'    "$SETTINGS" 2>/dev/null)

pkill -x wlsunset 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x wlsunset >/dev/null || break
    sleep 0.1
done
sleep 0.15

if [ -f "$OVERRIDE" ]; then
    MODE=$(cat "$OVERRIDE")
    if [ "$MODE" = "on" ]; then
        ARGS=(-t "$TEMP" -T "$TEMP" -s 00:00 -S 12:00)
    else
        ARGS=(-t 6500 -T 6500 -s 00:00 -S 12:00)
    fi
else
    ARGS=(-t "$TEMP" -T 6500 -s "$START" -S "$END" -d 1800)
fi

LOG=$(mktemp)
wlsunset "${ARGS[@]}" >"$LOG" 2>&1 &
PID=$!
sleep 1

# Hyprland can get its wlr-gamma-control-manager ownership stuck (known
# upstream bug, persists across plain process restarts) — a monitor
# disable/enable cycle forces a fresh output object and clears it.
if grep -q "gamma control.*failed" "$LOG"; then
    kill "$PID" 2>/dev/null
    MON=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // "eDP-1"')
    hyprctl keyword monitor "$MON,disable" >/dev/null 2>&1
    sleep 0.5
    hyprctl keyword monitor "$MON,preferred,auto,1" >/dev/null 2>&1
    sleep 1
    wlsunset "${ARGS[@]}" >"$LOG" 2>&1 &
fi
rm -f "$LOG"
