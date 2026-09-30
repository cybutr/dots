#!/usr/bin/env bash

python3 - "$1" "$2" <<'PYEOF'
import pickle, sys
from googleapiclient.discovery import build
from google.auth.transport.requests import Request

task_id, tasklist_id = sys.argv[1], sys.argv[2]
TOKEN = "/home/czeddaru/.local/share/qs_calendar_oauth"

with open(TOKEN, "rb") as f:
    creds = pickle.load(f)
if creds.expired and creds.refresh_token:
    creds.refresh(Request())
    with open(TOKEN, "wb") as f:
        pickle.dump(creds, f)

svc  = build("tasks", "v1", credentials=creds, cache_discovery=False)
task = svc.tasks().get(tasklist=tasklist_id, task=task_id).execute()

if task.get("status") == "completed":
    svc.tasks().patch(tasklist=tasklist_id, task=task_id,
                      body={"status": "needsAction", "completed": None}).execute()
else:
    svc.tasks().patch(tasklist=tasklist_id, task=task_id,
                      body={"status": "completed"}).execute()
PYEOF

rm -f "$HOME/.local/share/qs_schedule_cache.json"
