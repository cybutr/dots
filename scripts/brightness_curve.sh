#!/usr/bin/env bash
# Adaptive display-brightness curve — brightness follows real solar position
# (brightest at solar noon, dimmest at night), recomputed fresh from wall-clock
# time + cached lat/lon every run (no elapsed-time/uptime tracking, so it's
# correct immediately after boot/wake regardless of how long the PC was off).
#
# Sibling feature to night_light.sh (which handles color TEMPERATURE on a
# fixed clock schedule) — this handles actual screen BRIGHTNESS on a solar
# curve. Independent axes, independent state.

SETTINGS="$HOME/.config/hypr/settings.json"
CACHE_DIR="$HOME/.cache/quickshell"
LOC_CACHE="$CACHE_DIR/brightness_location.json"
ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

DISABLE_MARKER="/tmp/qs_brightness_curve_disabled"
LAST_SET_FILE="/tmp/qs_brightness_last_set"
MANUAL_UNTIL_FILE="/tmp/qs_brightness_manual_until"
SELF_WRITE_MARKER="/tmp/qs_brightness_self_write"
IDLE_MARKER="/tmp/qs_pc_idle"            # touched/removed by hypridle's 500s listener
MANUAL_SNOOZE_SECS=7200   # 2h backstop cooldown if the user never actually goes idle
MANUAL_TOLERANCE=3        # percentage points of drift tolerated before treating as "manual"

# --- smooth ramp: step brightness from current to target instead of snapping ---
ramp_to() {
    local from="$1" to="$2" steps=18 i pct
    touch "$SELF_WRITE_MARKER"
    for i in $(seq 1 "$steps"); do
        pct=$(awk -v f="$from" -v t="$to" -v i="$i" -v n="$steps" 'BEGIN { printf "%d", f + (t-f)*i/n }')
        brightnessctl set "${pct}%" >/dev/null 2>&1
        sleep 0.04
    done
    touch "$SELF_WRITE_MARKER"   # refresh timestamp so the watcher's grace window covers the whole ramp
}

mkdir -p "$CACHE_DIR"

# --- feature toggle ---
if [ -f "$DISABLE_MARKER" ]; then
    exit 0
fi

# --- manual-override snooze ---
# While snoozed: leave brightness alone entirely, UNLESS the user has actually
# gone idle (hypridle's 500s listener touches IDLE_MARKER) — idle means it's
# safe to catch back up to the curve right away instead of waiting out the
# full backstop. The backstop only matters if idle never fires for some reason.
now_epoch=$(date +%s)
resuming=0
if [ -f "$MANUAL_UNTIL_FILE" ]; then
    if [ -f "$IDLE_MARKER" ]; then
        rm -f "$MANUAL_UNTIL_FILE"
        resuming=1
    else
        until_epoch=$(cat "$MANUAL_UNTIL_FILE" 2>/dev/null || echo 0)
        if [ -n "$until_epoch" ] && [ "$now_epoch" -lt "$until_epoch" ] 2>/dev/null; then
            exit 0
        fi
        rm -f "$MANUAL_UNTIL_FILE"
        resuming=1
    fi
fi

current_pct=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub("%","",$4); print $4}')
if [ -z "$current_pct" ]; then
    exit 0   # no backlight device available — nothing to do
fi

# --- detect a manual brightness change since our last write ---
# A write we just made ourselves (ramp_to touches SELF_WRITE_MARKER) is never
# mistaken for manual input, even though it also changes current_pct.
self_write_recent=0
if [ -f "$SELF_WRITE_MARKER" ]; then
    sw_epoch=$(stat -c %Y "$SELF_WRITE_MARKER" 2>/dev/null || echo 0)
    [ $(( now_epoch - sw_epoch )) -le 2 ] && self_write_recent=1
