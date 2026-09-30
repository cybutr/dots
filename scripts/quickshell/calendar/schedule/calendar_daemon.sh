#!/usr/bin/env bash

CACHE="$HOME/.local/share/qs_schedule_cache.json"
EVENT="/tmp/qs_current_event.json"
SETTINGS="$HOME/.config/hypr/settings.json"
SCRIPT="$HOME/.config/hypr/scripts/quickshell/calendar/schedule/schedule_manager.sh"
NOTIFIED="/tmp/qs_notified_events"

compute_events() {
    python3 - "$CACHE" "$EVENT" "$NOTIFIED" <<'PYEOF'
import json, sys, subprocess, hashlib, os
from datetime import datetime

cache_path, out_path, notified_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.load(open(cache_path))
except Exception:
    json.dump({"active": False, "events": []}, open(out_path, "w"))
    sys.exit(0)

now_dt = datetime.now()
now    = int(now_dt.timestamp())
today  = now_dt.strftime("%Y-%m-%d")

lessons = data.get("lessons", [])
timed   = [l for l in lessons if l.get("type") == "class" and l.get("time") not in ("All day", "Task")]
allday  = [l for l in lessons if l.get("type") == "class" and l.get("time") == "All day"]
tasks   = [l for l in lessons if l.get("type") == "class" and l.get("time") == "Task"]

def fmt_mins(m):
    h, m2 = divmod(int(m), 60)
    return (f"{h}h {m2}m" if m2 else f"{h}h") if h else f"{int(m)}m"

events_out = []

for ev in timed:
    if ev["start"] <= now <= ev["end"]:
        total   = ev["end"] - ev["start"]
        elapsed = now - ev["start"]
        events_out.append({
            "title":    ev["subject"],
            "subtitle": fmt_mins((ev["end"] - now) / 60) + " left",
            "isNow": True, "progress": elapsed / total if total > 0 else 0,
            "type": "event",
        })

for ev in timed:
    if ev["start"] > now:
        events_out.append({
            "title":    ev["subject"],
            "subtitle": "in " + fmt_mins((ev["start"] - now) / 60),
            "isNow": False, "progress": 0.0, "type": "event",
        })

for ev in allday:
    events_out.append({"title": ev["subject"], "subtitle": "all day",
                       "isNow": False, "progress": 0.0, "type": "allday"})

for ev in tasks:
    events_out.append({"title": ev["subject"], "subtitle": "task",
                       "isNow": False, "progress": 0.0, "type": "task"})

# Notifications
notified = set()
if os.path.exists(notified_path):
    for line in open(notified_path):
        parts = line.strip().split("|")
        if len(parts) == 2 and parts[0] == today:
            notified.add(parts[1])

for ev in timed:
    if ev["start"] > now:
        delta_m = (ev["start"] - now) / 60
        if 0 < delta_m <= 10:
            key = hashlib.md5(f"{ev['subject']}{ev['start']}".encode()).hexdigest()
            if key not in notified:
                subprocess.run(["notify-send", "-i", "x-office-calendar",
                               f"Upcoming: {ev['subject']}",
                               f"Starting in {int(delta_m)}m"], check=False)
                with open(notified_path, "a") as f:
                    f.write(f"{today}|{key}\n")

json.dump({"active": len(events_out) > 0, "events": events_out}, open(out_path, "w"))
PYEOF
}

while true; do
    INTERVAL=$(python3 -c "import json; print(json.load(open('$SETTINGS')).get('calendarRefreshMinutes',5))" 2>/dev/null || echo 5)
    SHOW=$(python3 -c "import json; print(json.load(open('$SETTINGS')).get('showCalendarPill',True))" 2>/dev/null || echo True)

    rm -f "$CACHE"
    bash "$SCRIPT" > /dev/null 2>/dev/null

    if [ "$SHOW" = "False" ]; then
        echo '{"active":false,"events":[]}' > "$EVENT"
    else
        compute_events
    fi

    sleep $((INTERVAL * 60))
done
