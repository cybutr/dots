#!/usr/bin/env bash

COLORS="$HOME/.config/hypr/scripts/quickshell/qs_colors.json"
if [ -f "$COLORS" ]; then
    BASE=$(python3 -c "import json; d=json.load(open('$COLORS')); print(d.get('base','#1e1e2e'))")
    MANTLE=$(python3 -c "import json; d=json.load(open('$COLORS')); print(d.get('mantle','#181825'))")
    MAUVE=$(python3 -c "import json; d=json.load(open('$COLORS')); print(d.get('mauve','#b4befe'))")
    TEXT=$(python3 -c "import json; d=json.load(open('$COLORS')); print(d.get('text','#cdd6f4'))")
    SURFACE0=$(python3 -c "import json; d=json.load(open('$COLORS')); print(d.get('surface0','#313244'))")
else
    BASE="#1e1e2e"; MANTLE="#181825"; MAUVE="#b4befe"; TEXT="#cdd6f4"; SURFACE0="#313244"
fi

TITLE=$(rofi -dmenu -p "Add task:" \
    -theme-str "
    window    { width: 520px; height: 0px; border-radius: 14px; background-color: ${MANTLE}; border: 1px; border-color: ${MAUVE}; }
    mainbox   { children: [inputbar]; padding: 10px; background-color: transparent; orientation: vertical; spacing: 0px; }
    inputbar  { children: [prompt,entry]; background-color: ${SURFACE0}; border-radius: 10px; padding: 10px 14px; spacing: 8px; border: 0px; orientation: horizontal; }
    prompt    { color: ${MAUVE}; font: \"JetBrains Mono Bold 13\"; background-color: transparent; text-color: ${MAUVE}; }
    entry     { color: ${TEXT}; font: \"JetBrains Mono 13\"; placeholder: \"task name...\"; placeholder-color: ${SURFACE0}; background-color: transparent; }
    listview  { enabled: false; lines: 0; }
    " 2>/dev/null)

[ -z "$TITLE" ] && exit 0

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
