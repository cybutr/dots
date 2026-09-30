#!/usr/bin/env bash
mic=false; idle=false; tick=0; last=""
while true; do
    wl=false
    if [ -f /tmp/qs_wakelock.pid ]; then
        read -r wp < /tmp/qs_wakelock.pid
        [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null && wl=true
    fi
    if [ $((tick % 2)) -eq 0 ]; then
        if command -v wpctl &>/dev/null; then
            case "$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)" in *MUTED*) mic=true ;; *) mic=false ;; esac
        fi
        if pidof -q hypridle; then idle=false; else idle=true; fi
    fi
    nl=auto
    [ -f /tmp/qs_nightlight_override ] && read -r nl < /tmp/qs_nightlight_override
    bc=true
    [ -f /tmp/qs_brightness_curve_disabled ] && bc=false
    kd=false
    if [ -f /tmp/qs_kandor_enabled ]; then read -r kv < /tmp/qs_kandor_enabled; [ "$kv" = "1" ] && kd=true; fi
    out=$(printf '{"wakelock":%s,"mic_muted":%s,"idle_paused":%s,"nl_mode":"%s","brightness_curve":%s,"kandor_enabled":%s}' "$wl" "$mic" "$idle" "$nl" "$bc" "$kd")
    if [ "$out" != "$last" ]; then echo "$out"; last="$out"; fi
    tick=$((tick + 1))
    sleep 1
done
