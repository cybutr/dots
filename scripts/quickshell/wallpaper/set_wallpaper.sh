#!/usr/bin/env bash
# Standalone wallpaper-set, mirrors WallpaperPicker.qml's applyWallpaper() for
# non-search local files — usable headlessly (resident/agent tool calls).
# Usage: set_wallpaper.sh [filename|random]

SETTINGS="$HOME/.config/hypr/settings.json"
SRC_DIR=$(python3 -c "
import json
try:
    print(json.load(open('$SETTINGS')).get('wallpaperDir', '$HOME/Wallpapers'))
except Exception:
    print('$HOME/Wallpapers')
")

TARGET="$1"
if [ -z "$TARGET" ] || [ "$TARGET" = "random" ]; then
    TARGET=$(find "$SRC_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -printf "%f\n" | shuf -n 1)
fi
[ -z "$TARGET" ] && { echo "no wallpaper found in $SRC_DIR" >&2; exit 1; }

WALL_FILE="$SRC_DIR/$TARGET"
[ -f "$WALL_FILE" ] || { echo "not found: $WALL_FILE" >&2; exit 1; }

THUMB_DIR="$HOME/.cache/wallpaper_picker/thumbs"
mkdir -p "$THUMB_DIR"
FINAL_THUMB="$THUMB_DIR/$TARGET"
[ -f "$FINAL_THUMB" ] || magick "$WALL_FILE" -resize x420 -quality 70 "$FINAL_THUMB" 2>/dev/null || cp "$WALL_FILE" "$FINAL_THUMB"

RELOAD_SCRIPT="$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"
TRANSITIONS=("grow" "outer" "any" "wipe" "wave" "pixel" "center")
TRANSITION="${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}"

cp "$WALL_FILE" /tmp/lock_bg.png 2>/dev/null || true
pkill mpvpaper 2>/dev/null || true

if ! pgrep -x "awww-daemon" > /dev/null; then
    awww-daemon >/dev/null 2>&1 &
    sleep 0.2
fi

case "$TARGET" in
    000_*)
        mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample' '*' "$WALL_FILE" >/dev/null 2>&1 &
        ;;
    *)
        for i in $(seq 1 20); do
            env WGPU_BACKEND=vulkan awww img "$WALL_FILE" --transition-type "$TRANSITION" --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1 && break
            sleep 0.05
        done
        ;;
esac

export FINAL_THUMB
( matugen image "$FINAL_THUMB" --source-color-index 0 || true; bash "$RELOAD_SCRIPT" || true ) &
wait

echo "set: $TARGET"
