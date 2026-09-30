#!/usr/bin/env bash
# Instant reaction to manual brightness changes (hardware keys, swayosd, etc.)
# — inotify on the backlight sysfs node instead of waiting for the next poll
# tick, so the curve backs off immediately instead of up to a minute late.
DEV=$(brightnessctl -l 2>/dev/null | grep -m1 "class 'backlight'" | sed -E "s/.*'([^']+)' of.*/\1/")
[ -z "$DEV" ] && exit 0
NODE="/sys/class/backlight/$DEV/brightness"
[ -f "$NODE" ] || exit 0

SELF_WRITE_MARKER="/tmp/qs_brightness_self_write"

inotifywait -m -e modify,close_write "$NODE" 2>/dev/null | while read -r _; do
    # brightness_curve.sh's own ramp touches this marker right before writing —
    # a fresh touch means the change we're seeing is ours, not the user's.
    if [ -f "$SELF_WRITE_MARKER" ]; then
        sw_epoch=$(stat -c %Y "$SELF_WRITE_MARKER" 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        if [ $(( now_epoch - sw_epoch )) -le 2 ]; then
            continue
        fi
    fi
    bash "$HOME/.config/hypr/scripts/brightness_curve.sh"
done
