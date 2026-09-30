#!/usr/bin/env bash
# Logs every invocation (category + action + args) to ACTION_LOG so
# resident_extras.py can tell whether a proposed fix was actually acted on
# vs. just dismissed — see the dismiss/mute tracking in resident_extras.py.
ACTION_LOG="/tmp/qs_resident_action_log.jsonl"
python3 -c "
import json, sys, time
cat, action = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
with open('$ACTION_LOG', 'a') as f:
    f.write(json.dumps({'ts': int(time.time()), 'category': cat, 'action': action, 'args': args}) + '\n')
" "${RESIDENT_FIX_CATEGORY:-}" "$@" 2>/dev/null
tail -n 500 "$ACTION_LOG" > "$ACTION_LOG.tmp" 2>/dev/null && mv -f "$ACTION_LOG.tmp" "$ACTION_LOG" 2>/dev/null

case "$1" in
    start_leak_reaper)
        setsid -f python3 "$HOME/.config/hypr/scripts/leak_reaper.py" >/dev/null 2>&1 &
        echo "leak reaper started"
        ;;
    vacuum_user_journal)
        journalctl --user --vacuum-size=100M 2>&1 | tail -1
        ;;
    clear_cache)
        name="$2"
        case "$name" in
            ""|*/*|.|..) echo "refused: bad cache name"; exit 1 ;;
        esac
        target="$HOME/.cache/$name"
        [ -d "$target" ] || { echo "no such cache: $name"; exit 1; }
        rm -rf -- "$target"
        echo "cleared ~/.cache/$name"
        ;;
    copy)
        shift
        printf '%s' "$*" | wl-copy
        notify-send -a Claude -u low "Claude" "Command copied — paste it in a terminal"
        ;;
    restart_failed_unit)
        unit="$2"
        case "$unit" in
            *[!A-Za-z0-9@._-]*|"") echo "refused: bad unit"; exit 1 ;;
        esac
        systemctl --user reset-failed "$unit" && systemctl --user restart "$unit"
        ;;
    kill_hog)
        pid="$2"
        case "$pid" in
            ""|*[!0-9]*) echo "refused: bad pid"; exit 1 ;;
        esac
        [ "$(stat -c %U /proc/$pid 2>/dev/null)" = "$USER" ] || { echo "not your process"; exit 1; }
        kill "$pid"
        ;;
    emergency_power_save)
        python3 "$HOME/.config/hypr/scripts/quickshell/claude/low_battery_action.py" --emergency
        ;;
    restore_eco)
        python3 "$HOME/.config/hypr/scripts/quickshell/claude/low_battery_action.py" --restore
        ;;
    open_mira)
        bash "$HOME/.config/hypr/scripts/mira_toggle.sh"
        ;;
    *)
        echo "unknown action: $1"
        exit 1
        ;;
esac
