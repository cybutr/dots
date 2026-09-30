#!/usr/bin/env bash
# Ensure the wake-word daemon is running (detached, idempotent).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID="/tmp/qs_wake_daemon.pid"
ENABLED_FLAG="/tmp/qs_kandor_enabled"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
    echo "1" > "$ENABLED_FLAG"
    exit 0
fi

# wake_daemon runs under venv_wake_train (openwakeword 0.6.0) — 0.4.0 mis-runs
# the custom-trained onnx model. STT still runs under venv via its own socket server.
setsid -f "$DIR/venv_wake_train/bin/python" "$DIR/wake_daemon.py" >/tmp/qs_wake.log 2>&1
echo "1" > "$ENABLED_FLAG"
