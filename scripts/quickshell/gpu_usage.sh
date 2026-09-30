#!/usr/bin/env bash
# Continuous GPU%[,temp] sampler — mirrors cpu_usage.sh's long-lived-loop shape
# instead of a spawn-per-poll script. Auto-detects nvidia vs amd. Prints
# "usage" or "usage,temp" per line every 2s. If no GPU is detectable, exits
# immediately (prints nothing) so the caller's pill just never gets a value
# and stays hidden.

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    while true; do
        line=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)
        util=$(echo "$line" | cut -d',' -f1 | tr -d ' ')
        temp=$(echo "$line" | cut -d',' -f2 | tr -d ' ')
        if [ -n "$util" ]; then
            if [ -n "$temp" ]; then echo "${util},${temp}"; else echo "$util"; fi
        fi
        sleep 2
    done
    exit 0
fi

card=$(ls -d /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1)
if [ -n "$card" ]; then
    hwmon_temp=$(ls "${card%/gpu_busy_percent}"/hwmon/hwmon*/temp1_input 2>/dev/null | head -n1)
    while true; do
        util=$(cat "$card" 2>/dev/null)
        if [ -n "$util" ]; then
            if [ -n "$hwmon_temp" ]; then
                raw=$(cat "$hwmon_temp" 2>/dev/null)
                if [ -n "$raw" ]; then echo "${util},$((raw / 1000))"; else echo "$util"; fi
            else
                echo "$util"
            fi
        fi
        sleep 2
    done
    exit 0
fi

# no gpu found — exit silently, pill stays hidden
exit 0
