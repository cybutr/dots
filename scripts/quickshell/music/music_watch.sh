#!/usr/bin/env bash
# Writes music state to watch files for card use.
# Only updates files on actual change to avoid spurious inotify fires.

write_if_changed() {
    local file="$1" val="$2"
    [ -n "$val" ] || return
    [ "$(cat "$file" 2>/dev/null)" = "$val" ] && return
    echo "$val" > "$file"
}

# Init
write_if_changed /tmp/qs_music_title  "$(playerctl -p spotify metadata title  2>/dev/null)"
write_if_changed /tmp/qs_music_artist "$(playerctl -p spotify metadata artist 2>/dev/null)"
write_if_changed /tmp/qs_music_status "$(playerctl -p spotify status          2>/dev/null)"

# Follow title changes (fires on track change, not position)
playerctl -p spotify --follow metadata title 2>/dev/null | while read -r v; do
    [ -n "$v" ] || continue
    write_if_changed /tmp/qs_music_title  "$v"
    write_if_changed /tmp/qs_music_artist "$(playerctl -p spotify metadata artist 2>/dev/null)"
done &

# Follow status changes (play/pause/stop)
playerctl -p spotify --follow status 2>/dev/null | while read -r v; do
    [ -n "$v" ] || continue
    write_if_changed /tmp/qs_music_status "$v"
done &

wait
