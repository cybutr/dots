#!/usr/bin/env bash
# Card-button → decision file for the Discord autopilot approval flow.
# Args: <id> <choice> <user_id> <username>
# choice ∈ send | skip | trust_send | trust | edit
set -euo pipefail

id="${1:-}"
choice="${2:-}"
user_id="${3:-}"
username="${4:-}"

[ -z "$id" ] && exit 1
[ -z "$choice" ] && exit 1

dir="/tmp/qs_autopilot/decisions"
mkdir -p "$dir"
now="$(date +%s)"

printf '{"choice":"%s","user_id":"%s","username":"%s","ts":%s}\n' \
  "$choice" "$user_id" "$username" "$now" > "$dir/$id.json"

# Approve writes a fresh single-use token the ASK-mode gate consumes to permit one action.
case "$choice" in
  approve|send|trust_send)
    printf '{"choice":"approve","ts":%s}\n' "$now" > /tmp/qs_autopilot/approved.json
    ;;
esac

# Trust choices also persist the contact so future replies auto-send.
case "$choice" in
  trust|trust_send)
    cfg="$HOME/.config/discord-autopilot/trusted.json"
    [ -f "$cfg" ] && [ -n "$user_id$username" ] && \
      python3 - "$cfg" "$user_id" "$username" <<'PY' || true
import json, sys
cfg, uid, uname = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(cfg))
ids = d.setdefault("auto_send_user_ids", [])
names = d.setdefault("auto_send_usernames", [])
if uid and uid not in ids: ids.append(uid)
if uname and uname not in names: names.append(uname)
json.dump(d, open(cfg, "w"), indent=2)
PY
    ;;
esac
