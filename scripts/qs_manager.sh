#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CONSTANTS & ARGUMENTS
# -----------------------------------------------------------------------------
QS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT_PID_FILE="$HOME/.cache/bt_scan_pid"
BT_SCAN_LOG="$HOME/.cache/bt_scan.log"
THUMB_DIR="$HOME/.cache/wallpaper_picker/thumbs"

resolve_src_dir() {
    local SETTINGS_FILE="$HOME/.config/hypr/settings.json" JSON_DIR
    if [ -f "$SETTINGS_FILE" ]; then
        JSON_DIR=$(jq -r '.wallpaperDir // empty' "$SETTINGS_FILE" 2>/dev/null)
        if [ -n "$JSON_DIR" ]; then
            JSON_DIR="${JSON_DIR/#\~/$HOME}"
            JSON_DIR="${JSON_DIR%/}"
            SRC_DIR="$JSON_DIR"
        fi
    fi
    SRC_DIR="${SRC_DIR:-${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}}"
}

# User-specific cache directory matching the QML logic
QS_NETWORK_CACHE="${XDG_RUNTIME_DIR:-$HOME/.cache}/qs_network"
mkdir -p "$QS_NETWORK_CACHE"

IPC_FILE="/tmp/qs_widget_state"
NETWORK_MODE_FILE="$QS_NETWORK_CACHE/mode"

ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

# -----------------------------------------------------------------------------
# FAST PATH: WORKSPACE SWITCHING
# -----------------------------------------------------------------------------
if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
    WORKSPACE_NUM="$ACTION"
    echo "close" > "$IPC_FILE" # Tell QML to hide the widget natively
    
    CMD="workspace $WORKSPACE_NUM"
    [[ "$2" == "move" ]] && CMD="movetoworkspace $WORKSPACE_NUM"
    hyprctl --batch "dispatch $CMD" >/dev/null 2>&1
    exit 0
fi

