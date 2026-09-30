#!/usr/bin/env bash
# hypridle on-resume — clears idle state, restores mic only if idle_enter muted it.
echo active > /tmp/qs_idle_state

if [ -f /tmp/qs_idle_muted_mic ]; then
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null
    rm -f /tmp/qs_idle_muted_mic
fi
