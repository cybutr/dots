#!/usr/bin/env bash
SAVE_DIR="$HOME/.cache/quickshell/claude"
mkdir -p "$SAVE_DIR"
FILENAME="$SAVE_DIR/answer-$(date +%s).png"

GEOMETRY=$(slurp -b 1B1F2844 -c E06B74ff -s C778DD0D -w 2)
[ -z "$GEOMETRY" ] && exit 0

grim -g "$GEOMETRY" "$FILENAME"
[ -s "$FILENAME" ] || exit 0

python3 "$HOME/.config/hypr/scripts/quickshell/claude/resident_card.py" \
    --id screenshot-answer --title "Claude" --body "thinking…" --icon camera \
    --urgency low --hold 30 --source screenshot >/dev/null 2>&1
python3 "$HOME/.config/hypr/scripts/quickshell/claude/shot_answer.py" "$FILENAME"
