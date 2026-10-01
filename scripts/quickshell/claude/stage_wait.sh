#!/usr/bin/env bash
say="$(dirname "$(readlink -f "$0")")/stage_say.py"
ack=/tmp/qs_stage_ack
id=${1:-latest}
timeout=${2:-300}

[[ $timeout =~ ^[0-9]+$ ]] || { echo "timeout must be whole seconds" >&2; exit 2; }
[[ $id == latest ]] && id=$(python3 "$say" pending | tail -n1)
[[ -n $id ]] || { echo "nothing is waiting" >&2; exit 2; }

touch "$ack"
end=$((SECONDS + timeout))
state() { awk -v id="$id" '$1 == id { s = $2 } END { print s }' "$ack"; }

while :; do
    case $(state) in
        ok) exit 0 ;;
        cancel|expired) exit 3 ;;
    esac
    left=$((end - SECONDS))
    if (( left <= 0 )); then
        python3 "$say" ack "$id" --state expired >/dev/null
        exit 1
    fi
    # short re-arm caps the check-then-watch race to a few seconds instead of the whole timeout
    inotifywait -qq -t $(( left < 5 ? left : 5 )) -e close_write,modify,moved_to,attrib "$ack" 2>/dev/null
done
