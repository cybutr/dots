#!/usr/bin/env bash
# Non-locking preview of the new lock screen (no session-lock, no real auth).
# Password "test" plays the unlock animation, anything else the shake/flash. Esc twice or 90s closes it.
QML="$HOME/.config/hypr/scripts/quickshell/Lock.qml"
[ -f /tmp/qs_lock_preview.pid ] && kill "$(cat /tmp/qs_lock_preview.pid)" 2>/dev/null
QS_LOCK_PREVIEW=1 setsid -f quickshell -p "$QML" >/tmp/qs_lock_preview.log 2>&1
sleep 0.4
pgrep -f "quickshell.*Lock.qml" | head -1 > /tmp/qs_lock_preview.pid
