#!/usr/bin/env bash
OVERRIDE="/tmp/qs_nightlight_override"
SETTINGS="$HOME/.config/hypr/settings.json"

now_h=$(date +%H)
now_m=$(date +%M)
now_mins=$((10#$now_h * 60 + 10#$now_m))

START=$(jq -r '.nightLightStart // "18:00"' "$SETTINGS" 2>/dev/null)
END=$(jq -r '.nightLightEnd // "07:00"' "$SETTINGS" 2>/dev/null)

s_h=${START%%:*}; s_m=${START##*:}
e_h=${END%%:*};   e_m=${END##*:}
s_mins=$((10#$s_h * 60 + 10#$s_m))
e_mins=$((10#$e_h * 60 + 10#$e_m))

# Is it naturally night time?
if [ $s_mins -gt $e_mins ]; then
    # wraps midnight
    if [ $now_mins -ge $s_mins ] || [ $now_mins -lt $e_mins ]; then
        natural=1
    else
        natural=0
    fi
else
    if [ $now_mins -ge $s_mins ] && [ $now_mins -lt $e_mins ]; then
        natural=1
    else
        natural=0
    fi
fi

if [ -f "$OVERRIDE" ]; then
    MODE=$(cat "$OVERRIDE")
    if [ "$MODE" = "on" ]; then
        # Was forced on — remove override (back to auto)
        rm -f "$OVERRIDE"
        [ "$natural" = "1" ] && label="󰌔 AUTO ON" || label="󰌵 AUTO OFF"
    else
        # Was forced off — remove override (back to auto)
        rm -f "$OVERRIDE"
        [ "$natural" = "1" ] && label="󰌔 AUTO ON" || label="󰌵 AUTO OFF"
    fi
else
    # Auto mode — force opposite of natural
    if [ "$natural" = "1" ]; then
        echo "off" > "$OVERRIDE"
        label="󰌵 FORCED OFF"
    else
        echo "on" > "$OVERRIDE"
        label="󰌔 FORCED ON"
    fi
fi

bash "$HOME/.config/hypr/scripts/night_light.sh"
echo "$label" > /tmp/qs_nl_osd
