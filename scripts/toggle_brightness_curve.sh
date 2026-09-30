#!/usr/bin/env bash
# Flip the adaptive display-brightness curve (brightness_curve.sh) on/off.
# Marker file convention mirrors night_light.sh's override file.
MARKER="/tmp/qs_brightness_curve_disabled"
OSD="/tmp/qs_brightness_curve_osd"

if [ -f "$MARKER" ]; then
    rm -f "$MARKER"
    echo "on" > "$OSD"
else
    touch "$MARKER"
    echo "off" > "$OSD"
fi
