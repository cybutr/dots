#!/usr/bin/env bash

# Self-dedup: duplicate instances each hold a pactl subscribe connection and
# can exhaust pipewire-pulse's client limit ("too many client application
# connections"), which breaks pactl/swayosd-client system-wide.
PIDFILE="/tmp/qs_volume_listener.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

# Helper functions to get current state
get_sink() { pactl get-default-sink; }
get_vol() { pamixer --get-volume; }
get_mute() { pamixer --get-mute; }

# 1. Initialize state
last_sink=$(get_sink)
last_vol=$(get_vol)
last_mute=$(get_mute)

if [[ "$last_mute" == "true" ]]; then
    echo "muted" > /tmp/qs_volume_state
else
    echo "${last_vol}%" > /tmp/qs_volume_state
fi

# 2. Loop through events
pactl subscribe | grep --line-buffered "Event 'change' on sink" | while read -r line; do
    
    current_sink=$(get_sink)
    current_vol=$(get_vol)
    current_mute=$(get_mute)

    # CHECK 1: Did the Output Device change? (e.g. Headphones connected)
    if [[ "$current_sink" != "$last_sink" ]]; then
        # The device changed. We do NOT want a popup for this.
        # Just update our tracking variables to the new device's levels.
        last_sink="$current_sink"
        last_vol="$current_vol"
        last_mute="$current_mute"
        continue
    fi

    # CHECK 2: Did the Volume/Mute actually change on the SAME device?
    if [[ "$current_vol" != "$last_vol" ]] || [[ "$current_mute" != "$last_mute" ]]; then

        # No independent OSD trigger here anymore - every bind that changes
        # volume already calls swayosd-client itself with the right max, and
        # a second racing call from this loop (reading pamixer async) was
        # flickering the overcharge state on/off around the 100% boundary.
        # This loop now only mirrors state for widgets that read qs_volume_state.

        # Write state for card watchers
        if [[ "$current_mute" == "true" ]]; then
            echo "muted" > /tmp/qs_volume_state
        else
            echo "${current_vol}%" > /tmp/qs_volume_state
        fi

        # Update tracking
        last_vol="$current_vol"
        last_mute="$current_mute"
    fi
done
