#!/usr/bin/env bash

# Directory to save screenshots
SAVE_DIR="$HOME/Images/Screenshots"
mkdir -p "$SAVE_DIR"

# Define timestamp for filenames
time=$(date +'%Y-%m-%d-%H%M%S')
FILENAME="$SAVE_DIR/Screenshot_$time.png"

# Slurp Styling (Transparent)
SLURP_ARGS="-b 1B1F2844 -c E06B74ff -s C778DD0D -w 2"

# Notification Function
send_notification() {
    # -s checks if file exists AND size is greater than 0
    if [ -s "$FILENAME" ]; then
        notify-send -a "Screenshot" \
                    -i "$FILENAME" \
                    "Screenshot Saved" \
                    "File: Screenshot_$time.png\nFolder: $SAVE_DIR"
    fi
}

# Parse arguments
EDIT_MODE=false
FULL_MODE=false
FREEZE_MODE=false
for arg in "$@"; do
    case $arg in
        --edit) EDIT_MODE=true ;;
        --full) FULL_MODE=true ;;
        --freeze) FREEZE_MODE=true ;;
    esac
done

FREEZE_PID=""
FREEZE_SRC=""
cleanup_freeze() {
    [ -n "$FREEZE_PID" ] && kill "$FREEZE_PID" 2>/dev/null
    FREEZE_PID=""
}
trap 'cleanup_freeze; [ -n "$FREEZE_SRC" ] && rm -f "$FREEZE_SRC"' EXIT

# Handle geometry if not in full screen mode
if [ "$FULL_MODE" = false ]; then
    if [ "$FREEZE_MODE" = true ]; then
        # Grab a cursor-free snapshot of the current (hovered) frame up front;
        # the final image is cropped from this, so the pointer never appears.
        FREEZE_SRC=$(mktemp --suffix=.png)
        grim "$FREEZE_SRC"
        # hyprpicker just holds the frozen frame on screen as a visual reference
        # while selecting; its overlay (and cursor) are never captured.
        if command -v hyprpicker >/dev/null; then
            hyprpicker -r -z >/dev/null 2>&1 &
            FREEZE_PID=$!
            sleep 0.2
        fi
    fi

    # 1. Select Region first. If user presses Esc, this variable will be empty.
    GEOMETRY=$(slurp $SLURP_ARGS)

    # 2. Check if selection was cancelled
    if [ -z "$GEOMETRY" ]; then
        exit 0
    fi
fi

# Capture to stdout, then release the freeze
capture_screen() {
    if [ "$FULL_MODE" = true ]; then
        grim -
    elif [ -n "$FREEZE_SRC" ]; then
        # crop the cursor-free frozen snapshot to the selected region (slurp: "X,Y WxH")
        set -- $(printf '%s' "$GEOMETRY" | sed 's/[,x]/ /g')
        magick "$FREEZE_SRC" -crop "${3}x${4}+${1}+${2}" +repage -
    else
        grim -g "$GEOMETRY" -
    fi
    cleanup_freeze
}

gen_cliphist_thumb() {
    (
        sleep 1
        THUMB_DIR="/tmp/cliphist_thumbs"
        mkdir -p "$THUMB_DIR"
        latest=$(cliphist list 2>/dev/null | head -1)
        [ -z "$latest" ] && exit 0
        id=$(printf '%s' "$latest" | cut -f1)
        content=$(printf '%s' "$latest" | cut -f2-)
        if [[ "$content" == "[[ binary data"* ]]; then
            thumb="$THUMB_DIR/${id}.png"
            if [ ! -f "$thumb" ]; then
                printf '%s\t%s' "$id" "$content" | \
                    cliphist decode 2>/dev/null | \
                    magick - -resize 96x96^ -gravity center -extent 96x96 "$thumb" 2>/dev/null || \
                    rm -f "$thumb"
            fi
        fi
    ) &
    disown
}

if [ "$EDIT_MODE" = true ]; then
    # Edit Mode: Capture -> Open in Satty
    capture_screen | GSK_RENDERER=gl satty --filename - --output-filename "$FILENAME" --init-tool brush --copy-command wl-copy
    send_notification
    gen_cliphist_thumb
else
    # Standard Mode: Capture -> Save to file -> Copy to clipboard
    capture_screen | tee "$FILENAME" | wl-copy
    send_notification
    gen_cliphist_thumb
    # #10 screenshot-action: classify the shot in the background, surface a
    # matching one-action card (explain/OCR/annotate). Silent if nothing's
    # actionable — never blocks the screenshot flow itself.
    if [ -s "$FILENAME" ]; then
        (python3 "$HOME/.config/hypr/scripts/quickshell/claude/shot_action.py" "$FILENAME" &) \
            >/dev/null 2>&1
    fi
fi
