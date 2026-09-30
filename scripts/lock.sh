#!/usr/bin/env bash
QML="$HOME/.config/hypr/scripts/quickshell"
pids=$(pgrep -f "quickshell.*Lock(Legacy)?[.]qml")
prev=$(cat /tmp/qs_lock_preview.pid 2>/dev/null)
for p in $pids; do [ "$p" != "$prev" ] && exit 0; done
style=$(jq -r '.lockStyleEnabled // true' "$HOME/.config/hypr/settings.json" 2>/dev/null)
if [ "$style" = "false" ]; then
    exec quickshell -p "$QML/LockLegacy.qml"
fi
exec quickshell -p "$QML/Lock.qml"
