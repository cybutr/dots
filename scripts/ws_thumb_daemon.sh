#!/usr/bin/env bash
THUMB_DIR="/tmp/ws_thumbs"
mkdir -p "$THUMB_DIR"

get_geo() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.x),\(.y) \(.width)x\(.height)"'
}

special_active() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[0].specialWorkspace.id' | grep -qv '^0$'
}

take_thumb() {
    local ws_id="$1"
    local geo; geo=$(get_geo)
    [ -z "$geo" ] && return
    grim -g "$geo" - 2>/dev/null | magick - -resize 50% "$THUMB_DIR/ws_${ws_id}.png" 2>/dev/null
}

take_special_thumb() {
    local name="$1"
    [ -z "$name" ] && return
    local geo; geo=$(get_geo)
    [ -z "$geo" ] && return
    grim -g "$geo" - 2>/dev/null | magick - -resize 50% "$THUMB_DIR/ws_special_${name}.png" 2>/dev/null
}

sleep 1
ACTIVE=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
[ -n "$ACTIVE" ] && take_thumb "$ACTIVE"

socat - "UNIX-CONNECT:/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" 2>/dev/null | \
while IFS= read -r line; do
    # Regular workspace switch
    if [[ "$line" =~ ^workspace\>\>([0-9]+) ]]; then
        sleep 0.15
        special_active || take_thumb "${BASH_REMATCH[1]}"

    # Special workspace became visible
    elif [[ "$line" =~ ^activespecial\>\>([^,]+), ]]; then
        SNAME="${BASH_REMATCH[1]}"
        [ -n "$SNAME" ] && { sleep 0.15; take_special_thumb "$SNAME"; }

    # Window opened or closed on current workspace — refresh its thumbnail
    elif [[ "$line" =~ ^(openwindow|closewindow)\>\> ]]; then
        sleep 0.30
        SPECIAL_ID=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].specialWorkspace.id')
        if [ "$SPECIAL_ID" != "0" ] && [ -n "$SPECIAL_ID" ]; then
            SNAME=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].specialWorkspace.name' | sed 's/special://')
            [ -n "$SNAME" ] && take_special_thumb "$SNAME"
        else
            CUR=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
            [ -n "$CUR" ] && take_thumb "$CUR"
        fi
    fi
done
