#!/usr/bin/env bash
# Args: $1 = YYYY-MM (defaults to current month)

YM="${1:-$(date +%Y-%m)}"
CACHE="/tmp/qs_month_dots_${YM}.json"
SETTINGS="$HOME/.config/hypr/settings.json"
REFRESH_MINS=$(jq -r '.calendarRefreshMinutes // 3' "$SETTINGS" 2>/dev/null)

# Serve from cache if fresh
if [ -f "$CACHE" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
    if [ "$age" -lt $(( REFRESH_MINS * 60 )) ]; then
        cat "$CACHE"
        exit 0
    fi
fi

python3 - "$YM" <<'PYEOF'
import pickle, json, sys, calendar as cal_mod
from datetime import datetime, timezone
from googleapiclient.discovery import build
from google.auth.transport.requests import Request

ym = sys.argv[1]
year, month = int(ym[:4]), int(ym[5:7])
TOKEN = "/home/czeddaru/.local/share/qs_calendar_oauth"

try:
    with open(TOKEN, "rb") as f:
        creds = pickle.load(f)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
    cal_svc   = build("calendar", "v3", credentials=creds, cache_discovery=False)
    tasks_svc = build("tasks",    "v1", credentials=creds, cache_discovery=False)
except Exception:
    print("{}"); sys.exit(0)

last_day    = cal_mod.monthrange(year, month)[1]
month_start = datetime(year, month, 1, tzinfo=timezone.utc)
month_end   = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

result = {}

def add_entry(date_str, title, time_str, typ):
    if not date_str:
        return
    if date_str not in result:
        result[date_str] = {"eventCount": 0, "taskCount": 0, "items": []}
    if typ == "task":
        result[date_str]["taskCount"] += 1
    else:
        result[date_str]["eventCount"] += 1
    if len(result[date_str]["items"]) < 5:
        result[date_str]["items"].append({"title": title, "time": time_str, "type": typ})

# Calendar events
calendars = cal_svc.calendarList().list(showHidden=True).execute().get("items", [])
seen = set()
for cal in calendars:
    try:
        resp = cal_svc.events().list(
            calendarId=cal["id"],
            timeMin=month_start.isoformat(),
            timeMax=month_end.isoformat(),
            singleEvents=True, maxResults=250,
        ).execute()
    except Exception:
        continue
    for ev in resp.get("items", []):
        title = ev.get("summary", "(no title)")
        start = ev["start"]
        if "dateTime" in start:
            from datetime import datetime as dt
            s = dt.fromisoformat(start["dateTime"])
            e = dt.fromisoformat(ev["end"]["dateTime"])
            date_str = s.strftime("%Y-%m-%d")
            time_str = f"{s.strftime('%H:%M')} – {e.strftime('%H:%M')}"
            typ = "event"
        else:
            date_str = start.get("date", "")[:10]
            time_str = "All day"
            typ = "allday"
        key = (date_str, title)
        if key not in seen:
            seen.add(key)
            add_entry(date_str, title, time_str, typ)

# Tasks
for tl in tasks_svc.tasklists().list(maxResults=20).execute().get("items", []):
    try:
        resp = tasks_svc.tasks().list(
            tasklist=tl["id"],
            dueMin=month_start.isoformat(),
            dueMax=month_end.isoformat(),
            showCompleted=False, maxResults=100,
        ).execute()
    except Exception:
        continue
    for task in resp.get("items", []):
        t = task.get("title", "").strip().replace('\n', ' ')
        due = (task.get("due") or "")[:10]
        if t and due:
            add_entry(due, t, "", "task")

out = json.dumps(result)
cache_path = f"/tmp/qs_month_dots_{ym}.json"
with open(cache_path, "w") as f:
    f.write(out)
print(out)
PYEOF
