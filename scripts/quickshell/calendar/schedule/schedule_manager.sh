#!/usr/bin/env bash

CACHE="$HOME/.local/share/qs_schedule_cache.json"
MAX_AGE=1800

if [ -f "$CACHE" ]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
    if [ "$AGE" -lt "$MAX_AGE" ]; then
        cat "$CACHE"
        exit 0
    fi
fi

OUTPUT=$(python3 - <<'PYEOF'
import pickle, json, sys
from datetime import datetime, timezone, timedelta
from googleapiclient.discovery import build
from google.auth.transport.requests import Request

TOKEN_PATH = "/home/czeddaru/.local/share/qs_calendar_oauth"
ALLDAY_MINS = 100

try:
    with open(TOKEN_PATH, "rb") as f:
        creds = pickle.load(f)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(TOKEN_PATH, "wb") as f:
            pickle.dump(creds, f)
    cal_svc   = build("calendar", "v3", credentials=creds, cache_discovery=False)
    tasks_svc = build("tasks",    "v1", credentials=creds, cache_discovery=False)
except Exception as e:
    print(json.dumps({"header": "Auth error", "link": "https://calendar.google.com", "lessons": []}))
    sys.exit(0)

now       = datetime.now()
today_str = now.strftime("%Y-%m-%d")
day_start = datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
day_end   = day_start + timedelta(days=1)

calendars = cal_svc.calendarList().list(showHidden=True).execute().get("items", [])

all_day = []
timed   = []
seen_timed  = set()
seen_allday = set()

for cal in calendars:
    try:
        resp = cal_svc.events().list(
            calendarId=cal["id"],
            timeMin=day_start.isoformat(),
            timeMax=day_end.isoformat(),
            singleEvents=True,
            orderBy="startTime",
        ).execute()
    except Exception:
        continue

    for ev in resp.get("items", []):
        title = ev.get("summary", "(no title)")
        start = ev["start"]
        end   = ev["end"]

        if "dateTime" in start:
            try:
                s_dt = datetime.fromisoformat(start["dateTime"])
                e_dt = datetime.fromisoformat(end["dateTime"])
                s_ep = int(s_dt.timestamp())
                e_ep = int(e_dt.timestamp())
                key  = (s_ep, title)
                if key not in seen_timed:
                    seen_timed.add(key)
                    timed.append({
                        "start": s_ep, "end": e_ep,
                        "subject": title,
                        "time": f"{s_dt.strftime('%H:%M')} - {e_dt.strftime('%H:%M')}",
                        "room": ev.get("location", ""),
                        "is_compact": (e_ep - s_ep) < 1800,
                        "calendar": cal.get("summaryOverride") or cal.get("summary", ""),
                        "color": cal.get("backgroundColor", ""),
                    })
            except Exception:
                pass
        else:
            ev_date = start.get("date", "")
            ev_end  = end.get("date", "")
            if (ev_date <= today_str < ev_end or ev_date == today_str) and title not in seen_allday:
                seen_allday.add(title)
                all_day.append(title)

timed.sort(key=lambda e: e["start"])

due_min = day_start.isoformat()
due_max = day_end.isoformat()
task_lists  = tasks_svc.tasklists().list(maxResults=20).execute().get("items", [])
tasks_today = []

for tl in task_lists:
    try:
        resp = tasks_svc.tasks().list(
            tasklist=tl["id"],
            dueMin=due_min, dueMax=due_max,
            showCompleted=False, showHidden=False, maxResults=50,
        ).execute()
    except Exception:
        continue
    for task in resp.get("items", []):
        t = task.get("title", "").strip()
        if t:
            tasks_today.append((t, task["id"], tl["id"]))

lessons = []
midnight_epoch = int(datetime(now.year, now.month, now.day).timestamp())

for i, title in enumerate(all_day):
    s = midnight_epoch + i * ALLDAY_MINS * 60
    e = s + ALLDAY_MINS * 60
    lessons.append({"type": "class", "subject": title,
                    "start": s, "end": e, "time": "All day", "room": "", "is_compact": False})

for i, (title, task_id, tasklist_id) in enumerate(tasks_today):
    offset = (len(all_day) + i) * ALLDAY_MINS * 60
    s = midnight_epoch + offset
    e = s + ALLDAY_MINS * 60
    lessons.append({"type": "class", "subject": f"󰄳 {title}",
                    "start": s, "end": e, "time": "Task", "room": "", "is_compact": False,
                    "taskId": task_id, "tasklistId": tasklist_id})

if (all_day or tasks_today) and timed:
    sep = midnight_epoch + (len(all_day) + len(tasks_today)) * ALLDAY_MINS * 60
    lessons.append({"type": "gap", "desc": "", "start": sep, "end": sep + 600})

for i, ev in enumerate(timed):
    if i > 0:
        gap_s = timed[i-1]["end"]
        gap_e = ev["start"]
        gap_m = (gap_e - gap_s) // 60
        if gap_m > 0:
            h, m = divmod(gap_m, 60)
            desc = (f"{h}h {m}m" if m else f"{h}h") if h else f"{m} min"
            lessons.append({"type": "gap", "desc": desc, "start": gap_s, "end": gap_e})
    lessons.append({"type": "class", **ev})

total = len(all_day) + len(tasks_today) + len(timed)
if total == 0:
    header = "No events today"
else:
    parts = []
    if all_day:     parts.append(f"{len(all_day)} all-day")
    if tasks_today: parts.append(f"{len(tasks_today)} task{'s' if len(tasks_today)!=1 else ''}")
    if timed:       parts.append(f"{len(timed)} event{'s' if len(timed)!=1 else ''}")
    header = "Today · " + ", ".join(parts)

print(json.dumps({"header": header, "link": "https://calendar.google.com", "lessons": lessons}))
PYEOF
)

echo "$OUTPUT" > "$CACHE"
cat "$CACHE"
