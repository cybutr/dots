#!/usr/bin/env bash

TMP_DIR="/tmp/eww_covers"
mkdir -p "$TMP_DIR"
PLACEHOLDER="$TMP_DIR/placeholder_blank.png"

CACHE_FILE="$HOME/.config/hypr/scripts/quickshell/music/song_cache.json"
CACHE_LOCK="$CACHE_FILE.lock"
CACHE_CAP=100000  # each entry is a few bytes (hex colors + bpm + ts) — effectively unbounded, just a sanity ceiling
[ -f "$CACHE_FILE" ] || echo '{}' > "$CACHE_FILE"

cache_get() {
    local hash="$1"
    jq -c --arg h "$hash" '.[$h] // {}' "$CACHE_FILE" 2>/dev/null
}

# Atomic read-modify-write: merges $2 (a JSON object) into cache[$1], stamps
# ts for eviction, writes via tmpfile+mv (atomic rename, same filesystem) so
# concurrent invocations (TopBar + MusicPopup can both shell out to this
# script at once) never see a half-written file. flock serializes the RMW
# itself so two racing writers don't clobber each other's merge.
cache_set() {
    local hash="$1" updateJson="$2"
    (
        flock -x 200
        local current now merged tmp
        current=$(cat "$CACHE_FILE" 2>/dev/null)
        [ -n "$current" ] || current='{}'
        now=$(date +%s)
        merged=$(echo "$current" | jq -c --arg h "$hash" --argjson upd "$updateJson" --argjson ts "$now" '
            .[$h] = ((.[$h] // {}) + $upd + {ts: $ts})
            | if (keys | length) > '"$CACHE_CAP"' then
                (to_entries | sort_by(.value.ts) | .[-'"$CACHE_CAP"':] | from_entries)
              else . end
        ')
        if [ -n "$merged" ]; then
            tmp=$(mktemp "${CACHE_FILE}.XXXXXX")
            echo "$merged" > "$tmp"
            mv -f "$tmp" "$CACHE_FILE"
        fi
    ) 200>"$CACHE_LOCK"
}

# --- 1. ENSURE PLACEHOLDER EXISTS ---
if [ ! -f "$PLACEHOLDER" ]; then
    convert -size 500x500 xc:"#313244" "$PLACEHOLDER"
fi

# --- 2. CHECK STATUS ---
STATUS=$(playerctl status --player=spotify 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then

    # --- 3. GET INFO ---
    rawUrl=$(playerctl metadata --player=spotify mpris:artUrl 2>/dev/null)
    title=$(playerctl metadata --player=spotify xesam:title 2>/dev/null)
    artist=$(playerctl metadata --player=spotify xesam:artist 2>/dev/null)

    # Generate Hash
    idStr="${title:-unknown}-${artist:-unknown}"
    trackHash=$(echo "$idStr" | md5sum | cut -d" " -f1)

    # --- Play history log (append-only JSONL, one line per track START) ---
    # This script runs on every poll/dbus signal — far more often than once
    # per song — so logging needs its own cheap dedup, not "log every call".
    # A small state file holding the last hash we logged is enough: only
    # write a new history line when the track actually changed (and only
    # while genuinely Playing, not just sitting Paused on the same song).
    # Deliberately independent of song_cache.json (which is a per-track
    # lookup keyed by hash, overwritten in place — colors/bpm/last-seen, not
    # a timeline) — this is the append-only "what did I actually listen to
    # and when" log that the recently-played/most-played/etc features read.
    if [ "$STATUS" = "Playing" ] && [ -n "$title" ]; then
        lastLoggedHash=$(cat /tmp/qs_last_logged_track 2>/dev/null)
        if [ "$lastLoggedHash" != "$trackHash" ]; then
            echo "$trackHash" > /tmp/qs_last_logged_track
            # mpris:length is microseconds; convert to whole seconds so
            # music_stats.py can sum real listening time. Entries logged
            # before this field existed simply lack it (excluded from the
            # time total, not counted as zero).
            lengthUs=$(playerctl metadata --player=spotify mpris:length 2>/dev/null)
            durationSec=""
            if [ -n "$lengthUs" ] && [ "$lengthUs" -gt 0 ] 2>/dev/null; then
                durationSec=$((lengthUs / 1000000))
            fi
            jq -nc --arg ts "$(date +%s)" --arg artist "$artist" --arg title "$title" --arg hash "$trackHash" --arg dur "$durationSec" \
                '{ts: ($ts|tonumber), artist: $artist, title: $title, hash: $hash} + (if $dur != "" then {durationSec: ($dur|tonumber)} else {} end)' \
                >> "$HOME/.config/hypr/scripts/quickshell/music/play_history.jsonl" 2>/dev/null
        fi
    fi

    finalArt="$TMP_DIR/${trackHash}_art.jpg"
    blurPath="$TMP_DIR/${trackHash}_blur.png"
    colorPath="$TMP_DIR/${trackHash}_grad.txt"
    vibrantPath="$TMP_DIR/${trackHash}_vibrant.txt"
    textPath="$TMP_DIR/${trackHash}_text.txt"
    lockFile="$TMP_DIR/${trackHash}.lock"
    bpmPath="$TMP_DIR/${trackHash}_bpm.txt"
    bpmLock="$TMP_DIR/${trackHash}_bpm.lock"

    # Default display values (Placeholder)
    displayArt="$PLACEHOLDER"
    displayBlur="$PLACEHOLDER"
    displayGrad="linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)"
    displayVibrant="$displayGrad"
    displayText="#cdd6f4"
    displayBpm=0

    # Persistent cross-session cache (song_cache.json, keyed by trackHash) —
    # checked first so a repeat play of a song already analyzed in a past
    # session gets correct colors/bpm instantly instead of waiting on a
    # fresh art download/quantize/analysis. Also warms the per-boot /tmp
    # cache files so subsequent invocations this session hit the fast path.
    cachedEntry=$(cache_get "$trackHash")
    cachedGrad=$(echo "$cachedEntry" | jq -r '.grad // empty')
    cachedVibrant=$(echo "$cachedEntry" | jq -r '.vibrantGrad // empty')
    cachedText=$(echo "$cachedEntry" | jq -r '.textColor // empty')
    cachedBpm=$(echo "$cachedEntry" | jq -r '.bpm // empty')

    if [ -n "$cachedGrad" ] && [ ! -f "$colorPath" ]; then
        echo "$cachedGrad" > "$colorPath"
    fi
    if [ -n "$cachedVibrant" ] && [ ! -f "$vibrantPath" ]; then
        echo "$cachedVibrant" > "$vibrantPath"
    fi
    if [ -n "$cachedText" ] && [ ! -f "$textPath" ]; then
        echo "$cachedText" > "$textPath"
    fi
    if [ -n "$cachedBpm" ] && [ "$cachedBpm" != "null" ] && [ ! -f "$bpmPath" ]; then
        echo "$cachedBpm" > "$bpmPath"
    fi

    # --- BPM ANALYSIS (async, cached per track) ---
    if [ -f "$bpmPath" ]; then
        displayBpm=$(cat "$bpmPath" 2>/dev/null)
        [ -z "$displayBpm" ] && displayBpm=0
    elif [ "$STATUS" = "Playing" ] && [ ! -f "$bpmLock" ]; then
        touch "$bpmLock"
        (
            python3 "$HOME/.config/hypr/scripts/quickshell/music/bpm_detect.py" "$bpmPath"
            if [ -s "$bpmPath" ]; then
                bpmVal=$(cat "$bpmPath")
                cache_set "$trackHash" "{\"bpm\": $bpmVal}"
            fi
            rm -f "$bpmLock"
        ) </dev/null >/dev/null 2>&1 &
        disown
    fi

    # --- 4. ASYNC BACKGROUND LOGIC ---
    if [ -f "$finalArt" ] && [ -s "$finalArt" ]; then
        # Cache Hit: Use the real files
        displayArt="$finalArt"
        # Only use blur/colors if they are ready too
        if [ -f "$blurPath" ]; then displayBlur="$blurPath"; fi
        if [ -f "$colorPath" ]; then displayGrad=$(cat "$colorPath"); fi
        if [ -f "$vibrantPath" ]; then displayVibrant=$(cat "$vibrantPath"); fi
        if [ -f "$textPath" ]; then displayText=$(cat "$textPath"); fi
    else
        # No local art thumbnail yet this session — but if the persistent
        # cache already had colors for this track, show those immediately
        # instead of the generic purple fallback while art downloads.
        if [ -n "$cachedGrad" ]; then displayGrad="$cachedGrad"; fi
        if [ -n "$cachedVibrant" ]; then displayVibrant="$cachedVibrant"; fi
        if [ -n "$cachedText" ]; then displayText="$cachedText"; fi

        # Cache Miss: Trigger Background Download
        # We only spawn if not already downloading (checked via lockFile)
        if [ ! -f "$lockFile" ] && [ -n "$rawUrl" ]; then
            touch "$lockFile"
            (
                # A. Download/Copy Source
                if [[ "$rawUrl" == http* ]]; then
                    curl -s -L --max-time 10 -o "$finalArt" "$rawUrl"
                else
                    cleanPath=$(echo "$rawUrl" | sed 's/file:\/\///g')
                    if [ -f "$cleanPath" ]; then
                        cp "$cleanPath" "$finalArt"
                    else
                        # Invalid local file
                        cp "$PLACEHOLDER" "$finalArt"
                    fi
                fi

                # B. Validate Download
                if [ ! -s "$finalArt" ]; then
                    cp "$PLACEHOLDER" "$finalArt"
                fi

                # C. Generate Effects (Blur & Colors)
                # Check if it's just the placeholder
                # (FIXED: securely stripping alpha to prevent empty strings)
                isPlaceholder=$(convert "$finalArt" -format "%[hex:u.p{0,0}]" info: 2>/dev/null | cut -c1-6)

                if [[ "$isPlaceholder" == "313244" ]] || [[ -z "$isPlaceholder" ]]; then
                    cp "$finalArt" "$blurPath"
                    # Keep default colors
                else
                    convert "$finalArt" -blur 0x20 -brightness-contrast -30x-10 "$blurPath" 2>/dev/null

                    # Colors/text already known from the persistent cache —
                    # skip re-quantizing, the files were pre-warmed above.
                    # (vibrantPath included in the guard so a cache entry
                    # written before vibrancy detection existed still gets it
                    # computed once, instead of being stuck without it forever.)
                    if [ -f "$colorPath" ] && [ -f "$textPath" ] && [ -f "$vibrantPath" ]; then
                        :
                    else
                        # FIXED: Added -alpha off and +dither to prevent ImageMagick from leaking RGBA 8-digit hex codes
                        # which broke QML parsing and extraction arrays.
                        colors=$(convert "$finalArt" -resize 50x50 -alpha off +dither -quantize RGB -colors 3 -depth 8 -format "%c" histogram:info: 2>/dev/null | grep -E -o '#[0-9A-Fa-f]{6}' | head -n 3 | tr '\n' ' ')
                        read -r -a color_array <<< "$colors"

                        c1=${color_array[0]:-#cba6f7}
                        c2=${color_array[1]:-$c1}
                        c3=${color_array[2]:-$c1}

                        grad="linear-gradient(45deg, $c1, $c2, $c3, $c1)"
                        echo "$grad" > "$colorPath"

                        # Vibrancy — the quantized colors above are the most
                        # FREQUENT pixels (dominant), not the most saturated,
                        # so a dark/muted cover gives genuinely dark/muted bars
                        # with no alternative in that set. Requantize with more
                        # candidates and pick the most saturated ones instead —
                        # gives the "Vibrant" visualizer color source (Guide →
                        # Settings → Media & Audio) something real to select.
                        vibrantColors=$(convert "$finalArt" -resize 50x50 -alpha off +dither -quantize RGB -colors 8 -depth 8 -format "%c" histogram:info: 2>/dev/null | grep -E -o '#[0-9A-Fa-f]{6}')
                        vibrantPick=$(python3 -c "
import sys, colorsys
hexes = list(dict.fromkeys(sys.argv[1:]))  # de-dupe, keep order
def sat(h):
    h = h.lstrip('#')
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    _, l, s = colorsys.rgb_to_hls(r, g, b)
    # Weight down near-black/near-white candidates even if 'saturated' in
    # the HSL sense — a saturation-sorted list alone still surfaces e.g.
    # near-black-with-a-tint as 'vibrant', which is exactly the bug this
    # is meant to fix.
    return s * (1 - abs(l - 0.5) * 1.2)
hexes.sort(key=sat, reverse=True)
print(' '.join(hexes[:3]) if hexes else '')
" $vibrantColors 2>/dev/null)
                        read -r -a vibrant_array <<< "$vibrantPick"
                        v1=${vibrant_array[0]:-$c1}
                        v2=${vibrant_array[1]:-$v1}
                        v3=${vibrant_array[2]:-$v1}
                        vibrantGrad="linear-gradient(45deg, $v1, $v2, $v3, $v1)"
                        echo "$vibrantGrad" > "$vibrantPath"

                        # FIXED: Securely stripping alpha outputs and strictly demanding a 6 char hex sequence
                        opp_raw=$(convert xc:"$c1" -alpha off -negate -depth 8 -format "%[hex:u]" info: 2>/dev/null | grep -E -o '[0-9A-Fa-f]{6}' | head -n 1)
                        if [ -n "$opp_raw" ]; then
                            textCol="#$opp_raw"
                        else
                            textCol="#cdd6f4"
                        fi
                        echo "$textCol" > "$textPath"

                        cache_set "$trackHash" "{\"grad\": $(printf '%s' "$grad" | jq -R .), \"vibrantGrad\": $(printf '%s' "$vibrantGrad" | jq -R .), \"textColor\": $(printf '%s' "$textCol" | jq -R .)}"
                    fi
                fi

                # D. Cleanup
                rm "$lockFile"
                # Housekeeping: keep only recent 20 files
                (cd "$TMP_DIR" && ls -1t | tail -n +21 | xargs -r rm 2>/dev/null)
            ) </dev/null >/dev/null 2>&1 &
            disown
        fi
        # While background job runs, we proceed to output the PLACEHOLDER (or
        # persistent-cache colors, computed above) immediately
    fi


    # --- 5. TIMING & DEVICE INFO ---
    metadata=$(playerctl metadata --player=spotify --format '{{mpris:length}} {{position}}' 2>/dev/null)
    len_micro=$(echo "$metadata" | awk '{print $1}')
    pos_micro=$(echo "$metadata" | awk '{print $2}')

    if [ -z "$len_micro" ] || [ "$len_micro" -eq 0 ]; then len_micro=1000000; fi
    len_sec=$((len_micro / 1000000))
    pos_sec=$((pos_micro / 1000000))
    percent=$((pos_sec * 100 / len_sec))
    pos_str=$(printf "%02d:%02d" $((pos_sec/60)) $((pos_sec%60)))
    len_str=$(printf "%02d:%02d" $((len_sec/60)) $((len_sec%60)))
    time_str="${pos_str} / ${len_str}"

    player_raw=$(playerctl status --player=spotify -f "{{playerName}}" 2>/dev/null | head -n 1)
    player_nice="${player_raw^}"

    # Audio Device
    sink_name=$(pactl get-default-sink 2>/dev/null)
    dev_icon="󰓃"; dev_name="Speaker"
    if [[ "$sink_name" == *"bluez"* ]]; then
        dev_icon="󰂯"
        readable_name=$(pactl list sinks | grep -A 20 "$sink_name" | grep -m 1 "Description:" | cut -d: -f2 | xargs)
        if [ -n "$readable_name" ]; then dev_name="$readable_name"; else dev_name="Bluetooth"; fi
    elif [[ "$sink_name" == *"usb"* ]]; then
        dev_icon="󰓃"; dev_name="USB Audio"
    elif [[ "$sink_name" == *"pci"* ]]; then
        dev_icon="󰓃"; dev_name="System"
    fi

    # --- 6. JSON OUTPUT ---
    jq -n -c \
        --arg title "$title" \
        --arg artist "$artist" \
        --arg status "$STATUS" \
        --arg len "$len_sec" \
        --arg pos "$pos_sec" \
        --arg len_str "$len_str" \
        --arg pos_str "$pos_str" \
        --arg time_str "$time_str" \
        --arg percent "$percent" \
        --arg source "$player_nice" \
        --arg pname "$player_raw" \
        --arg blur "$displayBlur" \
        --arg grad "$displayGrad" \
        --arg vibrantGrad "$displayVibrant" \
        --arg txtColor "$displayText" \
        --arg devIcon "$dev_icon" \
        --arg devName "$dev_name" \
        --arg finalArt "$displayArt" \
        --argjson bpm "${displayBpm:-0}" \
        '{
            title: $title,
            artist: $artist,
            status: $status,
            length: $len,
            position: $pos,
            lengthStr: $len_str,
            positionStr: $pos_str,
            timeStr: $time_str,
            percent: $percent,
            source: $source,
            playerName: $pname,
            blur: $blur,
            grad: $grad,
            vibrantGrad: $vibrantGrad,
            textColor: $txtColor,
            deviceIcon: $devIcon,
            deviceName: $devName,
            artUrl: $finalArt,
            bpm: $bpm
        }'

else
    # Fallback
    jq -n -c \
    --arg placeholder "$PLACEHOLDER" \
    '{
        title: "Not Playing",
        artist: "",
        status: "Stopped",
        percent: 0,
        lengthStr: "00:00",
        positionStr: "00:00",
        timeStr: "--:-- / --:--",
        source: "Offline",
        playerName: "",
        blur: $placeholder,
        grad: "linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)",
        textColor: "#cdd6f4",
        deviceIcon: "󰓃",
        deviceName: "Speaker",
        artUrl: $placeholder,
        bpm: 0
    }'
fi
