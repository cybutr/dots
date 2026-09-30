#!/usr/bin/env bash
# Idempotent launcher for the ProtonVPN per-wifi autoconnect watcher.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID="/tmp/qs_vpn_autoconnect.pid"

if [ -f "$PID" ] && kill -0 "$(cat "$PID" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

setsid -f python3 "$DIR/vpn_autoconnect.py" >/tmp/qs_vpn_autoconnect.log 2>&1
