#!/usr/bin/env bash
# Region-screenshot + inline listening-mode question (SUPER+ALT+Z). Unlike
# screenshot_ask.sh (dumps into the full ClaudeAsk chat) or
# screenshot_answer.sh (fixed auto-solve prompt), this doesn't open any
# popup — it hands the captured image off to the Claude pill in
# TopBar.qml, which switches into a "listening" state (evdev-driven inline
# text field, see shot_listen.py) and calls shot_ask.py directly against
# the raw Anthropic API once you hit Enter, so it keeps answering
# screenshots even with no Claude Code CLI quota left.

SAVE_DIR="$HOME/.cache/quickshell/claude"
mkdir -p "$SAVE_DIR"
FILENAME="$SAVE_DIR/ask-$(date +%s).png"

SLURP_ARGS="-b 1B1F2844 -c E06B74ff -s C778DD0D -w 2"
GEOMETRY=$(slurp $SLURP_ARGS)
[ -z "$GEOMETRY" ] && exit 0

grim -g "$GEOMETRY" "$FILENAME"
[ -s "$FILENAME" ] || exit 0

printf '%s' "$FILENAME" > /tmp/qs_shot_listen_trigger
