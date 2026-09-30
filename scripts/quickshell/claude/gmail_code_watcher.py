#!/usr/bin/env python3
# Watches the inbox for verification/confirmation codes (2FA, sign-in OTPs,
# etc.) as they arrive and auto-copies them to the clipboard + surfaces a
# short-lived resident card, so you never have to open Gmail to grab one.
#
# Uses the SAME OAuth token as the calendar integration
# (~/.local/share/qs_calendar_oauth) — requires the gmail.readonly scope,
# added in calendar/schedule/setup_auth.py. If that token predates the
# scope being added, re-run setup_auth.py once to grant it (see that file's
# comment). This daemon does NOT attempt reauth itself — resident_extras.py's
# find_fixes() health-checks the token and nudges reauth the same way it
# already does for the calendar/Spotify tokens.
#
# Single-instance via flock (same idiom as leak_reaper.py / spotify_history_daemon.py).
import fcntl
import json
import os
import pickle
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import resident_card  # noqa: E402

TOKEN_PATH = os.path.expanduser("~/.local/share/qs_calendar_oauth")
STATE_FILE = "/tmp/qs_gmail_watcher_state.json"
LOCK = "/tmp/qs_gmail_watcher.lock"
LOG = "/tmp/qs_gmail_watcher.log"
POLL_SECS = 20
SEEN_CAP = 300
CODE_HOLD_SECS = 90  # most OTPs expire well before this; matches typical validity

CODE_KEYWORDS = re.compile(
    r"(verification|confirm|security|sign.?in|log.?in|one.?time|passcode|access|auth|otp|pin|code)",
    re.IGNORECASE,
)
# Prefer an explicit "code is/was/: XXXXXX" phrasing; fall back to a bare
# 4-8 digit token (optionally split with a space/dash, e.g. "123 456") that
# sits near one of the keywords above.
CODE_PATTERNS = [
    re.compile(r"(?:code|pin|passcode|otp)[^\w\d]{0,12}(?:is|was|:)?[^\w\d]{0,4}(\d[\d\s-]{3,9}\d)", re.IGNORECASE),
    re.compile(r"\b(\d{3}[\s-]?\d{3})\b"),
    re.compile(r"\b(\d{4,8})\b"),
]


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + msg + "\n")
        if os.path.getsize(LOG) > 200000:
            os.replace(LOG, LOG + ".old")
    except OSError:
        pass


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"seen_ids": [], "start_ts": int(time.time())}


def save_state(state):
    state["seen_ids"] = state.get("seen_ids", [])[-SEEN_CAP:]
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_FILE)


def get_service():
    from googleapiclient.discovery import build
    from google.auth.transport.requests import Request

    with open(TOKEN_PATH, "rb") as f:
        creds = pickle.load(f)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(TOKEN_PATH, "wb") as f:
            pickle.dump(creds, f)
    return build("gmail", "v1", credentials=creds, cache_discovery=False)


def extract_code(subject, snippet):
    text = f"{subject}\n{snippet}"
    if not CODE_KEYWORDS.search(text):
        return None
    for pat in CODE_PATTERNS:
        m = pat.search(text)
        if m:
            code = re.sub(r"[\s-]", "", m.group(1))
            if 4 <= len(code) <= 8:
                return code
    return None


def sender_name(headers):
    for h in headers:
        if h.get("name", "").lower() == "from":
            val = h.get("value", "")
            m = re.match(r'^"?([^"<]+)"?\s*<', val)
            return (m.group(1).strip() if m else val).strip()
    return "unknown sender"


def poll_once(state):
    svc = get_service()
    seen = set(state.get("seen_ids", []))
    # Only ever look at the last ~15 minutes — a code from longer ago is
    # already expired and not worth surfacing.
    resp = svc.users().messages().list(userId="me", q="newer_than:1h", maxResults=10).execute()
    for m in resp.get("messages", []):
        mid = m["id"]
        if mid in seen:
            continue
        seen.add(mid)
        msg = svc.users().messages().get(userId="me", id=mid, format="metadata",
                                          metadataHeaders=["Subject", "From"]).execute()
        internal_ts = int(msg.get("internalDate", "0")) / 1000
        if internal_ts < state.get("start_ts", 0):
            # Don't fire on mail that arrived before this daemon started —
            # avoids a burst of stale notifications on first boot.
            continue
        headers = msg.get("payload", {}).get("headers", [])
        subject = next((h["value"] for h in headers if h.get("name", "").lower() == "subject"), "")
        snippet = msg.get("snippet", "")
        code = extract_code(subject, snippet)
        if not code:
            continue
        who = sender_name(headers)
        subprocess.run(["wl-copy", "--", code], check=False)
        resident_card.emit(
            f"Code from {who}", f"{code}\ncopied to clipboard — {subject[:60]}",
            "dialog-password", "normal", CODE_HOLD_SECS,
            [{"label": "Copy again", "cmd": "printf %s '" + code.replace("'", "'\\''") + "' | wl-copy"}],
            "gmail_watcher", card_id="gmail-code-" + mid,
        )
        log(f"code {code} from {who} ({subject[:50]!r})")
    state["seen_ids"] = list(seen)
    save_state(state)


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    state = load_state()
    if "--once" in sys.argv:
        try:
            poll_once(state)
        except Exception as e:
            log(f"error: {e!r}")
        return
    while True:
        try:
            poll_once(state)
        except Exception as e:
            log(f"error: {e!r}")
        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
