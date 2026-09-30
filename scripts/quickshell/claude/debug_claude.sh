#!/usr/bin/env bash
# Reproduce the agent's exact claude invocation in YOUR shell, stderr visible.
CL=$(command -v claude || echo "$HOME/.local/bin/claude")
CFG="$HOME/.config/hypr/scripts/quickshell/claude/qs_mcp.json"
MSG='{"type":"user","message":{"role":"user","content":[{"type":"text","text":"say PONG only"}]}}'

echo "claude bin: $CL"
echo
echo "===== TEST A: stream-json WITHOUT mcp ====="
printf '%s\n' "$MSG" | timeout 40 "$CL" -p \
  --input-format stream-json --output-format stream-json --verbose \
  --dangerously-skip-permissions 2>&1 | head -20
echo "exitA=${PIPESTATUS[1]}"
echo
echo "===== TEST B: stream-json WITH mcp ====="
printf '%s\n' "$MSG" | timeout 40 "$CL" -p \
  --input-format stream-json --output-format stream-json --verbose \
  --mcp-config "$CFG" --dangerously-skip-permissions 2>&1 | head -30
echo "exitB=${PIPESTATUS[1]}"
