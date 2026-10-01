#!/usr/bin/env bash
# Recapture the widget screenshots used by the Guide and the docs.
#
#   bash ~/.config/hypr/scripts/docs/capture.sh            # all widgets
#   bash ~/.config/hypr/scripts/docs/capture.sh music      # just one
#
# Opens each popup through qs_manager.sh, waits for the open animation,
# grabs the focused monitor with grim, then closes it. Output overwrites
# scripts/quickshell/guide/previews/preview_<widget>.png, then rebuilds
# docs/assets/ via build_assets.py. Run it on a clean workspace with a
# wallpaper you like — whatever is on screen ends up in the README.
set -euo pipefail

HYPR="$HOME/.config/hypr"
QS="$HYPR/scripts/qs_manager.sh"
OUT="$HYPR/scripts/quickshell/guide/previews"
SETTLE="${SETTLE:-1.2}"

widgets=("$@")
[[ ${#widgets[@]} -eq 0 ]] && widgets=(battery calendar focustime guide monitors music network stewart volume wallpaper)

command -v grim >/dev/null || { echo "grim not installed" >&2; exit 1; }
monitor=$(hyprctl monitors -j | python3 -c 'import json,sys; print(next(m["name"] for m in json.load(sys.stdin) if m["focused"]))')

bash "$QS" close || true
sleep 0.5
for w in "${widgets[@]}"; do
    echo "capturing $w on $monitor"
    bash "$QS" open "$w"
    sleep "$SETTLE"
    grim -o "$monitor" "$OUT/preview_$w.png"
    bash "$QS" close
    sleep 0.6
done

python3 "$HYPR/scripts/docs/build_assets.py"
