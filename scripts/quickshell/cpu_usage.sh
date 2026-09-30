#!/usr/bin/env bash
# Continuous CPU% sampler — reads /proc/stat deltas every 2s and prints one
# integer percentage per line. Long-lived loop process (same shape as
# sys_toggles.sh's poller in TopBar.qml) instead of a one-shot script, since a
# one-shot can't compute a delta by itself without sleeping twice per call.
prev_idle=0
prev_total=0
first=1

while true; do
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    idle_all=$((idle + iowait))
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    if [ "$first" -eq 0 ]; then
        diff_idle=$((idle_all - prev_idle))
        diff_total=$((total - prev_total))
        if [ "$diff_total" -gt 0 ]; then
            pct=$(( (1000 * (diff_total - diff_idle) / diff_total + 5) / 10 ))
            [ "$pct" -lt 0 ] && pct=0
            [ "$pct" -gt 100 ] && pct=100
            echo "$pct"
        fi
    fi

    prev_idle=$idle_all
    prev_total=$total
    first=0
    sleep 2
done
