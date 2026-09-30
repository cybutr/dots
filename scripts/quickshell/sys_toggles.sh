#!/usr/bin/env bash
# Snapshot of miscellaneous boolean/state toggles for sysCapsule page 2 —
# read-only "current state" pills, mirrors sys_info.sh's JSON-poll pattern.

get_wakelock() {
    if [ -f /tmp/qs_wakelock.pid ] && kill -0 "$(cat /tmp/qs_wakelock.pid 2>/dev/null)" 2>/dev/null; then
        echo true
    else
        echo false
    fi
}

get_mic_muted() {
    if command -v wpctl &>/dev/null; then
        if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED; then echo true; else echo false; fi
    elif command -v pactl &>/dev/null; then
        if [ "$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print $2}')" = "yes" ]; then echo true; else echo false; fi
    else
        echo false
    fi
}

get_idle_paused() {
    if pgrep -x hypridle >/dev/null; then echo false; else echo true; fi
}

get_nl_mode() {
    if [ -f /tmp/qs_nightlight_override ]; then cat /tmp/qs_nightlight_override; else echo "auto"; fi
}

get_brightness_curve_enabled() {
    if [ -f /tmp/qs_brightness_curve_disabled ]; then echo false; else echo true; fi
}

get_kandor_enabled() {
    if [ -f /tmp/qs_kandor_enabled ] && [ "$(cat /tmp/qs_kandor_enabled 2>/dev/null)" = "1" ]; then echo true; else echo false; fi
}

jq -n -c \
  --arg wakelock "$(get_wakelock)" \
  --arg mic_muted "$(get_mic_muted)" \
  --arg idle_paused "$(get_idle_paused)" \
  --arg nl_mode "$(get_nl_mode)" \
  --arg brightness_curve "$(get_brightness_curve_enabled)" \
  --arg kandor_enabled "$(get_kandor_enabled)" \
  '{
     wakelock: ($wakelock == "true"),
     mic_muted: ($mic_muted == "true"),
     idle_paused: ($idle_paused == "true"),
     nl_mode: $nl_mode,
     brightness_curve: ($brightness_curve == "true"),
     kandor_enabled: ($kandor_enabled == "true")
   }'
