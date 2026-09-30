#!/usr/bin/env bash
# Continuous net up/down rate sampler — same long-lived-loop shape as
# cpu_usage.sh, computing a delta every 2s from /sys/class/net rather than
# spawning a fresh process per poll. Prints one compact JSON line per sample:
#   {"down":<bytes/sec>,"up":<bytes/sec>}
# Auto-picks the active (non-loopback, UP, has a default route) interface
# each cycle so it follows the user hopping between wifi/ethernet.

get_iface() {
    ip route 2>/dev/null | awk '/^default/ {print $5; exit}'
}

prev_rx=0
prev_tx=0
prev_iface=""

while true; do
    iface=$(get_iface)
    if [ -z "$iface" ]; then
        sleep 2
        continue
    fi

    rx=$(cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null)
    tx=$(cat "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null)

    if [ -n "$rx" ] && [ -n "$tx" ] && [ "$iface" = "$prev_iface" ] && [ "$prev_rx" != "0" ]; then
        down=$(( (rx - prev_rx) / 2 ))
        up=$(( (tx - prev_tx) / 2 ))
        [ "$down" -lt 0 ] && down=0
        [ "$up" -lt 0 ] && up=0
        echo "{\"down\":${down},\"up\":${up}}"
    fi

    prev_rx=$rx
    prev_tx=$tx
    prev_iface=$iface
    sleep 2
done
