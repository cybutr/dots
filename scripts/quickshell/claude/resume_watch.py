#!/usr/bin/env python3
"""#4 resume-context + #18 wake/return summary.
Polls for the lock screen process (Lock.qml, launched by hypridle's
lock_cmd) to detect lock/unlock transitions, and for large gaps between
polls to detect suspend/sleep. On return: a short 'back where you left off'
card (TTL 120s, self-expiring if you don't act on it), or — if you were gone
long enough to accrue notifications/mailbox notes — a 'while you were gone'
fold-up instead."""
import os, sys, json, subprocess, time

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
                                  mailbox_pending, NOTIFICATIONS)
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
    NOTIFICATIONS = "/tmp/qs_notifications.json"

    def mailbox_pending(to="resident"):
        return []

PID = "/tmp/qs_resume_watch.pid"
CTX = "/tmp/qs_context.json"
STATE = "/tmp/qs_resume_watch_state.json"
POLL = 3
SUSPEND_GAP = 300
RESUME_TTL = 120


def _lock_active():
    try:
        r = subprocess.run(["pgrep", "-f", "quickshell.*Lock(Legacy)?[.]qml"],
                            capture_output=True, text=True, timeout=3)
        pids = set(r.stdout.split())
        try:
            with open("/tmp/qs_lock_preview.pid") as f:
                pids.discard(f.read().strip())
        except OSError:
            pass
        return bool(pids)
    except Exception:
        return False


def _project_context():
    ctx = load(CTX, {})
    return ctx.get("focus", {}) if isinstance(ctx, dict) else {}


def _expire_after(ttl):
    time.sleep(ttl)
    sug = load(SUGGEST, {})
    if sug.get("key") == "resume_context":
        save(SUGGEST, {})


def _while_away_summary(gone_secs):
    notifs = load(NOTIFICATIONS, [])
    recent = [n for n in notifs if n.get("uid", 0)][-8:]
    lines = "; ".join(f"{n.get('appName','?')}: {n.get('summary','')}" for n in recent) or "nothing notable"
    mail = mailbox_pending("resident")
    mail_lines = "; ".join(m.get("msg", "") for m in mail) or "nothing"
    mins = max(1, gone_secs // 60)
    out = say(f"I was away for about {mins} minutes. Recent notifications: {lines}. "
              f"Notes left for me: {mail_lines}. Fold this into a short 'while you were gone' "
              f"summary, at most 2 short sentences, warm and practical, no greeting.",
              system=PERSONA.replace("ONE short line", "at most 2 short sentences"), timeout=20).strip()
    if not out:
        return
    if resident_card is not None:
        resident_card.emit("Claude · welcome back", out, "face-smile", "normal", None, [],
                           "resident", "resume-away-" + str(int(time.time())))
    else:
        notify("Claude · welcome back", out, "normal")
    save(SUGGEST, {"key": "resume_away", "msg": out, "urgency": "normal",
                   "ts": int(time.time()), "action_label": "", "action_cmd": "",
                   "label": "welcome back"})


def _resume_context(project, cwd, app, title, gone_secs):
    mins = max(1, gone_secs // 60)
    where = project or app or "your desktop"
    detail = f" ({title[:60]})" if title and not project else ""
    out = say(f"I just unlocked after being away {mins} min. Before locking I was in "
              f"'{where}'{detail}. Give me ONE short 'welcome back' line reminding me where "
              f"I left off. Under 18 words, no greeting, no quotes.",
              system=PERSONA, timeout=15).strip()
    msg = out or f"back in {where} — {mins}min before you left"
    if resident_card is not None:
        resident_card.emit("Claude", msg, "go-home", "low", RESUME_TTL, [], "resident",
                           "resume-context")
    else:
        notify("Claude", msg, "low")
    save(SUGGEST, {"key": "resume_context", "msg": msg, "urgency": "low",
                   "ts": int(time.time()), "action_label": "", "action_cmd": "",
                   "label": "welcome"})
    import threading
    threading.Thread(target=_expire_after, args=(RESUME_TTL,), daemon=True).start()


def main():
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))

    state = load(STATE, {"was_locked": False, "last_poll": time.time(), "pre_lock_focus": {}})
    last_poll = state.get("last_poll", time.time())

    while True:
        time.sleep(POLL)
        now = time.time()
        gap = now - last_poll
        last_poll = now

        locked = _lock_active()
        was_locked = state.get("was_locked", False)

        if locked and not was_locked:
            state["pre_lock_focus"] = _project_context()
            state["locked_at"] = now

        if not locked and was_locked:
            gone = now - state.get("locked_at", now)
            pre = state.get("pre_lock_focus", {})
            if gone >= SUSPEND_GAP or gap >= SUSPEND_GAP:
                _while_away_summary(int(max(gone, gap)))
            else:
                _resume_context(pre.get("project", ""), pre.get("cwd", ""),
                                pre.get("app", ""), pre.get("title", ""), int(gone))

        # suspend can also happen without the lock screen ever registering a
        # poll in between (system frozen) — catch that gap even if unlocked
        # both before and after.
        if gap >= SUSPEND_GAP and not (locked and not was_locked) and not (not locked and was_locked):
            _while_away_summary(int(gap))

        state["was_locked"] = locked
        state["last_poll"] = now
        save(STATE, state)


if __name__ == "__main__":
    main()
