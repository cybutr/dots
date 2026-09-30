#!/usr/bin/env bash
# Seeks the current Spotify track and drives MediaOsd.qml's progress view.
# Usage: media_seek.sh back|forward
set -uo pipefail

DIR="${1:-forward}"
TRIGGER="/tmp/qs_media_osd"

if ! playerctl --player=spotify status >/dev/null 2>&1; then
    exit 0
fi

case "$DIR" in
    back) playerctl -p spotify position 5- >/dev/null 2>&1; icon="seek-back" ;;
    *) playerctl -p spotify position 5+ >/dev/null 2>&1; icon="seek-fwd" ;;
esac

meta=$(playerctl -p spotify metadata --format '{{artist}}	{{title}}	{{mpris:length}}' 2>/dev/null)
artist="${meta%%$'\t'*}"
rest="${meta#*$'\t'}"
title="${rest%%$'\t'*}"
length_us="${rest#*$'\t'}"
pos=$(playerctl -p spotify position 2>/dev/null)
len=$(awk -v us="${length_us:-0}" 'BEGIN { printf "%.2f", us / 1000000 }')

printf '%s\t%s\t%s\t%s\t%s\n' "$icon" "$title" "$artist" "${pos:-0}" "$len" > "$TRIGGER"

pulse_enabled=$(jq -r '.hyprlandBorderPulseEnabled | if . == null then true else . end' "$HOME/.config/hypr/settings.json" 2>/dev/null)
if [ "$pulse_enabled" = "true" ]; then
    accent=$("$HOME/.config/hypr/scripts/quickshell/music/music_info.sh" 2>/dev/null | jq -r '.grad // empty' | grep -oE '#[0-9A-Fa-f]{6}' | head -n1)
    [ -n "$accent" ] && "$HOME/.config/hypr/scripts/media_border_pulse.sh" "$accent"
fi
exit 0
