#!/usr/bin/env bash
ps -eo pid,ppid,args | awk '$2==1 && ($0 ~ /sys_toggles.sh; sleep 0.2|qs_[a-z_]*osd|playerctl .*--follow|inotifywait -m|inotifywait -qq -e (modify|close_write)|dbus-monitor|quickshell\/(cpu|net|gpu)_usage.sh|quickshell\/workspaces.sh|audio_level.py|pinned_cards.json|qs_active_widget/) {print $1}' | xargs -r kill
sleep 1
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"
