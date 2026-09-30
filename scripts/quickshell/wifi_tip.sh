#!/usr/bin/env bash
ifc=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')
[ -z "$ifc" ] && exit 0
link=$(iw dev "$ifc" link 2>/dev/null)
ssid=$(echo "$link" | awk -F': ' '/SSID:/{print $2; exit}')
sig=$(echo "$link" | awk '/signal:/{print $2; exit}')
freq=$(echo "$link" | awk '/freq:/{printf "%d", $2; exit}')
rx=$(echo "$link" | awk -F'rx bitrate: ' '/rx bitrate:/{print $2; exit}' | awk '{print $1}')
tx=$(echo "$link" | awk -F'tx bitrate: ' '/tx bitrate:/{print $2; exit}' | awk '{print $1}')
ip=$(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)
gw=$(ip route show default dev "$ifc" 2>/dev/null | awk '{print $3; exit}')
rxb=$(cat /sys/class/net/$ifc/statistics/rx_bytes 2>/dev/null)
txb=$(cat /sys/class/net/$ifc/statistics/tx_bytes 2>/dev/null)
ping_ms=""
if [ -n "$gw" ]; then
    ping_ms=$(ping -c1 -W1 "$gw" 2>/dev/null | awk -F'time=' '/time=/{split($2,a," "); print a[1]; exit}')
fi
radio=$(nmcli radio wifi 2>/dev/null)
nm=$(nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY,IN-USE dev wifi list --rescan no 2>/dev/null)
sec=$(echo "$nm" | awk -F: -v s="$ssid" '$2==s{print $4; exit}')
pct=$(echo "$nm" | awk -F: '$1=="yes"{print $3; exit}')
saved=$(nmcli -t -f NAME con show 2>/dev/null | jq -R . | jq -sc .)
others=$(echo "$nm" | awk -F: -v s="$ssid" '$2!="" && $2!=s && !seen[$2]++ {print $2 "\t" $3 "\t" $4}' | sort -t$'\t' -k2 -nr | head -8 | jq -R 'split("\t") | {n: .[0], s: (.[1]|tonumber), k: (.[2] // "")}' | jq -sc .)
printf 'L|%s|%s|%s|%s|%s|%s|%s|%s\n' "$ssid" "$sig" "$freq" "$rx" "$tx" "$pct" "$sec" "$radio"
printf 'N|%s|%s|%s|%s|%s\n' "$ip" "$gw" "$rxb" "$txb" "$ping_ms"
printf 'S|%s\n' "${saved:-[]}"
printf 'O|%s\n' "${others:-[]}"
