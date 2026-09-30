#!/usr/bin/env bash
# Toggles a systemd-inhibit lock that blocks lid-switch/sleep handling —
# closing the lid keeps the machine fully awake (network, downloads, etc)
# instead of suspending. Independent of hypridle's idle-lock toggle.
PIDFILE="/tmp/qs_wakelock.pid"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    echo "off" > /tmp/qs_wakelock_osd
else
    setsid systemd-inhibit --what=handle-lid-switch:sleep \
        --who="qs-wakelock" --why="user keep-awake toggle" \
        --mode=block sleep infinity &
    echo $! > "$PIDFILE"
    echo "on" > /tmp/qs_wakelock_osd
fi
