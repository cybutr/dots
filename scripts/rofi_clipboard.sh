#!/usr/bin/env bash

if pgrep -x "rofi" > /dev/null; then
    pkill rofi
    exit 0
fi

THUMB_DIR="/tmp/cliphist_thumbs"
mkdir -p "$THUMB_DIR"

ROFI_INPUT=$(mktemp)
MISSING_THUMBS=$(mktemp)
trap 'rm -f "$ROFI_INPUT" "$MISSING_THUMBS"' EXIT

declare -A seen_ids

while IFS=$'\t' read -r id content; do
    seen_ids["$id"]=1
    if [[ "$content" == "[[ binary data"* ]]; then
        thumb="$THUMB_DIR/${id}.png"
        if [ -f "$thumb" ]; then
            printf '%s\t%s\0icon\x1f%s\n' "$id" "$content" "$thumb" >> "$ROFI_INPUT"
        else
            printf '%s\t%s\n' "$id" "$content" >> "$ROFI_INPUT"
            printf '%s\t%s\n' "$id" "$content" >> "$MISSING_THUMBS"
        fi
    else
        printf '%s\t%s\n' "$id" "$content" >> "$ROFI_INPUT"
    fi
done < <(cliphist list)

# Generate missing thumbnails in background — available on next open
if [ -s "$MISSING_THUMBS" ]; then
    MISSING_COPY=$(mktemp)
    cp "$MISSING_THUMBS" "$MISSING_COPY"
    (
        while IFS=$'\t' read -r id content; do
            thumb="$THUMB_DIR/${id}.png"
            [ -f "$thumb" ] && continue
            printf '%s\t%s' "$id" "$content" | \
                cliphist decode 2>/dev/null | \
                magick - -resize 96x96^ -gravity center -extent 96x96 "$thumb" 2>/dev/null || \
                rm -f "$thumb"
        done < "$MISSING_COPY"
        rm -f "$MISSING_COPY"
    ) &
    disown
fi

# Clean stale thumbnails
for thumb in "$THUMB_DIR"/*.png; do
    [ -f "$thumb" ] || continue
    id=$(basename "$thumb" .png)
    [ -z "${seen_ids[$id]}" ] && rm -f "$thumb"
done

selected=$(rofi -dmenu \
    -p "Clipboard" \
    -config ~/.config/rofi/config.rasi \
    -theme-str 'listview { columns: 1; spacing: 0px; }' \
    -theme-str 'element { orientation: horizontal; children: [ element-icon, element-text ]; padding: 6px 12px; }' \
    -theme-str 'element-icon { enabled: true; size: 32px; margin: 0px 8px 0px 0px; }' \
    -theme-str 'element-text { enabled: true; vertical-align: 0.5; horizontal-align: 0.0; margin: 0; text-color: inherit; }' \
    < "$ROFI_INPUT")

[ -n "$selected" ] && printf '%s\n' "$selected" | cliphist decode | wl-copy
