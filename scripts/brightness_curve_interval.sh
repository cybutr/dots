#!/usr/bin/env bash
# Backup tick for the slow solar-curve drift — brightness_watch.sh now handles
# instant reaction to manual changes, so this just keeps the curve following
# the sun during long idle-free stretches with no manual input.
while true; do
    sleep 60
    bash "$HOME/.config/hypr/scripts/brightness_curve.sh"
done
