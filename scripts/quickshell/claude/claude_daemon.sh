#!/usr/bin/env bash
# Ensure the persistent Claude daemon is running (detached). Idempotent.
PID="/tmp/qs_claude_daemon.pid"
DAEMON="$HOME/.config/hypr/scripts/quickshell/claude/claude_daemon.py"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
    exit 0
fi

setsid -f python3 "$DAEMON" >/dev/null 2>&1
