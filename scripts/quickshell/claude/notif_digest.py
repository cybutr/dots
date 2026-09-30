#!/usr/bin/env python3
"""#3 notif-digest.
Every 60 minutes, folds whatever low-priority notifications piled up since
the last run into one 2-line Haiku summary card, so the user doesn't have
to scroll a wall of individually-triaged notif_ dots. If they're currently
in a sustained focus streak, the digest still builds but skips the
desktop-notify interruption (suppress during focus mode)."""
import os, sys, json, time, subprocess, sqlite3

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import resident_card
except Exception:
    resident_card = None

try:
    from claude_say import say
except Exception:
    def say(*a, **k): return ""

try:
    from claude_resident import (save, load, notify, SUGGEST, PERSONA, FOCUS_DB,
                                  NOTIF_WATCH_IGNORE, NOTIF_BODY_IGNORE)
except Exception:
    def load(path, default):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            return default

    def save(path, obj):
        try:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(obj, f)
            os.replace(tmp, path)
        except OSError:
            pass

    def notify(title, body, urgency):
        try:
            subprocess.run(["notify-send", "-a", "Claude", "-u", urgency,
                            "-i", "dialog-information", title, body], timeout=5, check=False)
        except Exception:
            pass

    SUGGEST = "/tmp/qs_resident_suggestion"
    PERSONA = ("You are the user's ambient desktop assistant living in their Hyprland shell. "
               "Reply with ONE short line, warm and practical, under 20 words. "
               "No greeting, no sign-off, no quotes, no markdown.")
    HOME = os.path.expanduser("~")
    FOCUS_DB = os.path.join(HOME, ".local/share/focustime/focustime.db")
    NOTIF_WATCH_IGNORE = {"claude", "system", "screenshot", "cachy-update"}
    NOTIF_BODY_IGNORE = ("claude is waiting for your input", "claude needs your permission")

PID = "/tmp/qs_notif_digest.pid"
NOTIFICATIONS = "/tmp/qs_notifications.json"
STATE = "/tmp/qs_notif_digest_state.json"
INTERVAL = 3600
FOCUS_WINDOW_MIN = 15


def _in_focus():
    if not os.path.exists(FOCUS_DB):
        return False
    lt = time.localtime()
    today = time.strftime("%Y-%m-%d", lt)
    cur_idx = lt.tm_hour * 60 + lt.tm_min
    lo = max(0, cur_idx - FOCUS_WINDOW_MIN)
    try:
        conn = sqlite3.connect(FOCUS_DB, timeout=2)
        rows = conn.execute(
            "SELECT DISTINCT app_class FROM focus_minutes "
            "WHERE log_date=? AND minute_idx>=? AND minute_idx<=? AND seconds>=3",
            (today, lo, cur_idx)).fetchall()
        conn.close()
        apps = {r[0] for r in rows} - {"Desktop", "Locked", "Unknown"}
        return len(apps) == 1
    except Exception:
        return False


def run_once(state):
    notifs = load(NOTIFICATIONS, [])
    last_uid = state.get("last_uid", 0)
    fresh = []
    max_uid = last_uid
    for n in notifs:
        uid = n.get("uid", 0)
        if uid <= last_uid:
            continue
        max_uid = max(max_uid, uid)
        app = (n.get("appName") or "").strip()
        body = n.get("body", "")
        if not app or app.lower() in NOTIF_WATCH_IGNORE:
            continue
        if any(p in body.lower() for p in NOTIF_BODY_IGNORE):
            continue
        fresh.append(n)
    state["last_uid"] = max_uid
    if len(fresh) < 2:
        return
    lines = "; ".join(f"{n.get('appName','?')}: {n.get('summary','')}" for n in fresh[:15])
    out = say(f"{len(fresh)} low-priority notifications piled up: {lines}. Fold these into a "
              f"2-line summary — what happened, anything worth a look. Warm, terse, no "
              f"greeting, no markdown, no per-item breakdown.",
              system=PERSONA.replace("ONE short line", "at most 2 short lines"), timeout=20).strip()
    if not out:
        return
    if not _in_focus():
        if resident_card is not None:
            resident_card.emit("Claude · digest", out, "mail-unread", "low", None, [],
                               "resident", "notif-digest-" + str(int(time.time())))
        else:
            notify("Claude · digest", out, "low")
    save(SUGGEST, {"key": "notif_digest", "msg": out, "urgency": "low",
                   "ts": int(time.time()), "action_label": "", "action_cmd": "",
                   "label": "digest"})


def main():
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))

    while True:
        state = load(STATE, {})
        try:
            run_once(state)
        except Exception:
            pass
        save(STATE, state)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
