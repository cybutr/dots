#!/usr/bin/env bash
# Send a message to the currently open Discord DM/channel in Vesktop.
# Usage: discord-send.sh "message text"
#
# Diacritics: uses wl-copy + ctrl+v paste. Falls back to ydotool type (strips accents).
# Newline trick: ydotool type $'\n' sends message (ydotool key Return broken in Electron).

set -e

MSG="$1"
[[ -z "$MSG" ]] && { echo "Usage: discord-send.sh \"message\""; exit 1; }

# Get vesktop window position and size dynamically
VESKTOP=$(hyprctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if 'vesktop' in c.get('class','').lower() and c.get('mapped') and not c.get('hidden'):
        at = c['at']; sz = c['size']
        print(at[0]+sz[0]//2, at[1]+sz[1]-40)
        break
" 2>/dev/null)

if [[ -z "$VESKTOP" ]]; then
    echo "Vesktop not found" >&2
    exit 1
fi

INPUT_X=$(echo "$VESKTOP" | awk '{print $1}')
INPUT_Y=$(echo "$VESKTOP" | awk '{print $2}')

# Focus vesktop
hyprctl dispatch focuswindow class:vesktop > /dev/null

# Small delay for focus to settle
sleep 0.1

# Try clipboard paste for diacritics
if command -v wl-copy &>/dev/null; then
    printf '%s' "$MSG" | wl-copy
    ydotool click 0x00 "$INPUT_X" "$INPUT_Y" 2>/dev/null || true
    sleep 0.05
    ydotool key ctrl+v 2>/dev/null || true
    sleep 0.05
else
    # Fallback: direct type (strips diacritics)
    ydotool type -- "$MSG"
fi

# Send — ydotool key Return broken in Electron, use type newline instead
ydotool type $'\n'

echo "Sent to vesktop at ($INPUT_X, $INPUT_Y)"
