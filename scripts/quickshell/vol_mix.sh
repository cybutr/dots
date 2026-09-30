#!/usr/bin/env bash
echo "D|$(pactl get-default-sink 2>/dev/null)"
echo "S|$(pactl -f json list sinks 2>/dev/null | jq -c '[.[] | select(([.ports[]?.availability] | length == 0) or any(.ports[]?; .availability != "not available")) | {n: .name, d: .description}]' 2>/dev/null)"
apps=$(pactl -f json list sink-inputs 2>/dev/null | jq -c '[.[] | {i: .index, a: (.properties["application.name"] // "app"), v: ((.volume | to_entries[0].value.value_percent) | rtrimstr("%") | tonumber), m: .mute}]' 2>/dev/null)
[ -z "$apps" ] && apps="[]"
mpris=$(playerctl --player=spotify volume 2>/dev/null)
if [ -n "$mpris" ]; then
    apps=$(echo "$apps" | jq -c --argjson m "$mpris" '
        (if any(.[]; (.a | ascii_downcase) == "spotify") then . else [{i: -1, a: "spotify", v: 0, m: false}] + . end)
        | map(if (.a | ascii_downcase) == "spotify" then .v = ($m * 100 | round) | .p = 1 else . end)
        | sort_by(.p != 1)' 2>/dev/null)
fi
echo "A|$apps"
