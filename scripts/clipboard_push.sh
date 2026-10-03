#!/usr/bin/env bash
# SUPER CTRL C — pushes the laptop's current clipboard to the phone as a
# resident card (source=clipboard_push). The card body is a short preview;
# the full text (capped) rides in the card's data field so the Fleet app
# can set its own clipboard to the real content.
CLIP_MAX=4000
PREVIEW_MAX=80
CARD_PY="$(dirname "$0")/quickshell/claude/resident_card.py"

text="$(wl-paste -n -t text 2>/dev/null | head -c "$CLIP_MAX")"
[ -z "$text" ] && exit 0

preview="$(printf '%s' "$text" | head -c "$PREVIEW_MAX")"
[ "${#text}" -gt "$PREVIEW_MAX" ] && preview="${preview}…"

data="$(python3 -c 'import json, sys; print(json.dumps({"text": sys.argv[1]}))' "$text")"

python3 "$CARD_PY" \
    --title "Copied to phone" --body "$preview" --icon "" \
    --urgency low --hold 5 --source clipboard_push --kind clipboard --data "$data"
