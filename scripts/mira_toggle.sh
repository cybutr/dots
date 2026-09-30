#!/usr/bin/env bash
MIRA_BIN="$HOME/apps/mira/src-tauri/target/release/mira"
CMD_FILE="/tmp/qs_mira_cmd.json"

running() { hyprctl clients -j | jq -e '.[] | select(.class == "mira")' > /dev/null; }
shown() { hyprctl monitors -j | jq -e '.[] | select(.specialWorkspace.name == "special:mira")' > /dev/null; }
launch() { hyprctl dispatch exec "[workspace special:mira silent] env WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 $MIRA_BIN"; }

case "$1" in
    open|search)
        if [ "$1" = open ]; then
            [[ "$2" =~ ^[0-9a-fA-F]{8,32}$ ]] || exit 1
            payload=$(jq -nc --arg t "$2" --arg a "${3:-}" '{action:"open", thread:$t, account:(if $a == "" then null else $a end)}')
        else
            [ -n "$2" ] || exit 1
            payload=$(jq -nc --arg q "$2" '{action:"search", query:$q}')
        fi
        printf '%s' "$payload" > "$CMD_FILE.tmp" && mv "$CMD_FILE.tmp" "$CMD_FILE"
        if ! running; then
            launch
            for _ in $(seq 1 40); do running && break; sleep 0.25; done
        fi
        shown || hyprctl dispatch togglespecialworkspace mira
        ;;
    *)
        if running; then
            hyprctl dispatch togglespecialworkspace mira
        else
            launch
        fi
        ;;
esac