fi
if [ "$resuming" -eq 0 ] && [ "$self_write_recent" -eq 0 ] && [ -f "$LAST_SET_FILE" ]; then
    last_set=$(cat "$LAST_SET_FILE" 2>/dev/null || echo "")
    if [ -n "$last_set" ]; then
        diff=$(( current_pct - last_set ))
        diff=${diff#-}
        if [ "$diff" -gt "$MANUAL_TOLERANCE" ]; then
            echo $(( now_epoch + MANUAL_SNOOZE_SECS )) > "$MANUAL_UNTIL_FILE"
            exit 0
        fi
    fi
fi

# --- config ---
BMIN=$(jq -r '.brightnessCurveMin // 15' "$SETTINGS" 2>/dev/null)
BMAX=$(jq -r '.brightnessCurveMax // 100' "$SETTINGS" 2>/dev/null)

# --- location (fetch once, cache forever — city doesn't move) ---
LAT=""
LON=""
if [ -f "$LOC_CACHE" ]; then
    LAT=$(jq -r '.lat // empty' "$LOC_CACHE" 2>/dev/null)
    LON=$(jq -r '.lon // empty' "$LOC_CACHE" 2>/dev/null)
fi

if [ -z "$LAT" ] || [ -z "$LON" ]; then
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs) 2>/dev/null
    fi
    if [ -n "${OPENWEATHER_KEY:-}" ] && [ -n "${OPENWEATHER_CITY_ID:-}" ] && [ "$OPENWEATHER_KEY" != "Skipped" ]; then
        raw=$(curl -sf "http://api.openweathermap.org/data/2.5/weather?id=${OPENWEATHER_CITY_ID}&appid=${OPENWEATHER_KEY}" 2>/dev/null)
        if [ -n "$raw" ]; then
            fetched_lat=$(echo "$raw" | jq -r '.coord.lat // empty' 2>/dev/null)
            fetched_lon=$(echo "$raw" | jq -r '.coord.lon // empty' 2>/dev/null)
            if [ -n "$fetched_lat" ] && [ -n "$fetched_lon" ]; then
                LAT="$fetched_lat"; LON="$fetched_lon"
                jq -n --arg lat "$LAT" --arg lon "$LON" '{lat: ($lat|tonumber), lon: ($lon|tonumber)}' > "$LOC_CACHE"
            fi
        fi
    fi
fi

# --- compute target brightness ---
if [ -n "$LAT" ] && [ -n "$LON" ]; then
    # Real solar-elevation curve (NOAA-style approximation), computed purely
    # from current UTC wall-clock time + cached lat/lon. Normalized so max
    # brightness lands exactly at solar noon regardless of season/latitude.
    utc_doy=$(date -u +%j)
    utc_h=$(date -u +%H); utc_m=$(date -u +%M); utc_s=$(date -u +%S)
    target=$(awk -v lat="$LAT" -v lon="$LON" -v doy="$utc_doy" \
                 -v h="$utc_h" -v m="$utc_m" -v s="$utc_s" \
                 -v bmin="$BMIN" -v bmax="$BMAX" '
        BEGIN {
            pi = atan2(0,-1)
            utcHours = h + m/60 + s/3600
            gamma = 2*pi/365 * (doy - 1 + (utcHours-12)/24)

            eqtime = 229.18*(0.000075 + 0.001868*cos(gamma) - 0.032077*sin(gamma) \
                      - 0.014615*cos(2*gamma) - 0.040849*sin(2*gamma))
            decl = 0.006918 - 0.399912*cos(gamma) + 0.070257*sin(gamma) \
                   - 0.006758*cos(2*gamma) + 0.000907*sin(2*gamma) \
                   - 0.002697*cos(3*gamma) + 0.00148*sin(3*gamma)

            trueSolarMin = utcHours*60 + eqtime + 4*lon
            hourAngleDeg = trueSolarMin/4 - 180
            haRad = hourAngleDeg * pi/180
            latRad = lat * pi/180

            sinElev = sin(latRad)*sin(decl) + cos(latRad)*cos(decl)*cos(haRad)
            maxSinElev = sin(latRad)*sin(decl) + cos(latRad)*cos(decl)

            factor = (maxSinElev > 0) ? sinElev/maxSinElev : 0
            if (factor < 0) factor = 0
            if (factor > 1) factor = 1
            factor = factor ^ 0.75

            target = bmin + (bmax-bmin)*factor
            printf "%d", target
        }')
else
    # Fallback: no location available — fixed cosine curve keyed to local
    # clock time only, peaking at local noon, floor outside ~6am-6pm.
    local_h=$(date +%H); local_m=$(date +%M)
    target=$(awk -v h="$local_h" -v m="$local_m" -v bmin="$BMIN" -v bmax="$BMAX" '
        BEGIN {
            pi = atan2(0,-1)
            hours = h + m/60
            angle = (hours-12)*15*pi/180
            factor = cos(angle)
            if (factor < 0) factor = 0
            target = bmin + (bmax-bmin)*factor
            printf "%d", target
        }')
fi

if [ -n "$target" ] && [ "$target" -ne "$current_pct" ]; then
    ramp_to "$current_pct" "$target"
    echo "$target" > "$LAST_SET_FILE"
fi
