#!/usr/bin/env bash
QS="$HOME/.config/hypr/scripts/quickshell"
base=$(bash "$QS/sys_toggles.sh" 2>/dev/null)
[ -n "$base" ] || base='{}'
wifi=false; [ "$(nmcli radio wifi 2>/dev/null)" = "enabled" ] && wifi=true
bt=false; timeout 0.6 bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && bt=true
eco=$(jq -r 'if .ecoModeEnabled == false then "false" else "true" end' "$HOME/.config/hypr/settings.json" 2>/dev/null)
quiet=$(jq -r '.quiet == true' "$QS/claude/resident_quiet.json" 2>/dev/null)
echo "$base" | jq -c --argjson wifi "$wifi" --argjson bt "$bt" --argjson eco "${eco:-true}" --argjson quiet "${quiet:-false}" \
    '. + {wifi: $wifi, bt: $bt, eco: $eco, cards_quiet: $quiet}'
