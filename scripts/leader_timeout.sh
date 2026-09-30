#!/usr/bin/env bash
# Auto-reset the "leader" submap if no second key is pressed within 0.6s.
# Idempotent — dispatching submap reset when already reset is a no-op.
sleep 0.6
hyprctl dispatch submap reset >/dev/null 2>&1
