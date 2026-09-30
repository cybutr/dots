#!/usr/bin/env bash
# Non-interactive task add (agent use). Args: $1 = title
TITLE="$1"
[ -z "$TITLE" ] && exit 1

python3 - "$TITLE" <<'PYEOF'
import pickle, sys
from datetime import datetime, timezone
from googleapiclient.discovery import build
from google.auth.transport.requests import Request

title = sys.argv[1]
TOKEN = "/home/czeddaru/.local/share/qs_calendar_oauth"

with open(TOKEN, "rb") as f:
    creds = pickle.load(f)
if creds.expired and creds.refresh_token:
    creds.refresh(Request())
    with open(TOKEN, "wb") as f:
        pickle.dump(creds, f)

svc = build("tasks", "v1", credentials=creds, cache_discovery=False)
today = datetime.now(timezone.utc).strftime("%Y-%m-%dT00:00:00.000Z")
tasklist = svc.tasklists().list(maxResults=1).execute()["items"][0]["id"]
svc.tasks().insert(tasklist=tasklist, body={"title": title, "due": today, "status": "needsAction"}).execute()
PYEOF

rm -f "$HOME/.local/share/qs_schedule_cache.json"
notify-send -i checkbox "Task added" "$TITLE" -t 2000
