#!/usr/bin/env bash
# Connected wired (USB-cable) devices — lsusb filtered down to actually
# external hardware: drops the 1d6b Linux Foundation root hubs (virtual bus
# entries), drops anything reporting removable=="fixed" in sysfs (this
# laptop's integrated camera and fingerprint reader), and drops the internal
# Bluetooth adapter by name (redundant with the bt list anyway).
#
# Shared by TopBar.qml's clockWiredReader hover-card query and
# device_watch.py's connect/disconnect diff — keep this the single source of
# truth for the filter logic, don't reimplement it a second time.
#
# Output: {"wired":[{"name":"..."}...]}

declare -A REM
for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    vid=$(cat "$d/idVendor" 2>/dev/null)
    pid=$(cat "$d/idProduct" 2>/dev/null)
    REM["$vid:$pid"]=$(cat "$d/removable" 2>/dev/null)
done

objs=()
while IFS= read -r line; do
    [[ "$line" =~ ID\ ([0-9a-f]{4}):([0-9a-f]{4})\ (.*) ]] || continue
    vid="${BASH_REMATCH[1]}"
    pid="${BASH_REMATCH[2]}"
    desc="${BASH_REMATCH[3]}"
    [[ "$vid" == "1d6b" ]] && continue
    [[ "${desc,,}" == *bluetooth* ]] && continue
    [[ "${REM[$vid:$pid]}" == "fixed" ]] && continue
    objs+=("{\"name\":\"${desc//\"/\\\"}\",\"id\":\"${vid}:${pid}\"}")
done < <(lsusb)

if [ ${#objs[@]} -gt 0 ]; then
    printf '{"wired":[%s]}\n' "$(IFS=,; echo "${objs[*]}")"
else
    echo '{"wired":[]}'
fi
