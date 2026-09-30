#!/usr/bin/env bash
# Runs a playerctl transport action and drives MediaOsd.qml with the result.
# Usage: media_control.sh play-pause|next|previous
set -uo pipefail

ACTION="${1:-play-pause}"
TRIGGER="/tmp/qs_media_osd"

if ! playerctl --player=spotify status >/dev/null 2>&1; then
    exit 0
fi

playerctl --player=spotify "$ACTION" >/dev/null 2>&1
sleep 0.15   # let MPRIS state settle before reading it back

status=$(playerctl --player=spotify status 2>/dev/null)
meta=$(playerctl --player=spotify metadata --format '{{artist}}	{{title}}	{{mpris:length}}' 2>/dev/null)
artist="${meta%%$'\t'*}"
rest="${meta#*$'\t'}"
title="${rest%%$'\t'*}"
length_us="${rest#*$'\t'}"

case "$ACTION" in
    next) icon="next" ;;
    previous) icon="prev" ;;
    *) icon=$([[ "$status" == "Playing" ]] && echo "play" || echo "pause") ;;
esac

if [[ "$ACTION" == "play-pause" ]]; then
    line1=$([[ "$status" == "Playing" ]] && echo "Playing" || echo "Paused")
    line2="$artist - $title"
    pos=$(playerctl --player=spotify position 2>/dev/null)
    len=$(awk -v us="${length_us:-0}" 'BEGIN { printf "%.2f", us / 1000000 }')
    printf '%s\t%s\t%s\t%s\t%s\n' "$icon" "$line1" "$line2" "${pos:-0}" "$len" > "$TRIGGER"

    pulse_enabled=$(jq -r '.hyprlandBorderPulseEnabled | if . == null then true else . end' "$HOME/.config/hypr/settings.json" 2>/dev/null)
    if [ "$pulse_enabled" = "true" ]; then
        accent=$("$HOME/.config/hypr/scripts/quickshell/music/music_info.sh" 2>/dev/null | jq -r '.grad // empty' | grep -oE '#[0-9A-Fa-f]{6}' | head -n1)
        [ -n "$accent" ] && "$HOME/.config/hypr/scripts/media_border_pulse.sh" "$accent"
    fi
else
    line1="$title"
    line2="$artist"
    printf '%s\t%s\t%s\n' "$icon" "$line1" "$line2" > "$TRIGGER"
fi
