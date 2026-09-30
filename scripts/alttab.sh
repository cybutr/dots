#!/usr/bin/env bash
pkill -f alttab_monitor.py 2>/dev/null
echo "" > /tmp/qs_alttab_nav
~/.config/hypr/scripts/qs_manager.sh open workspaces
hyprctl dispatch submap alttab
setsid sg input -c "python3 ~/.config/hypr/scripts/alttab_monitor.py" >/dev/null 2>&1 &
disown
(sleep 0.25 && echo next > /tmp/qs_alttab_nav) &
