#!/usr/bin/env bash
# clean nuke + single daemon + FIFO round-trip test
pkill -9 -f claude_daemon.py 2>/dev/null
pkill -9 -f "quickshell/claude/agent.py" 2>/dev/null
pkill -9 -f "claude -p --input-format" 2>/dev/null
sleep 1
rm -f /tmp/qs_claude_daemon.pid /tmp/qs_claude_stream /tmp/qs_claude_in
setsid -f python3 "$HOME/.config/hypr/scripts/quickshell/claude/claude_daemon.py"
sleep 1
printf '%s\n' '{"cmd":"config","mode":"auto"}' > /tmp/qs_claude_in
printf '%s\n' '{"text":"say PONG only"}'        > /tmp/qs_claude_in
for i in $(seq 1 40); do
    grep -q '"t": "turn"' /tmp/qs_claude_stream 2>/dev/null && break
    sleep 1
done
echo "waited ${i}s --- transcript:"
cat /tmp/qs_claude_stream
echo "--- daemons alive: $(pgrep -fc claude_daemon.py)"
