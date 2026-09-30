#!/usr/bin/env bash
# Reads startup_apps.json and launches each entry, honoring its target
# workspace and silent flag. Driven by the "Startup" tab in GuidePopup.qml.
#
# "class", when set, does two things:
#  1. Dedup: if a window of that class already exists, skip launching this
#     entry entirely. Matters because this script must be safe to re-run
#     mid-session (crash-restart, manual re-trigger) without opening a
#     second window of a single-primary-window app (Vivaldi/Firefox aren't
#     single-instance-locked — a second launch just opens another window in
#     the same process, silently duplicating it).
#  2. Placement strategy: if hyprland.conf already has a persistent
#     `windowrule` owning that class, placement is its job (class match,
#     not PID-tracked — proven reliable under real concurrent cold-boot
#     load, see the comment there) and this script just launches plainly.
#     Otherwise it falls back to open_on_workspace.sh, which polls hyprctl
#     for the new window and moves it explicitly by address — for an app
#     that needs a ONE-SHOT startup placement rather than a permanent home
#     for its whole class (e.g. Kitty into special:magic — a windowrule
#     would wrongly pin every future kitty window there too).
set -uo pipefail
CONF="$HOME/.config/hypr/scripts/quickshell/startup_apps.json"
SCRIPT_DIR="$HOME/.config/hypr/scripts"
HYPRCONF="$HOME/.config/hypr/hyprland.conf"
LOCK="/tmp/qs_startup_apps.lock"
[ -f "$CONF" ] || exit 0

# Guard against a double-fire (crash-restart, manual re-run, a stray second
# exec-once) launching every app twice. PID-checked so a stale lock from a
# killed run doesn't wedge startup forever.
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

has_windowrule_for_class() {
    grep -qE "match:class[[:space:]]*=[[:space:]]*\^\($1\)\\\$" "$HYPRCONF" 2>/dev/null
}

python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    apps = json.load(f)
for a in apps:
    print(a.get("workspace", ""), a.get("silent", False), a.get("class", ""), a.get("cmd", ""), sep="\x1f")
' "$CONF" | while IFS=$'\x1f' read -r ws silent cls cmd; do
    [ -z "$cmd" ] && continue

    if [ -n "$cls" ]; then
        if hyprctl clients -j | jq -e --arg c "$cls" '[.[] | select(.class == $c)] | length > 0' >/dev/null 2>&1; then
            echo "$(date '+%F %T') skip $cls — already running (cmd: $cmd)" >> "$HOME/.config/hypr/scripts/quickshell/startup_apps.log"
            continue
        fi
    fi

    if [ -n "$cls" ] && [ -n "$ws" ] && ! has_windowrule_for_class "$cls"; then
        if [ "$silent" = "True" ]; then
            setsid -f bash "$SCRIPT_DIR/open_on_workspace.sh" -s "$ws" "$cls" "$cmd" >/dev/null 2>&1 &
        else
            setsid -f bash "$SCRIPT_DIR/open_on_workspace.sh" "$ws" "$cls" "$cmd" >/dev/null 2>&1 &
        fi
        sleep 1.5
        continue
    fi

    flags=""
    [ -n "$ws" ] && flags="workspace $ws"
    [ "$silent" = "True" ] && flags="${flags:+$flags }silent"
    if [ -n "$flags" ]; then
        hyprctl dispatch exec "[$flags] $cmd"
    else
        hyprctl dispatch exec "$cmd"
    fi
    sleep 0.3
done

# Backgrounded silent launches race on final focus — land predictably on ws1.
sleep 1
hyprctl dispatch workspace 1
