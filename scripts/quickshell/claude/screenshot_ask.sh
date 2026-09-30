#!/usr/bin/env bash
# Region-select a screenshot and hand it straight to the Claude ask chat as
# an attachment — same attach mechanism the in-chat /shot command already
# uses (window.attachPath in ClaudeAsk.qml), just reachable from a global
# keybind with a real region selector instead of a full-screen grab, and
# without needing the chat already open first.

SAVE_DIR="$HOME/.cache/quickshell/claude"
mkdir -p "$SAVE_DIR"
FILENAME="$SAVE_DIR/ask-$(date +%s).png"

SLURP_ARGS="-b 1B1F2844 -c E06B74ff -s C778DD0D -w 2"
GEOMETRY=$(slurp $SLURP_ARGS)
[ -z "$GEOMETRY" ] && exit 0

grim -g "$GEOMETRY" "$FILENAME"
[ -s "$FILENAME" ] || exit 0

# same one-shot handoff file idiom as qs_claude_prefill — ClaudeAsk.qml reads
# and deletes it the next time the widget becomes visible.
printf '%s' "$FILENAME" > /tmp/qs_claude_attach

bash "$HOME/.config/hypr/scripts/qs_manager.sh" open claudeask
