#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# holdaction_run.sh — hold-to-confirm timer/executor, quickshell-independent.
#
# Runs entirely off Hyprland's own bind/bindr — no dependency on quickshell
# being alive. Reads action metadata (holdSeconds/cmd/glowHex/...) from
# registry.json via jq, times the hold in a detached process group, and
# fires `cmd` if the key is held for the full duration. Progress is mirrored
# to a state file purely for optional UI (TopBar glow) — nothing here waits
# on quickshell to read it.
#
# Usage:
#   holdaction_run.sh start <name>   # bind  (keydown)
#   holdaction_run.sh abort <name>   # bindr (keyup)
# -----------------------------------------------------------------------------

REGISTRY="$HOME/.config/hypr/scripts/quickshell/holdactions/registry.json"
STATE_FILE="/tmp/qs_holdaction_state.json"
STEP=0.03

MODE="$1"
NAME="$2"
PID_FILE="/tmp/qs_holdaction_${NAME}.pid"

[ -z "$NAME" ] && exit 1

write_state() {
    printf '%s\n' "$1" > "$STATE_FILE" 2>/dev/null
}

case "$MODE" in
start)
    ENTRY=$(jq -c --arg n "$NAME" '.actions[] | select(.name == $n)' "$REGISTRY")
    [ -z "$ENTRY" ] && exit 1

    HOLD_SECONDS=$(jq -r '.holdSeconds // 1.5' <<<"$ENTRY")
    GLOW_HEX=$(jq -r '.glowHex // "#f38ba8"' <<<"$ENTRY")
    LABEL=$(jq -r '.label // ""' <<<"$ENTRY")
    CMD=$(jq -r '.cmd // ""' <<<"$ENTRY")
    [ -z "$CMD" ] && exit 1

    # stale run from this same action? kill it before starting fresh
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$OLD_PID" ] && kill -TERM "-$OLD_PID" 2>/dev/null
        rm -f "$PID_FILE"
    fi

    setsid bash -c '
        name="$1"; hold="$2"; glow="$3"; label="$4"; cmd="$5"; state="$6"; step="$7"; pidfile="$8"
        steps=$(awk -v h="$hold" -v s="$step" "BEGIN { n = h / s; print (n < 1) ? 1 : int(n) }")
        printf "{\"name\":\"%s\",\"phase\":\"start\",\"progress\":0,\"holdSeconds\":%s,\"glowHex\":\"%s\",\"label\":\"%s\"}\n" \
            "$name" "$hold" "$glow" "$label" > "$state" 2>/dev/null

        i=0
        while [ "$i" -lt "$steps" ]; do
            sleep "$step"
            i=$((i + 1))
            progress=$(awk -v i="$i" -v n="$steps" "BEGIN { printf \"%.4f\", i / n }")
            printf "{\"name\":\"%s\",\"phase\":\"progress\",\"progress\":%s,\"holdSeconds\":%s,\"glowHex\":\"%s\",\"label\":\"%s\"}\n" \
                "$name" "$progress" "$hold" "$glow" "$label" > "$state" 2>/dev/null
        done

        printf "{\"name\":\"%s\",\"phase\":\"complete\",\"progress\":1,\"holdSeconds\":%s,\"glowHex\":\"%s\",\"label\":\"%s\"}\n" \
            "$name" "$hold" "$glow" "$label" > "$state" 2>/dev/null
        rm -f "$pidfile"

        eval "$cmd"
    ' _ "$NAME" "$HOLD_SECONDS" "$GLOW_HEX" "$LABEL" "$CMD" "$STATE_FILE" "$STEP" "$PID_FILE" \
        </dev/null &>/tmp/qs_holdaction_${NAME}.log &

    echo $! > "$PID_FILE"
    ;;

abort)
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            kill -TERM "-$PID" 2>/dev/null
            ENTRY=$(jq -c --arg n "$NAME" '.actions[] | select(.name == $n)' "$REGISTRY" 2>/dev/null)
            GLOW_HEX=$(jq -r '.glowHex // "#f38ba8"' <<<"$ENTRY" 2>/dev/null)
            printf '{"name":"%s","phase":"abort","progress":0,"glowHex":"%s"}\n' "$NAME" "$GLOW_HEX" > "$STATE_FILE" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
    ;;
esac
