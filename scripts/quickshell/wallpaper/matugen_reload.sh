#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# 1. Flatten Matugen v4.0 Nested JSON for Quickshell
# ------------------------------------------------------------------------------
# Updated to match your config.toml output path
QS_JSON="~/.config/hypr/scripts/quickshell/qs_colors.json"

python3 -c '
import json
import sys

def flatten_colors(obj):
    if isinstance(obj, dict):
        if "color" in obj and isinstance(obj["color"], str):
            return obj["color"]
        return {k: flatten_colors(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [flatten_colors(x) for x in obj]
    return obj

target_file = sys.argv[1]
try:
    with open(target_file, "r") as f:
        data = json.load(f)
    
    flat_data = flatten_colors(data)
    
    with open(target_file, "w") as f:
        json.dump(flat_data, f, indent=4)
        
except FileNotFoundError:
    pass
except Exception as e:
    print(f"Error flattening JSON: {e}")
' "$QS_JSON"

# ------------------------------------------------------------------------------
# 2. Flatten Matugen v4.0 Output in Standard Text Configs
# ------------------------------------------------------------------------------
# If Tera dumped {"color": "#hex"} into your text files, this strips it to #hex.
TEXT_FILES=(
    "$HOME/.config/kitty/kitty-matugen-colors.conf"
    "$HOME/.config/nvim/matugen_colors.lua"
    "$HOME/.config/cava/colors"
    "$HOME/.config/swayosd/style.css"
    "$HOME/.config/swaync/style.css"
    "$HOME/.config/rofi/theme.rasi"
    "$HOME/.config/hypr/colors.conf"
    "$HOME/.config/vivaldi/Default/style/custom.css"
    "$HOME/.cache/wal/colors.json"
    "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/themes/midnight-matugen.theme.css"
    "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions/local.matugen-theme-1.0.0/themes/matugen.json"
)

for file in "${TEXT_FILES[@]}"; do
    # Check if file exists and we have write permissions (avoids sudo password hangs on SDDM)
    if [ -f "$file" ] && [ -w "$file" ]; then
        # Looks for {"color": "#abcdef"} and replaces it with #abcdef
        sed -i -E 's/\{[[:space:]]*"color":[[:space:]]*"([^"]+)"[[:space:]]*\}/\1/g' "$file"
    elif [ -f "$file" ]; then
        echo "Warning: No write permission for $file (Skipping text clean-up)"
    fi
done

# ------------------------------------------------------------------------------
# 3. Reload System Components
# ------------------------------------------------------------------------------

# Reload Kitty instances
killall -USR1 kitty

# Reload CAVA
# ALWAYS rebuild the final config file from the base and newly generated colors
cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null

# Tell CAVA to reload the config ONLY if it is currently running
if pgrep -x "cava" > /dev/null; then
    killall -USR1 cava
fi

# Reload SwayNC CSS styling dynamically without killing the daemon
if command -v swaync-client &> /dev/null; then
    timeout 3 swaync-client -rs || true
fi

# Restart swayosd-server in the background
killall swayosd-server 2>/dev/null
swayosd-server --top-margin 0.9 --style "$HOME/.config/swayosd/style.css" > /dev/null 2>&1 &

# Run pywal from the wallpaper to generate colors for the wal VS Code theme
# -n = no wallpaper set, -s = skip terminal colors, -t = skip tty, -e = skip export
if [ -n "$FINAL_THUMB" ] && [ -f "$FINAL_THUMB" ]; then
    wal -i "$FINAL_THUMB" -n -s -t -e > /dev/null 2>&1 || true
elif [ -f "$HOME/.cache/wal/wal" ]; then
    wal -R -n -s -t -e > /dev/null 2>&1 || true
fi

# Reload Hyprland to pick up new border colors
hyprctl reload > /dev/null 2>&1

# Update Vivaldi wallpaper CSS to match current system wallpaper
VIVALDI_STYLE_DIR="$HOME/.config/vivaldi/Default/style"
WALLPAPER_SRC="/tmp/lock_bg.png"
[ -f "$WALLPAPER_SRC" ] || WALLPAPER_SRC="$FINAL_THUMB"
if [ -f "$WALLPAPER_SRC" ] && [ -d "$VIVALDI_STYLE_DIR" ]; then
    B64=$(base64 -w 0 "$WALLPAPER_SRC")
    EXT="${WALLPAPER_SRC##*.}"
    MIME="image/png"
    [[ "$EXT" =~ ^(jpg|jpeg)$ ]] && MIME="image/jpeg"
    cat > "$VIVALDI_STYLE_DIR/wallpaper.css" << EOF
#browser {
    background-image: url("data:$MIME;base64,$B64") !important;
    background-size: cover !important;
    background-position: center !important;
}
#webview-container {
    background-color: transparent !important;
}
EOF
fi

# Apply wallpaper + colors to Vivaldi
if pgrep -x "vivaldi-bin" > /dev/null; then
    CURRENT_WS=$(hyprctl activeworkspace -j | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
    VIVALDI_WORKSPACES=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws = sorted(set(
    str(c['workspace']['id'])
    for c in clients
    if 'vivaldi' in c.get('class', '').lower()
    and c['workspace']['id'] > 0
))
print(' '.join(ws) if ws else '1')
")
    FIRST_WS=$(echo "$VIVALDI_WORKSPACES" | awk '{print $1}')

    pkill -x "vivaldi-bin"
    sleep 1.5

    BEFORE_ADDRS=$(hyprctl clients -j | jq -r '[.[] | select(.class == "vivaldi-stable") | .address] | @csv')
    hyprctl dispatch exec "[workspace $FIRST_WS silent] vivaldi-stable --remote-debugging-port=9222"

    REMAINING_WS=$(echo "$VIVALDI_WORKSPACES" | awk '{for(i=2;i<=NF;i++) print $i}')
    if [[ -n "$REMAINING_WS" ]]; then
        (
            for TARGET_WS in $REMAINING_WS; do
                for i in $(seq 1 25); do
                    sleep 0.2
                    NEW_ADDR=$(hyprctl clients -j | jq -r \
                        "[.[] | select(.class == \"vivaldi-stable\") | .address] | .[] | select(. != ($BEFORE_ADDRS | split(\",\") | .[]))" \
                        2>/dev/null | head -1 | tr -d '"')
                    if [[ -n "$NEW_ADDR" ]]; then
                        hyprctl dispatch movetoworkspacesilent "$TARGET_WS,address:$NEW_ADDR" > /dev/null
                        BEFORE_ADDRS="$BEFORE_ADDRS,\"$NEW_ADDR\""
                        break
                    fi
                done
            done
        ) &
    fi

    hyprctl dispatch workspace "$CURRENT_WS"
fi

wait