# -----------------------------------------------------------------------------
# PREP FUNCTIONS
# -----------------------------------------------------------------------------
handle_wallpaper_prep() {
    resolve_src_dir
    mkdir -p "$THUMB_DIR"
    (
        for thumb in "$THUMB_DIR"/*; do
            [ -e "$thumb" ] || continue
            filename=$(basename "$thumb")
            clean_name="${filename#000_}"
            if [ ! -f "$SRC_DIR/$clean_name" ]; then rm -f "$thumb"; fi
        done

        for img in "$SRC_DIR"/*.{jpg,jpeg,png,webp,gif,mp4,mkv,mov,webm}; do
            [ -e "$img" ] || continue
            filename=$(basename "$img")
            extension="${filename##*.}"

            if [[ "${extension,,}" == "webp" ]]; then
                new_img="${img%.*}.jpg"
                magick "$img" "$new_img"
                rm -f "$img"
                img="$new_img"
                filename=$(basename "$img")
                extension="jpg"
            fi

            if [[ "${extension,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
                thumb="$THUMB_DIR/000_$filename"
                [ -f "$THUMB_DIR/$filename" ] && rm -f "$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                     ffmpeg -y -ss 00:00:05 -i "$img" -vframes 1 -f image2 -q:v 2 "$thumb" > /dev/null 2>&1
                fi
            else
                thumb="$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                    magick "$img" -resize x420 -quality 70 "$thumb"
                fi
            fi
        done
    ) &

    TARGET_THUMB=""
    CURRENT_SRC=""

    if pgrep -a "mpvpaper" > /dev/null; then
        # More resilient extraction: grab any valid video path
        CURRENT_SRC=$(pgrep -a mpvpaper | grep -oE "/[^' ]+" | grep -E "\.(mp4|mkv|mov|webm)$" | head -n1)
        CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi

    if [ -z "$CURRENT_SRC" ] && command -v awww >/dev/null; then
        # Bulletproof extraction: Ignore the folder structure and strip exactly what comes after "image: "
        CURRENT_SRC=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1 | tr -d '"' | tr -d "'")
        CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi

    if [ -n "$CURRENT_SRC" ]; then
        EXT="${CURRENT_SRC##*.}"
        if [[ "${EXT,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
            TARGET_THUMB="000_$CURRENT_SRC"
        else
            TARGET_THUMB="$CURRENT_SRC"
        fi
    fi
    
    export WALLPAPER_THUMB="$TARGET_THUMB"
}

handle_network_prep() {
    echo "" > "$BT_SCAN_LOG"
    [ -f "$BT_PID_FILE" ] && kill $(cat "$BT_PID_FILE") 2>/dev/null
    {
        echo "scan on"
        sleep 4
        while read -r w < /tmp/qs_active_widget && [ "$w" == "network" ]; do sleep 2; done
        echo "scan off"
        sleep 1
    } | stdbuf -oL bluetoothctl > "$BT_SCAN_LOG" 2>&1 &
    echo $! > "$BT_PID_FILE"
    (nmcli device wifi rescan) &
}

# -----------------------------------------------------------------------------
# ZOMBIE WATCHDOG
# -----------------------------------------------------------------------------
MAIN_QML_PATH="$HOME/.config/hypr/scripts/quickshell/Main.qml"
BAR_QML_PATH="$HOME/.config/hypr/scripts/quickshell/TopBar.qml"
ALARM_QML_PATH="$HOME/.config/hypr/scripts/quickshell/BatteryAlarm.qml"
SCRATCHPAD_HOST_PATH="$HOME/.config/hypr/scripts/quickshell/ScratchpadHost.qml"
KB_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/KbOsd.qml"
ACCT_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/AcctOsd.qml"
IDLE_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/IdleOsd.qml"
WAKELOCK_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/WakeLockOsd.qml"
BRIGHTNESS_CURVE_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/BrightnessCurveOsd.qml"
VOLUME_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/VolumeOsd.qml"
CAPS_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/CapsOsd.qml"
MIC_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/MicOsd.qml"
BRIGHTNESS_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/BrightnessOsd.qml"
SPOTIFY_VOLUME_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/SpotifyVolumeOsd.qml"
MEDIA_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/MediaOsd.qml"
NIGHT_LIGHT_OSD_PATH="$HOME/.config/hypr/scripts/quickshell/NightLightOsd.qml"
AMBIENT_GLOW_PATH="$HOME/.config/hypr/scripts/quickshell/AmbientGlow.qml"

QS_PROCS=""
watchdog_ensure_one() {
    local name="$1"
    local path="$2"
    local pids
    mapfile -t pids < <(awk -v n="/$name" '$2 == "quickshell" && $3 == "-p" && NF == 4 && substr($4, length($4) - length(n) + 1) == n { print $1 }' <<< "$QS_PROCS" | sort -n)
    local count=${#pids[@]}
    if [ "$count" -eq 0 ]; then
        quickshell -p "$path" >/dev/null 2>&1 &
        disown
    elif [ "$count" -gt 1 ]; then
        # Keep newest (highest PID), kill stale duplicates
        for ((i=0; i<count-1; i++)); do
            kill "${pids[$i]}" 2>/dev/null
        done
    fi
}

run_watchdog() {
    QS_PROCS=$(pgrep -ax quickshell 2>/dev/null)
    watchdog_ensure_one "Main.qml" "$MAIN_QML_PATH"
    watchdog_ensure_one "TopBar.qml" "$BAR_QML_PATH"
    watchdog_ensure_one "BatteryAlarm.qml" "$ALARM_QML_PATH"
    watchdog_ensure_one "AmbientGlow.qml" "$AMBIENT_GLOW_PATH"
    watchdog_ensure_one "ScratchpadHost.qml" "$SCRATCHPAD_HOST_PATH"
    watchdog_ensure_one "KbOsd.qml" "$KB_OSD_PATH"
    watchdog_ensure_one "AcctOsd.qml" "$ACCT_OSD_PATH"
    watchdog_ensure_one "IdleOsd.qml" "$IDLE_OSD_PATH"
    watchdog_ensure_one "WakeLockOsd.qml" "$WAKELOCK_OSD_PATH"
    watchdog_ensure_one "BrightnessCurveOsd.qml" "$BRIGHTNESS_CURVE_OSD_PATH"
    watchdog_ensure_one "VolumeOsd.qml" "$VOLUME_OSD_PATH"
    watchdog_ensure_one "CapsOsd.qml" "$CAPS_OSD_PATH"
    watchdog_ensure_one "MicOsd.qml" "$MIC_OSD_PATH"
    watchdog_ensure_one "BrightnessOsd.qml" "$BRIGHTNESS_OSD_PATH"
    watchdog_ensure_one "SpotifyVolumeOsd.qml" "$SPOTIFY_VOLUME_OSD_PATH"
    watchdog_ensure_one "MediaOsd.qml" "$MEDIA_OSD_PATH"
    watchdog_ensure_one "NightLightOsd.qml" "$NIGHT_LIGHT_OSD_PATH"
}

# The full watchdog is 17 pgrep scans (seconds under load) — only run it inline when
# Main itself is missing (so the IPC write isn't lost); otherwise defer it to after
# the IPC write, throttled to once per 30s.
WD_STAMP="${XDG_RUNTIME_DIR:-/tmp}/qs_watchdog_stamp"
deferred_watchdog() {
    local now last
    now=$(date +%s)
    last=$(cat "$WD_STAMP" 2>/dev/null || echo 0)
    if [ $((now - last)) -ge 30 ]; then
        echo "$now" > "$WD_STAMP"
        ( run_watchdog ) >/dev/null 2>&1 &
        disown
    fi
}
MAIN_PID_CACHE="${XDG_RUNTIME_DIR:-/tmp}/qs_main_pid"
main_alive() {
    local pid
    pid=$(cat "$MAIN_PID_CACHE" 2>/dev/null)
    if [ -n "$pid" ] && [ "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" == "quickshell -p $MAIN_QML_PATH " ]; then
        return 0
    fi
    pid=$(pgrep -fx "quickshell -p $MAIN_QML_PATH" 2>/dev/null | head -n1)
    [ -n "$pid" ] || return 1
    echo "$pid" > "$MAIN_PID_CACHE"
}
if main_alive; then
    trap deferred_watchdog EXIT
else
    run_watchdog
fi

# -----------------------------------------------------------------------------
# IPC ROUTING (No hyprctl focus/move commands needed!)
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "close" ]]; then
    echo "close" > "$IPC_FILE"
    if [[ "$TARGET" == "network" || "$TARGET" == "all" || -z "$TARGET" ]]; then
        if [ -f "$BT_PID_FILE" ]; then
            kill $(cat "$BT_PID_FILE") 2>/dev/null
            rm -f "$BT_PID_FILE"
        fi
        (bluetoothctl scan off > /dev/null 2>&1) &
    fi
    exit 0
fi

if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    ACTIVE_WIDGET=$(cat /tmp/qs_active_widget 2>/dev/null)
    CURRENT_MODE=$(cat "$NETWORK_MODE_FILE" 2>/dev/null)

    if [[ "$TARGET" == "network" ]]; then
        if [[ "$ACTION" == "toggle" && "$ACTIVE_WIDGET" == "network" ]]; then
            if [[ -n "$SUBTARGET" ]]; then
                if [[ "$CURRENT_MODE" == "$SUBTARGET" ]]; then
                    echo "close" > "$IPC_FILE"
                else
                    echo "$SUBTARGET" > "$NETWORK_MODE_FILE"
                    echo "$TARGET" > "$IPC_FILE"
                fi
            else
                echo "close" > "$IPC_FILE"
            fi
        else
            handle_network_prep
            [[ -n "$SUBTARGET" ]] && echo "$SUBTARGET" > "$NETWORK_MODE_FILE"
            echo "$TARGET" > "$IPC_FILE"
        fi
        exit 0
    fi

    if [[ "$ACTION" == "toggle" && "$ACTIVE_WIDGET" == "$TARGET" ]]; then
        echo "close" > "$IPC_FILE"
        exit 0
    fi

    if [[ "$TARGET" == "wallpaper" ]]; then
        handle_wallpaper_prep
        echo "$TARGET:$WALLPAPER_THUMB" > "$IPC_FILE"
    elif [[ "$TARGET" == "quicktell" || "$TARGET" == "leader" ]]; then
        if [[ -n "$SUBTARGET" ]]; then echo "$TARGET:$SUBTARGET" > "$IPC_FILE"; else echo "$TARGET" > "$IPC_FILE"; fi
    elif [[ "$TARGET" == "workspaces" ]]; then
        echo "$TARGET" > "$IPC_FILE"
        (
            MON_JSON=$(hyprctl monitors -j 2>/dev/null)
            GEO=$(echo "$MON_JSON" | jq -r '.[0] | "\(.x),\(.y) \(.width)x\(.height)"')
            SPECIAL_ID=$(echo "$MON_JSON" | jq -r '.[0].specialWorkspace.id')
            SPECIAL_NAME=$(echo "$MON_JSON" | jq -r '.[0].specialWorkspace.name' | sed 's/special://')
            mkdir -p /tmp/ws_thumbs
            if [ -n "$GEO" ]; then
                if [ "$SPECIAL_ID" != "0" ] && [ -n "$SPECIAL_NAME" ]; then
                    grim -g "$GEO" - 2>/dev/null | magick - -resize 50% "/tmp/ws_thumbs/ws_special_${SPECIAL_NAME}.png" 2>/dev/null
                else
                    ACTIVE=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
                    [ -n "$ACTIVE" ] && \
                        grim -g "$GEO" - 2>/dev/null | magick - -resize 50% "/tmp/ws_thumbs/ws_${ACTIVE}.png" 2>/dev/null
                fi
            fi
        ) &
    elif [[ "$TARGET" == "guide" ]]; then
        if [[ -n "$SUBTARGET" ]]; then echo "$TARGET:$SUBTARGET" > "$IPC_FILE"; else echo "$TARGET" > "$IPC_FILE"; fi
    else
        echo "$TARGET" > "$IPC_FILE"
    fi
    exit 0
fi
