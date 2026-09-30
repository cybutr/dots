#!/usr/bin/env bash
# open_on_workspace.sh [-s] <workspace> <class> <command>
# Launches an app, waits for its window, then moves it to the target workspace.
# By default switches to the workspace. Use -s to move silently without switching.
#
# Usage: open_on_workspace.sh [-s|--silent] <workspace> <class> <command>
#
# Example from your exec.conf — Vivaldi on workspace 1:
#   open_on_workspace.sh 1 vivaldi-stable "vivaldi --new-window"
#   open_on_workspace.sh -s 1 vivaldi-stable "vivaldi --new-window"

SILENT=0
if [[ "$1" == "-s" || "$1" == "--silent" ]]; then
    SILENT=1
    shift
fi

WORKSPACE="$1"
CLASS="$2"
CMD="$3"

if [[ -z "$WORKSPACE" || -z "$CLASS" || -z "$CMD" ]]; then
    echo "Usage: $0 [-s|--silent] <workspace> <class> <command>"
    echo "  -s, --silent  Move window to workspace without switching to it"
    exit 1
fi

# Snapshot of existing window addresses for this class
BEFORE=$(hyprctl clients -j | jq -r "[.[] | select(.class == \"$CLASS\") | .address] | @csv")

# Launch the app
hyprctl dispatch exec "$CMD" > /dev/null

# Poll for up to 15s — under real concurrent cold-boot load (4 apps
# launching at once, all fighting for CPU) a native app's window can take
# well over 5s to map; measured 5-6s under load, so 5s produced marginal
# false-timeout misses even though the window did appear moments later.
for i in $(seq 1 60); do
    sleep 0.25
    NEW_ADDR=$(hyprctl clients -j | jq -r \
        "[.[] | select(.class == \"$CLASS\") | .address] | .[] | select(. != ($BEFORE | split(\",\") | .[]))" \
        2>/dev/null | head -1 | tr -d '"')

    if [[ -n "$NEW_ADDR" ]]; then
        if [[ "$SILENT" == "1" ]]; then
            hyprctl dispatch movetoworkspacesilent "$WORKSPACE,address:$NEW_ADDR" > /dev/null
        else
            hyprctl dispatch movetoworkspace "$WORKSPACE,address:$NEW_ADDR" > /dev/null
        fi
        exit 0
    fi
done

echo "$(date '+%F %T') timeout waiting for $CLASS window (cmd: $CMD)" >> "$HOME/.config/hypr/scripts/quickshell/startup_apps.log"
exit 1
