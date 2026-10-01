#!/usr/bin/env bash
QS="$HOME/.config/hypr/scripts/quickshell"

# kill 0 takes the whole lifeline process group down even if lifeline itself got SIGKILLed
trap 'trap - TERM INT HUP EXIT; kill 0 2>/dev/null; exit 0' TERM INT HUP EXIT

tag() { while read -r _; do echo "$1"; done; }

pactl subscribe 2>/dev/null | grep --line-buffered -E "'change' on (sink|source) #|'change' on server" | tag audio &

stdbuf -oL dbus-monitor --session \
    "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'" \
    "type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked'" 2>/dev/null \
    | grep --line-buffered -E 'member=(PropertiesChanged|Seeked)' | tag music &

stdbuf -oL dbus-monitor --system \
    "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Adapter1'" 2>/dev/null \
    | grep --line-buffered 'member=PropertiesChanged' | tag state &

nmcli monitor 2>/dev/null | tag state &

swaync-client -s 2>/dev/null | {
    last=""
    while read -r l; do
        d=${l#*\"dnd\": }; d=${d%%,*}
        [ "$d" != "$last" ] && { last=$d; echo state; }
    done
} &

udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null | grep --line-buffered ' change ' | tag bat &

for b in /sys/class/backlight/*/brightness; do
    [ -f "$b" ] && inotifywait -m -q -e modify,close_write "$b" 2>/dev/null | tag bright &
done

inotifywait -m -q -e close_write,moved_to,delete --format '%w%f' \
    --include '(/tmp/qs_(perf\.json|timer\.json|context\.json|kandor_enabled|wakelock\.pid|wakelock_osd|nl_osd|nightlight_override|idle_osd|mic_osd)|/hypr/settings\.json|/quickshell/qs_colors\.json|/claude/resident_quiet\.json|/history-charge-[^/]*\.dat)$' \
    /tmp "$HOME/.config/hypr" "$QS" "$QS/claude" /var/lib/upower 2>/dev/null | while read -r p; do
    case "$p" in
        */qs_perf.json) echo perf ;;
        */qs_timer.json) echo timer ;;
        */qs_context.json) echo ctx ;;
        */settings.json) echo settings ;;
        */qs_colors.json) echo wall ;;
        */history-charge-*) echo bat ;;
        *) echo state ;;
    esac
done &

bash "$QS/cpu_usage.sh" | while read -r v; do echo "cpu $v"; done &

wait
