#!/usr/bin/env bash
if pgrep -x hypridle > /dev/null; then
    pkill -x hypridle
    echo "paused" > /tmp/qs_idle_osd
else
    hypridle &
    disown
    echo "resumed" > /tmp/qs_idle_osd
fi
