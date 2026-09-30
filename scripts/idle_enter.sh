#!/usr/bin/env bash
# hypridle on-timeout (before the lock listener) — marks idle so focus_daemon.py
# stops counting tracked time, mutes mic if it was live, and lets resident know.
echo idle > /tmp/qs_idle_state

was_muted=$(pactl get-source-mute @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -o "yes\|no")
if [ "$was_muted" = "no" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null
    touch /tmp/qs_idle_muted_mic
else
    rm -f /tmp/qs_idle_muted_mic
fi
