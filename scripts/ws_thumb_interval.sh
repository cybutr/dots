#!/usr/bin/env bash
THUMB_DIR="/tmp/ws_thumbs"
mkdir -p "$THUMB_DIR"

get_geo() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.x),\(.y) \(.width)x\(.height)"'
}

while true; do
    sleep 20
    GEO=$(get_geo)
    [ -z "$GEO" ] && continue

    SPECIAL_ID=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].specialWorkspace.id')
    if [ "$SPECIAL_ID" != "0" ] && [ -n "$SPECIAL_ID" ]; then
        SNAME=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].specialWorkspace.name' | sed 's/special://')
        [ -n "$SNAME" ] && grim -g "$GEO" - 2>/dev/null | magick - -resize 50% "$THUMB_DIR/ws_special_${SNAME}.png" 2>/dev/null
    else
        ACTIVE=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
        [ -n "$ACTIVE" ] && grim -g "$GEO" - 2>/dev/null | magick - -resize 50% "$THUMB_DIR/ws_${ACTIVE}.png" 2>/dev/null
    fi
done
