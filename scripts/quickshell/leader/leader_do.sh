#!/usr/bin/env bash
H="$HOME/.config/hypr"
QS="$H/scripts/quickshell"
case "$1" in
    wakelock) bash "$H/scripts/toggle_wakelock.sh" ;;
    mic) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle 2>/dev/null || pactl set-source-mute @DEFAULT_SOURCE@ toggle ;;
    idle) bash "$H/scripts/toggle_hypridle.sh" ;;
    nightlight) bash "$H/scripts/toggle_night_light.sh" ;;
    curve) bash "$H/scripts/toggle_brightness_curve.sh" ;;
    kandor) bash "$QS/claude/voice/kandor_toggle.sh" ;;
    quiet)
        f="$QS/claude/resident_quiet.json"
        q=$(jq -r '.quiet == true' "$f" 2>/dev/null)
        [ "$q" = "true" ] && printf '{"quiet": false}\n' > "$f" || printf '{"quiet": true}\n' > "$f" ;;
    wifi) [ "$(nmcli radio wifi)" = "enabled" ] && nmcli radio wifi off || nmcli radio wifi on ;;
    bt) timeout 1 bluetoothctl show | grep -q "Powered: yes" && timeout 2 bluetoothctl power off || timeout 2 bluetoothctl power on ;;
    eco)
        s="$H/settings.json"
        jq '.ecoModeEnabled = (.ecoModeEnabled == false)' "$s" > "$s.leader.tmp" && mv "$s.leader.tmp" "$s" ;;
    *) exit 2 ;;
esac
