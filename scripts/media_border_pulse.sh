#!/usr/bin/env bash
# Briefly pulses the active Hyprland window border toward a song's accent color,
# then restores the exact original value. Fired by media_seek.sh / media_control.sh
# alongside the MediaOsd trigger.
#
# Correctness under rapid-fire calls:
#   - the ORIGINAL color is captured exactly once per "pulse session" (guarded by an
#     atomic `mkdir`, so a burst of overlapping calls only ever records the color that
#     was active before the FIRST pulse in the burst)
#   - every call still re-applies the pulse color and stamps itself as the "latest"
#     generation
#   - only whichever call is still the latest generation when ITS sleep ends actually
#     restores — older, superseded calls no-op instead of restoring early / fighting
#     the newer pulse
#   - a trap guarantees restore-on-any-exit (including kill/error) for whichever call
#     is holding the session, so a border can never get stuck on the pulse color
set -uo pipefail

ACCENT="${1:-}"
PULSE_MS="${2:-1300}"

SESSION_DIR="/tmp/qs_border_pulse.session"
ORIG_FILE="/tmp/qs_border_pulse.orig"
GEN_FILE="/tmp/qs_border_pulse.gen"

[ -z "$ACCENT" ] && exit 0
ACCENT="${ACCENT#\#}"
[[ "$ACCENT" =~ ^[0-9A-Fa-f]{6}$ ]] || exit 0

# Dark album-art colors (near-black) would make the border pulse basically
# invisible — floor lightness/saturation so it always reads clearly.
ACCENT="$(python3 -c "
import colorsys
r, g, b = (int('$ACCENT'[i:i+2], 16) / 255.0 for i in (0, 2, 4))
h, l, s = colorsys.rgb_to_hls(r, g, b)
l = max(l, 0.55)
s = max(s, 0.4)
r, g, b = colorsys.hls_to_rgb(h, l, s)
print('%02x%02x%02x' % (round(r * 255), round(g * 255), round(b * 255)))
" 2>/dev/null)"
[[ "$ACCENT" =~ ^[0-9A-Fa-f]{6}$ ]] || exit 0

# `hyprctl getoption -j` reports gradients as "AARRGGBBAARRGGBB... angle" (normalized
# AARRGGBB order per stop), but `hyprctl keyword` only accepts rgba(RRGGBBAA)-wrapped
# stops — so capture keeps the raw AARRGGBB form and restore converts each stop back.
get_current_raw() {
    hyprctl getoption general:col.active_border -j 2>/dev/null | jq -r '.custom // empty'
}

to_keyword_value() {
    local raw="$1" angle stops out=""
    angle="${raw##* }"
    stops="${raw% *}"
    for stop in $stops; do
        [ ${#stop} -ne 8 ] && { echo "$raw"; return; }
        local aa="${stop:0:2}" rrggbb="${stop:2:6}"
        out="${out}rgba(${rrggbb}${aa}) "
    done
    echo "${out}${angle}"
}

(
    token="$$-$(date +%s%N)"
    echo "$token" > "$GEN_FILE"

    created_session=0
    if mkdir "$SESSION_DIR" 2>/dev/null; then
        created_session=1
        orig_raw="$(get_current_raw)"
        if [ -z "$orig_raw" ]; then
            rmdir "$SESSION_DIR" 2>/dev/null
            exit 0
        fi
        echo "$orig_raw" > "$ORIG_FILE"
    fi

    restore_if_latest() {
        [ -f "$GEN_FILE" ] || return 0
        current_gen="$(cat "$GEN_FILE" 2>/dev/null)"
        [ "$current_gen" != "$token" ] && return 0
        orig_raw="$(cat "$ORIG_FILE" 2>/dev/null)"
        if [ -n "$orig_raw" ]; then
            hyprctl keyword general:col.active_border "$(to_keyword_value "$orig_raw")" >/dev/null 2>&1
        fi
        rm -f "$ORIG_FILE" "$GEN_FILE"
        rmdir "$SESSION_DIR" 2>/dev/null
    }
    trap restore_if_latest EXIT

    hyprctl keyword general:col.active_border "rgb(${ACCENT})" >/dev/null 2>&1
    sleep "$(awk -v ms="$PULSE_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"
) &
disown
