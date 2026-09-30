#!/usr/bin/env bash
# One-line approval for a gated agentic capability (screenshot, window_control,
# input_control, file_ops). Run after a "Needs approval" notification.
set -euo pipefail
CAPS_FILE="/tmp/qs_agent_caps.json"
CAP="${1:-}"
case "$CAP" in
    screenshot|window_control|input_control|file_ops|clipboard_control|process_control) ;;
    *) echo "usage: approve_cap.sh {screenshot|window_control|input_control|file_ops|clipboard_control|process_control}"; exit 1 ;;
esac
[ -f "$CAPS_FILE" ] || echo '{"approved":[]}' > "$CAPS_FILE"
tmp=$(mktemp)
jq --arg c "$CAP" '.approved = ((.approved // []) + [$c] | unique)' "$CAPS_FILE" > "$tmp" && mv "$tmp" "$CAPS_FILE"
echo "approved: $CAP"
