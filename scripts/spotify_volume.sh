#!/usr/bin/env bash
# SUPER + volume keys → adjust Spotify's own MPRIS volume only, leaving
# system output volume untouched. Usage: spotify_volume.sh raise|lower
set -uo pipefail

DIR="${1:-raise}"
STEP=0.05

if ! playerctl --player=spotify status >/dev/null 2>&1; then
    exit 0   # spotify not running / no MPRIS interface — nothing to do
fi

if [ "$DIR" = "lower" ]; then
    playerctl --player=spotify volume "${STEP}-" >/dev/null 2>&1
else
    playerctl --player=spotify volume "${STEP}+" >/dev/null 2>&1
fi

vol=$(playerctl --player=spotify volume 2>/dev/null)
[ -z "$vol" ] && exit 0

pct=$(awk -v v="$vol" 'BEGIN { printf "%d", v * 100 }')
echo "$pct" > /tmp/qs_spotify_volume_osd
