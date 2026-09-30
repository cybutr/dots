#!/usr/bin/env python3
import os, sys, json, time, subprocess, sqlite3, random, re, threading
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from claude_say import say
except Exception:
    def say(*a, **k):
        return ""

try:
    import resident_extras as extras
except Exception:
    extras = None

try:
    import resident_card
except Exception:
    resident_card = None

HOME = os.path.expanduser("~")
QS = os.path.join(HOME, ".config/hypr/scripts/quickshell")
CTX = "/tmp/qs_context.json"
NOTIFIED = "/tmp/qs_resident_notified"
SUGGEST = "/tmp/qs_resident_suggestion"
SEEN = "/tmp/qs_resident_seen"
SETTINGS_FILE = os.path.join(HOME, ".config/hypr/settings.json")
HISTORY = "/tmp/qs_resident_history.json"
HISTORY_MAX = 8
STATE = "/tmp/qs_resident_state"
PID = "/tmp/qs_resident.pid"
NOTIFICATIONS = "/tmp/qs_notifications.json"
MAILBOX = "/tmp/qs_claude_mailbox.json"
MAILBOX_MAX = 100
MUSIC_INFO = "/tmp/music_info.json"
COLORS_FILE = os.path.join(QS, "qs_colors.json")
SONG_REACT_COOLDOWN = 1200
QS_MANAGER = os.path.join(HOME, ".config/hypr/scripts/qs_manager.sh")
FOCUS_DB = os.path.join(HOME, ".local/share/focustime/focustime.db")
SCHED = os.path.join(QS, "calendar/schedule")

POLL = 30
RENOTIFY = 1800
MIC_THRESHOLD = 1800
BATTERY_LOW = 20   # matches BatteryAlarm.qml's level-1 (20%) banner threshold
EVENT_SOON = 10
NOTIF_WATCH_IGNORE = {"claude", "system", "screenshot", "cachy-update"}   # avoid reacting to our own / noisy system notifications
# Claude Code's own CLI status toasts surface under whatever terminal hosts it
# (kitty, etc), not under an app name we can ignore by name — match on body text.
NOTIF_BODY_IGNORE = ("claude is waiting for your input", "claude needs your permission")
NOTIF_STRICTNESS_RULES = {
    "quiet": "Only propose a task if it is extremely time-sensitive or clearly requires the "
             "user to act right now (security alert, deadline in minutes). Default to SKIP "
             "for almost everything else.",
    "balanced": "Propose a task if the notification looks like it needs a decision or action "
                "from the user soon (a question, a request, a deadline, something broken). "
                "Skip routine/informational notifications.",
    "proactive": "Propose a task for anything that could plausibly use a follow-up action, "
                 "even minor ones. Only SKIP truly inert notifications (e.g. 'update installed').",
}
THRASH_WINDOW_MIN = 10
THRASH_APP_COUNT = 6   # distinct apps engaged (>=3s) in the window to call it thrashing
MEETING_PREP_LO, MEETING_PREP_HI = 5, 15
HOG_CPU_THRESHOLD = 80
# short-lived shell/sampling commands (ps itself, pgrep, etc.) routinely show
# absurd %cpu (400%+) in a single `ps` snapshot purely because their cpu-time
# / process-age ratio is inflated right after spawn - they're not real hogs,
# just measurement artifacts of the very sampling that reads /proc. Each also
# has its own resource_hog_<name> key, so ps/pgrep/grep flip-flopping as
# "top" bypasses the 30-min RENOTIFY cooldown and looks like a stuck pill.
HOG_NAME_BLOCKLIST = {"ps", "pgrep", "pkill", "grep", "awk", "sed", "cut", "sort", "head", "tail"}
BRIGHTNESS_HIGH_THRESH = 35   # pct — only relevant when the auto-curve isn't already handling it
MSG_APPS = {"vesktop", "discord", "signal", "signal-desktop", "telegram", "telegramdesktop",
            "org.telegram.desktop", "vivaldi", "vivaldi-stable"}
QUESTION_HINTS = ("?", "can you", "could you", "would you", "when are", "are you", "do you")
OTP_RE = re.compile(r"\b(\d{4,8})\b.{0,25}?\b(code|otp|verification|passcode)\b|"
                     r"\b(code|otp|verification|passcode)\b.{0,25}?\b(\d{4,8})\b", re.I)
TRACKING_RE = re.compile(r"\b([A-Z0-9]{10,22})\b")
DATETIME_RE = re.compile(
    r"\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b.{0,20}?\b\d{1,2}(:\d{2})?\s*(am|pm)?\b|"
    r"\b\d{1,2}:\d{2}\s*(am|pm)?\b|\btomorrow\b|\btoday\b|\bnext week\b", re.I)
EOD_HOUR = 18
CLAUDE_BIN = "claude"
AGENT_LOG = "/tmp/qs_resident_agent.log"

def settings():
    return load(SETTINGS_FILE, {})


PERSONA = ("You are the user's ambient desktop assistant living in their Hyprland shell. "
           "Reply with ONE short line, warm and practical, under 20 words. "
           "No greeting, no sign-off, no quotes, no markdown.")

# triggers that come with a one-click action the user can confirm
ACTIONS = {
    "battery_low": ("enable power-saver", "powerprofilesctl set power-saver"),
    "mic_on": ("mute mic", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1"),
    "focus_thrash": ("open focus stats", f"bash {QS_MANAGER} open focustime"),
    "brightness_high": ("auto-adjust",
                         "rm -f /tmp/qs_brightness_manual_until && "
                         "bash ~/.config/hypr/scripts/brightness_curve.sh"),
}

# short tag shown next to the dot in the top bar — max 10 chars, matched by
# key prefix since event_/task_/notif_/mail_ keys carry a dynamic suffix.
DOT_LABEL_PREFIXES = [
    ("battery_low", "low batt"),
    ("mic_on", "mic hot"),
    ("focus_thrash", "thrashing"),
    ("event_", "event"),
    ("task_", "task due"),
    ("notif_extract_", "action"),
    ("notif_reply_", "reply"),
    ("notif_", "notif"),
    ("mail_", "note"),
    ("resource_hog_", "cpu hog"),
    ("cap_", "approve?"),
    ("wallpaper_", "palette"),
    ("song_", "vibe"),
    ("discord_unread", "discord"),
    ("brightness_high", "brightness"),
]
DOT_LABEL_DEFAULT = "needs you"


def _dot_label(key):
    for prefix, label in DOT_LABEL_PREFIXES:
        if key.startswith(prefix):
            return label[:10]
    return DOT_LABEL_DEFAULT


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
        subprocess.run(["notify-send", "-a", "Claude", "-u", urgency, "-i", "dialog-information",
                        title, body], timeout=5, check=False)
    except Exception:
        pass


def voiced(fact, action_label):
    if not settings().get("residentVoiceNudges", True):
        return fact
    extra = f" You can offer to {action_label}." if action_label else ""
    out = say(f"Situation: {fact}{extra} Give the user one short heads-up line.",
              system=PERSONA, timeout=20)
    return out.strip() or fact


def _append_history(msg):
    hist = load(HISTORY, [])
    hist.append({"ts": int(time.time()), "msg": msg})
    save(HISTORY, hist[-HISTORY_MAX:])


def mailbox_post(to, msg, frm="resident"):
    """Same mailbox file as qs_mcp.py's mailbox_post/mailbox_read tools — lets
    resident leave notes for me (the live session) or the on-demand agent
    without a shared process, e.g. when an approved task finishes."""
    msgs = load(MAILBOX, [])
    msgs.append({"id": int(time.time() * 1000), "from": frm, "to": to, "msg": msg,
                 "ts": int(time.time()), "read": False})
    save(MAILBOX, msgs[-MAILBOX_MAX:])


def mailbox_pending(to="resident"):
    msgs = load(MAILBOX, [])
    mine = [m for m in msgs if m.get("to") == to and not m.get("read")]
    if mine:
        ids = {m["id"] for m in mine}
        for m in msgs:
            if m["id"] in ids:
                m["read"] = True
        save(MAILBOX, msgs[-MAILBOX_MAX:])
    return mine


def _evaluate_notif(app, summary, body, strictness):
    rule = NOTIF_STRICTNESS_RULES.get(strictness, NOTIF_STRICTNESS_RULES["balanced"])
    out = say(
        f"Notification — app={app!r} summary={summary!r} body={body!r}. {rule} "
        f"Reply with exactly 'SKIP' if no task is warranted, or "
        f"'PROPOSE: <one short task description> | eta: <rough time estimate>' if one is.",
        system="You triage desktop notifications for an automation system. Be terse, follow "
               "the exact reply format requested, no extra commentary.",
        timeout=15, max_tokens=60).strip()
    if not out.lower().startswith("propose"):
        return None
    rest = out.split(":", 1)[1] if ":" in out else out
    if "|" in rest:
        desc, eta = rest.split("|", 1)
        eta = eta.split(":", 1)[-1].strip()
    else:
        desc, eta = rest, ""
    return {"title": desc.strip(), "eta": eta.strip()}


def propose_task_card(key, prefill, notified):
    save(SUGGEST, {"key": key, "msg": prefill, "urgency": "normal", "ts": int(time.time()),
                   "action_label": "open", "action_cmd": "open", "label": "wants act"})
    _append_history(prefill)
    notified[key] = int(time.time())
    save(NOTIFIED, notified)


def surface(key, fact, urgency, notified, also_notify=True):
    label, cmd = ACTIONS.get(key, ("", ""))
    msg = voiced(fact, label)
    if also_notify:
        if resident_card is not None:
            actions = [{"label": label, "cmd": cmd}] if cmd else []
            resident_card.emit("Claude", msg, "dialog-information", urgency, None, actions, "resident", key)
        else:
            notify("Claude", msg, urgency)
    save(SUGGEST, {"key": key, "msg": msg, "urgency": urgency, "ts": int(time.time()),
                   "action_label": label, "action_cmd": cmd, "label": _dot_label(key)})
    _append_history(msg)
    notified[key] = int(time.time())
    save(NOTIFIED, notified)


def _wallpaper_fact(state):
    try:
        mtime = os.path.getmtime(COLORS_FILE)
    except OSError:
        return None
    if state.get("wallpaper_mtime") == mtime:
        return None
    first_seen = "wallpaper_mtime" not in state
    state["wallpaper_mtime"] = mtime
    if first_seen:
        return None   # don't react to the wallpaper already set when the daemon boots
    colors = load(COLORS_FILE, {})
    sample = {}

    def walk(o, depth=0):
        if depth > 3 or len(sample) >= 6:
            return
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, str) and v.startswith("#"):
                    sample[k] = v
                elif isinstance(v, dict):
                    walk(v, depth + 1)

    walk(colors)
    swatch = ", ".join(f"{k}={v}" for k, v in list(sample.items())[:6])
    return (f"wallpaper changed, new matugen palette: {swatch or 'unknown'}. Feel free to "
            f"share a quick opinion on the new colors if you have one.")


def _maybe_react_song(state):
    m = load(MUSIC_INFO, {})
    title, artist = m.get("title", ""), m.get("artist", "")
    if not title or m.get("status") != "Playing":
        return
    track = f"{title}|{artist}"
    if state.get("last_track") == track:
        return
    state["last_track"] = track
    now = int(time.time())
    if now - state.get("last_song_react", 0) < SONG_REACT_COOLDOWN:
        return
    if random.random() > settings().get("residentSongReactChance", 0.3):
        return
    reply = say(f"Song just changed to '{title}' by {artist}. If you have a genuine quick "
                f"opinion — like or dislike the pick/vibe — give ONE short line. If it's "
                f"nothing special, reply with exactly SKIP and nothing else.",
                system=PERSONA, timeout=15).strip()
    if not reply or reply.upper() == "SKIP":
        return
    state["last_song_react"] = now
    if resident_card is not None:
        resident_card.emit("Claude", reply, "emblem-music-symbolic", "low", None, [], "resident")
    else:
        notify("Claude", reply, "low")
    save(SUGGEST, {"key": "song_" + str(now), "msg": reply, "urgency": "low", "ts": now,
                   "action_label": "", "action_cmd": "", "label": "vibe"})
    _append_history(reply)


def _expire_passive(now):
    # Passive comments (no action_cmd — a vibe react, a heads-up) self-dismiss
    # quickly since there's nothing to decide. Actionable nudges (cpu hog's
    # "kill it", etc.) used to be exempt entirely — a hog that stayed above
    # threshold, or that the user just didn't get to, left the topbar pill
    # pulsing "waiting" indefinitely with no way to age out short of manually
    # opening the chat. They still get a much longer ceiling (worth noticing)
    # before the same auto-dismiss applies — this only clears the URGENT
    # pulse state, the nudge itself stays in history either way.
    sug = load(SUGGEST, {})
    if not sug:
        return
    limit = (settings().get("residentActionExpireSecs", 180) if sug.get("action_cmd")
             else settings().get("residentPassiveExpireSecs", 30))
    if now - sug.get("ts", 0) < limit:
        return
    try:
        with open(SEEN, "w") as f:
            f.write(str(int(sug["ts"])))
    except (OSError, KeyError, ValueError):
        pass


def _thrashing_apps():
    if not os.path.exists(FOCUS_DB):
        return []
    lt = time.localtime()
    today = time.strftime("%Y-%m-%d", lt)
    cur_idx = lt.tm_hour * 60 + lt.tm_min
    lo = max(0, cur_idx - THRASH_WINDOW_MIN)
    try:
        conn = sqlite3.connect(FOCUS_DB, timeout=2)
        rows = conn.execute(
            "SELECT DISTINCT app_class FROM focus_minutes "
            "WHERE log_date=? AND minute_idx>=? AND minute_idx<=? AND seconds>=3",
            (today, lo, cur_idx)).fetchall()
        conn.close()
        return [r[0] for r in rows]
    except Exception:
        return []


def _brightness_should_lower():
    """Night hours + brightness still high + the auto-curve isn't the one
    holding it there (manually overridden) — worth a nudge. Silent if the
    curve is already handling it on its own, or the user explicitly disabled
    the feature (that's a deliberate opt-out, not something to nag about)."""
    if os.path.exists("/tmp/qs_brightness_curve_disabled"):
        return None
    if not os.path.exists("/tmp/qs_brightness_manual_until"):
        return None   # curve is live and already tracking this itself

    ns = settings()
    try:
        sh, sm = (int(x) for x in ns.get("nightLightStart", "18:00").split(":"))
        eh, em = (int(x) for x in ns.get("nightLightEnd", "07:00").split(":"))
    except (ValueError, AttributeError):
        sh, sm, eh, em = 18, 0, 7, 0
    now_min = datetime.now().hour * 60 + datetime.now().minute
    start_min, end_min = sh * 60 + sm, eh * 60 + em
    is_night = (now_min >= start_min or now_min < end_min) if start_min > end_min \
        else (start_min <= now_min < end_min)
    if not is_night:
        return None

    try:
        out = subprocess.run(["brightnessctl", "-m"], capture_output=True,
                              text=True, timeout=3).stdout
        pct = int(out.strip().split(",")[3].replace("%", ""))
    except Exception:
        return None
    return pct if pct > BRIGHTNESS_HIGH_THRESH else None


def spawn_full_agent(prompt, tag="task"):
    """Fire-and-forget one-shot full Claude turn (all qs-desktop MCP tools
    available, same registration the interactive chat and discord_profiler.sh
    use) — for findings that should build/update a pinned card proactively,
    without waiting for the user to open chat first."""
    def run():
        try:
            with open(AGENT_LOG, "a") as f:
                f.write(f"\n[{time.strftime('%H:%M:%S')}] --no-continue {tag}\n")
                subprocess.run([CLAUDE_BIN, "--no-continue", "-p", prompt],
                                stdout=f, stderr=f, timeout=180, check=False)
        except Exception as e:
            try:
                with open(AGENT_LOG, "a") as f:
                    f.write(f"[{time.strftime('%H:%M:%S')}] {tag} failed: {e}\n")
            except OSError:
                pass
    threading.Thread(target=run, daemon=True).start()


def _extract_notif_signal(app, summary, body):
    """#1 notif-action-extract — cheap local regex prefilter before ever
    spending a Haiku call; only escalates when something actionable-shaped
    is actually present (OTP, tracking number, date/time)."""
    text = f"{summary} {body}"
    otp = OTP_RE.search(text)
    tracking = TRACKING_RE.search(text) if len(text) < 400 else None
    dt = DATETIME_RE.search(text)
    if not (otp or tracking or dt):
        return None
    out = say(
        f"Notification from {app!r}: {summary!r} — {body!r}. If it contains a one-time "
        f"passcode/OTP, a tracking number, or a specific date+time for an event/appointment, "
        f"reply with exactly one line: 'TYPE: <otp|tracking|datetime> | VALUE: <the value> | "
        f"ACTION: <short label for a one-click action, e.g. \"Copy 449302\" or \"Add "
        f"'Dentist Thu 3pm' to calendar\">'. If none of those are actually present, reply "
        f"with exactly 'SKIP'.",
        system="You extract one structured actionable fact from a notification. Terse, exact "
               "format, no extra commentary.", timeout=15, max_tokens=80).strip()
    if not out or out.upper() == "SKIP" or "TYPE:" not in out:
        return None
    fields = {}
    for part in out.split("|"):
        if ":" in part:
            k, v = part.split(":", 1)
            fields[k.strip().upper()] = v.strip()
    value, action, kind = fields.get("VALUE", ""), fields.get("ACTION", ""), fields.get("TYPE", "")
    if not value or not action:
        return None
    return {"kind": kind, "value": value, "action": action}


def _find_free_gap(events, now, min_gap_min=30, day_end_hour=22):
    """#14 — first free gap >= min_gap_min between now and day_end_hour today,
    given a list of events with epoch start/end. Purely local, no Haiku call."""
    lt = time.localtime(now)
    day_end = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, day_end_hour, 0, 0, 0, 0, -1))
    busy = sorted((e["start"], e["end"]) for e in events
                  if e.get("start") and e.get("end") and e["end"] > now)
    cursor = now
    for start, end in busy:
        if start - cursor >= min_gap_min * 60:
            break
        cursor = max(cursor, end)
    else:
        start = day_end
    gap_end = min(start, day_end)
    if gap_end - cursor < min_gap_min * 60:
        return None
    return (time.strftime("%H:%M", time.localtime(cursor)),
            time.strftime("%H:%M", time.localtime(cursor + min_gap_min * 60)))


def _discord_pending():
    """Query the discord-mcp bridge's reply queue over its unix socket.
    Returns a list of pending conversations, or [] if the bridge is down."""
    import socket as _sock
    path = os.environ.get("DISCORD_MCP_SOCK", f"/run/user/{os.getuid()}/discord-mcp-bridge.sock")
    try:
        s = _sock.socket(_sock.AF_UNIX, _sock.SOCK_STREAM)
        s.settimeout(2)
        s.connect(path)
        s.sendall(json.dumps({"id": 1, "action": "__bridge_queue"}).encode() + b"\n")
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        s.close()
        line = buf.split(b"\n", 1)[0]
        return (json.loads(line).get("result") or {}).get("pending", []) or []
    except Exception:
        return []


def detect(ctx, state, notified):
    out = []
    now = int(time.time())
    sysd = ctx.get("system", {})
    bat = sysd.get("battery", {})
    try:
        pct = int(bat.get("percent", "100"))
    except ValueError:
        pct = 100
    if pct <= BATTERY_LOW and bat.get("status") == "Discharging":
        out.append(("battery_low", f"battery at {pct}% and draining", "critical"))

    events = ctx.get("schedule", {}).get("events", [])
    for ev in events:
        m = ev.get("mins_until")
        if m is None or not (0 <= m <= EVENT_SOON):
            continue
        if extras is not None and extras.calendar_nudged(state, ev.get("start")):
            continue
        room = ev.get("room", "")
        where = f" at {room}" if room else ""
        out.append(("event_" + str(ev.get("start", ev.get("title", ""))),
                    f"{ev.get('title','event')} starts in {m} min{where}", "normal"))

    # #12 meeting-prep — upgrade of the event_ branch. When an event is 5-15 min
    # out and hasn't been prepped yet, fire a background full-agent turn that
    # pulls related tabs/files/notes and pins a prep card. state["prepped"]
    # guards against re-prepping the same event on later polls.
    prepped = state.setdefault("prepped", {})
    for ev in events:
        m = ev.get("mins_until")
        if m is None or not (MEETING_PREP_LO <= m <= MEETING_PREP_HI):
            continue
        ev_id = str(ev.get("start", ev.get("title", "")))
        if prepped.get(ev_id):
            continue
        prepped[ev_id] = now
        title = ev.get("title", "event")
        spawn_full_agent(
            f"In {m} minutes I have '{title}'{(' at ' + ev['room']) if ev.get('room') else ''}. "
            f"Prep me for it: check browser_tabs for anything related open in Vivaldi, check "
            f"recall/memory_search for prior notes about this meeting or the people/topic "
            f"involved, and skim recent files under ~/Documents if relevant. Then call "
            f"show_card with title '{title}' — a short 'text' block summarizing what you "
            f"found (or 'nothing on record yet' if truly nothing), pinned:true, "
            f"board:'Meetings', card_id:'meeting_{ev_id}'. Keep it tight, this is a glance-"
            f"before-you-go card, not an essay.", tag=f"meeting_prep_{ev_id}")

    # #14 overdue-reschedule — upgrade of the task_ branch. Computes a free
    # calendar gap locally, has Haiku propose a slot, surfaces a direct
    # one-click 'block it' card instead of just flagging overdue.
    proposed = state.setdefault("overdue_proposed", {})
    for t in ctx.get("schedule", {}).get("tasks", []):
        due = t.get("due")
        tid = t.get("task_id")
        if not (due and due < now and tid):
            continue
        title = t.get("title", "(untitled)")
        last = proposed.get(tid, 0)
        if now - last < 86400:
            out.append(("task_" + str(tid), f"task overdue: {title}", "normal"))
            continue
        gap = _find_free_gap(events, now)
        if gap:
            slot_txt = f"{gap[0]} - {gap[1]}"
            reply = say(f"Overdue task {title!r}. I found a free slot today: {slot_txt}. "
                        f"Propose blocking that slot for it in ONE short line, under 15 words, "
                        f"no greeting.", system=PERSONA, timeout=15).strip()
            msg = reply or f"'{title}' is overdue — free slot at {slot_txt}, want it blocked?"
            proposed[tid] = now
            save(SUGGEST, {"key": "task_" + str(tid), "msg": msg, "urgency": "normal",
                           "ts": now, "action_label": "block it",
                           "action_cmd": f"bash {os.path.join(SCHED, 'add_task.sh')} "
                                         f"{json.dumps(title + ' — block ' + slot_txt)}",
                           "label": "task due"})
            _append_history(msg)
            notified["task_" + str(tid)] = now
        else:
            out.append(("task_" + str(tid), f"task overdue: {title}", "normal"))

    mic = ctx.get("mic", {})
    if mic.get("on"):
        since = state.get("mic_since")
        if since is None:
            state["mic_since"] = now
        elif now - since >= MIC_THRESHOLD:
            out.append(("mic_on", f"mic has been live for {(now - since)//60} min", "normal"))
    else:
        state["mic_since"] = None

    thrash_apps = _thrashing_apps()
    if len(thrash_apps) >= THRASH_APP_COUNT:
        names = ", ".join(thrash_apps[:5])
        out.append(("focus_thrash",
                    f"{len(thrash_apps)} different apps in the last {THRASH_WINDOW_MIN} min "
                    f"({names}) — looks like context-switch thrashing", "normal"))

    # #9 resource-hog-explain — same process pegging CPU for 2 consecutive polls.
    top = ctx.get("proc", {}).get("top") or {}
    name, cpu = top.get("name", ""), top.get("cpu", 0)
    prev_hog = state.get("prev_hog") or {}
    if name and name not in HOG_NAME_BLOCKLIST and cpu >= HOG_CPU_THRESHOLD:
        if prev_hog.get("name") == name and now - notified.get("resource_hog_" + name, 0) >= RENOTIFY:
            explain = say(f"Process '{name}' has been using over {HOG_CPU_THRESHOLD}% CPU for "
                          f"a bit. In ONE short line, say plainly what it probably is and "
                          f"whether that's normal — under 18 words, no greeting.",
                          system=PERSONA, timeout=15).strip()
            msg = explain or f"'{name}' is pegging the CPU at {cpu:.0f}%"
            save(SUGGEST, {"key": "resource_hog_" + name, "msg": msg, "urgency": "normal",
                           "ts": now, "action_label": "kill it", "action_cmd": f"pkill -f {name}",
                           "label": "cpu hog"})
            _append_history(msg)
            notified["resource_hog_" + name] = now
        state["prev_hog"] = {"name": name, "ts": now}
    else:
        state["prev_hog"] = None

    # #16 connectivity-troubleshoot — wifi drops for 2 consecutive polls while
    # it had previously been actively connected.
    wifi = sysd.get("wifi", {}) or {}
    wifi_up = wifi.get("status") == "enabled" and bool(wifi.get("ssid"))
    if wifi_up:
        state["wifi_was_up"] = True
        state["wifi_down_since"] = None
        state["wifi_troubleshoot_sent"] = False
    elif state.get("wifi_was_up"):
        if state.get("wifi_down_since") is None:
            state["wifi_down_since"] = now
        elif now - state["wifi_down_since"] >= POLL and not state.get("wifi_troubleshoot_sent"):
            state["wifi_troubleshoot_sent"] = True
            spawn_full_agent(
                "Wifi appears to have dropped (was connected, now isn't). Run wifi_control "
                "with action:'status', then action:'list' if needed, ping 1.1.1.1 once via "
                "input tools or a shell-capable check, and sanity-check DNS. Diagnose the "
                "single most likely cause and show_card with title 'Wifi trouble' — a short "
                "text block with your diagnosis and ONE concrete proposed fix, plus a "
                "buttons block with that one fix action if there's a safe one-click option "
                "(e.g. toggle wifi, reconnect). Keep it tight.", tag="wifi_troubleshoot")

    notifs = load(NOTIFICATIONS, [])
    last_uid = state.get("last_notif_uid", 0)
    max_uid = last_uid
    for n in notifs:
        uid = n.get("uid", 0)
        if uid <= last_uid:
            continue
        max_uid = max(max_uid, uid)
        app = (n.get("appName") or "").strip()
        if not app or app.lower() in NOTIF_WATCH_IGNORE:
            continue
        summary, body = n.get("summary", ""), n.get("body", "")
        if any(p in body.lower() for p in NOTIF_BODY_IGNORE):
            continue

        # #1 notif-action-extract — regex-prefiltered, one-click, no chat detour
        signal = _extract_notif_signal(app, summary, body)
        if signal:
            kind = signal["kind"].lower()
            if kind == "datetime":
                title = signal["action"]
                if title.lower().startswith("add "):
                    title = title[4:]
                if title.lower().endswith(" to calendar"):
                    title = title[:-len(" to calendar")]
                cmd = f"bash {os.path.join(SCHED, 'add_task.sh')} {json.dumps(title.strip())}"
            else:
                cmd = f"wl-copy -- {json.dumps(signal['value'])}"
            save(SUGGEST, {"key": "notif_extract_" + str(uid), "msg": f"{app}: {signal['action']}",
                           "urgency": "normal", "ts": now, "action_label": signal["action"],
                           "action_cmd": cmd, "label": "action"})
            _append_history(f"{app}: {signal['action']}")
            notified["notif_extract_" + str(uid)] = now
            continue

        # #2 notif-reply-draft — question-shaped message in a messaging app
        app_l = app.lower()
        text_l = f"{summary} {body}".lower()
        if app_l in MSG_APPS and any(h in text_l for h in QUESTION_HINTS) and body:
            reply = say(f"Message from {app} — {summary!r}: {body!r}. Draft ONE short, "
                        f"natural reply in my voice, under 20 words, no greeting, no sign-off, "
                        f"plain text (this gets copied straight into the reply box).",
                        system=PERSONA, timeout=15).strip()
            if reply:
                out.append((f"notif_reply_{uid}",
                            f"{app} asked something — drafted a reply: {reply!r}", "normal",
                            f"Message from {app}: {summary!r} — {body!r}. I drafted this reply: "
                            f"{reply!r}. Call show_card with a 'buttons' block (Copy reply / "
                            f"Chat about it) — Copy reply should run clipboard_control to write "
                            f"{reply!r}, Chat about it should just continue the conversation "
                            f"with me about how to respond."))
                continue

        strictness = settings().get("residentStrictness", "balanced")
        proposal = _evaluate_notif(app, summary, body, strictness)
        if proposal:
            prefill = (f"Notification from {app}: {summary!r} — {body!r}. I think this "
                       f"needs a task: {proposal['title']}"
                       + (f" (eta {proposal['eta']})" if proposal["eta"] else "") +
                       ". Call show_card with a 'buttons' block (Accept/Decline/Chat about it) "
                       "to propose it to the user, then act if they accept.")
            out.append(("notif_" + str(uid), proposal["title"], "normal", prefill))
        else:
            out.append(("notif_" + str(uid), f"new notification from {app}: {summary}", "normal"))
    state["last_notif_uid"] = max_uid

    for m in mailbox_pending("resident"):
        out.append(("mail_" + str(m["id"]), f"note from {m.get('from','?')}: {m.get('msg','')}", "normal"))

    # Discord: surface people waiting on a reply (from the bridge's reply queue).
    # Dedup by the set of waiting channels so it nudges when the backlog changes,
    # not every cycle.
    pending = _discord_pending()
    if pending:
        sig = ",".join(sorted(p.get("channel_id", "") for p in pending))
        if sig and sig != state.get("discord_sig"):
            state["discord_sig"] = sig
            who = ", ".join(p.get("display_name") or p.get("username") or "someone" for p in pending[:4])
            n = len(pending)
            prefill = (f"{n} Discord conversation(s) waiting on a reply: {who}. Offer to handle them — "
                       "call show_card with a 'buttons' block (Reply now / Later) and, if accepted, "
                       "triage and respond per the autopilot rules.")
            out.append((f"discord_unread_{n}", f"{n} waiting on Discord: {who}", "normal", prefill))
    elif state.get("discord_sig"):
        state["discord_sig"] = ""

    bpct = _brightness_should_lower()
    if bpct is not None:
        out.append(("brightness_high",
                    f"it's night and screen brightness is still at {bpct}% "
                    f"(auto-dim got manually overridden)", "low"))

    wf = _wallpaper_fact(state)
    if wf:
        out.append(("wallpaper_" + str(now), wf, "low"))

    return out


def make_brief(ctx):
    sysd = ctx.get("system", {})
    bat = sysd.get("battery", {})
    sched = ctx.get("schedule", {})
    events = sched.get("events", [])
    tasks = sched.get("tasks", [])
    ev_lines = "; ".join(f"{e.get('title')} {e.get('time','')}".strip() for e in events) or "nothing scheduled"
    task_lines = "; ".join(t.get("title", "") for t in tasks) or "none"

    weather = ""
    try:
        weather = subprocess.run(["bash", os.path.join(QS, "calendar/weather.sh")],
                                 capture_output=True, text=True, timeout=8).stdout.strip()[:200]
    except Exception:
        pass

    yest = (date.today() - timedelta(days=1)).isoformat()
    focus = ""
    try:
        fout = subprocess.run(["python3", os.path.join(QS, "focustime/get_stats.py"), yest],
                              capture_output=True, text=True, timeout=10).stdout.strip()
        fd = json.loads(fout)
        apps = fd.get("apps") or fd.get("top") or []
        if isinstance(apps, list) and apps:
            focus = ", ".join(f"{a.get('name', a.get('app',''))} {a.get('time', a.get('seconds',''))}" for a in apps[:3])
    except Exception:
        pass

    facts = (f"Today's events: {ev_lines}. Open tasks: {task_lines}. "
             f"Battery: {bat.get('percent')}% {bat.get('status')}. "
             f"Weather: {weather or 'unknown'}. Yesterday's top apps: {focus or 'unknown'}.")
    msg = say(f"Give the user a warm 2-sentence morning brief from these facts. "
              f"Lead with what matters most today. Facts: {facts}",
              system=PERSONA.replace("ONE short line", "at most 2 short sentences"), timeout=25)
    return msg.strip()


# ---- generic periodic-check framework ────────────────────────────────────
# A "periodic check" is anything the resident should notice at most once
# every N days, independent of the 30s poll loop: a daily brief, a weekly
# ecosystem diagnose, any future recurring health check. Register a function
# here instead of hand-rolling another date-string comparison + STATE key —
# one place to see everything recurring, one dedup mechanism, one retry
# behavior (fn returning falsy — e.g. its data isn't ready yet — means "try
# again next poll", not "silently skipped until the next interval").
PERIODIC_CHECKS = []  # [(key, interval_days, fn(ctx, state) -> bool), ...]


def register_periodic(key, interval_days, fn):
    PERIODIC_CHECKS.append((key, interval_days, fn))


def run_periodic(ctx, state):
    now = time.time()
    last = state.setdefault("periodic_last_run", {})
    changed = False
    for key, interval_days, fn in PERIODIC_CHECKS:
        if now - last.get(key, 0) < interval_days * 86400:
            continue
        try:
            ran = fn(ctx, state)
        except Exception:
            ran = False
        if ran:
            last[key] = now
            changed = True
    if changed:
        save(STATE, state)


def _check_morning_brief(ctx, state):
    if not ctx.get("schedule"):
        return False
    mode = settings().get("residentMorningBrief", "text")
    if mode == "off":
        return True
    if extras is not None:
        if not extras._in_window(settings().get("residentBriefTime", "05:00-11:00")) or extras._is_away():
            return False
    msg = make_brief(ctx)
    if not msg:
        return False
    # No raw notify here — extras.run_morning_brief (below) already emits the
    # resident card (and speaks it in "spoken" mode), so a notify-send here
    # would just be a duplicate popup for the same brief.
    save(SUGGEST, {"key": "brief", "msg": msg, "urgency": "normal",
                   "ts": int(time.time()), "action_label": "", "action_cmd": ""})
    if extras is not None:
        extras.run_morning_brief(ctx, state)
    return True


DIAGNOSE_SH = os.path.join(QS, "claude/diagnose.sh")


def _check_diagnose(ctx, state):
    try:
        r = subprocess.run(["bash", DIAGNOSE_SH], capture_output=True, text=True, timeout=60)
    except Exception:
        return False   # couldn't even launch it — retry next poll instead of losing the week
    if r.returncode != 0:
        lines = [ln for ln in (r.stdout or "").splitlines() if ln.startswith(("✗", "⚠"))]
        summary = "; ".join(ln[2:].strip() for ln in lines[:3]) or "see diagnose.sh output"
        notified = load(NOTIFIED, {})
        propose_task_card("diagnose_weekly",
            f"Weekly ecosystem check found issues: {summary}. Ask me to look into it, or run "
            f"'bash {DIAGNOSE_SH} --live' yourself for the full picture.",
            notified)
    return True


def _check_eod_review(ctx, state):
    """#6 end-of-day-review — first poll after settings.residentEodHour
    (default 18:00), once/day. Full agent turn pins a 'Day' board card with
    focus stats, completed tasks, and tomorrow's first event."""
    eod_hour = int(settings().get("residentEodHour", EOD_HOUR))
    if time.localtime().tm_hour < eod_hour:
        return False
    today = date.today().isoformat()
    spawn_full_agent(
        f"It's end of day ({today}). Build me a short end-of-day review: call focus_stats "
        f"for today's app usage totals, list_tasks and note which look completed vs still "
        f"open, and list_events for tomorrow to surface just the first one. Then call "
        f"show_card with title 'Day' — a rows or text block summarizing focus time + top "
        f"apps, a short list of what got done today, and tomorrow's first commitment. "
        f"pinned:true, board:'Day', card_id:'eod_{today}'. Warm, brief, no filler.",
        tag=f"eod_review_{today}")
    return True


WAKE_MODEL_PATH = os.path.join(QS, "claude/voice/models/kandor.onnx")
WAKE_TRAIN_DIR = os.path.join(QS, "claude/voice/wake_train")
VOICE_CORPUS_MANIFEST = os.path.expanduser("~/.local/share/qs_voice_corpus/manifest.jsonl")
WAKE_MODEL_STALE_DAYS = 30


def _corpus_latest_ts():
    ts = 0
    try:
        with open(VOICE_CORPUS_MANIFEST) as f:
            for line in f:
                try:
                    ts = max(ts, json.loads(line).get("ts", 0))
                except (json.JSONDecodeError, AttributeError):
                    pass
    except OSError:
        pass
    return ts


def _check_wake_model_freshness(ctx, state):
    """Same idea as diagnose_weekly, but for the personal 'yo kandor' wake
    model — nudges a retrain when new voice samples have been recorded since
    the last train, or it just hasn't been refreshed in a while."""
    if not os.path.exists(WAKE_MODEL_PATH):
        return False   # not trained yet at all — nothing to keep fresh
    model_mtime = os.path.getmtime(WAKE_MODEL_PATH)
    corpus_ts = _corpus_latest_ts()
    if corpus_ts > model_mtime + 60:
        reason = "you've recorded new voice samples since it was last trained"
    elif time.time() - model_mtime > WAKE_MODEL_STALE_DAYS * 86400:
        reason = f"it hasn't been retrained in over {WAKE_MODEL_STALE_DAYS} days"
    else:
        return True   # fresh, nothing to say — but the weekly check itself happened
    notified = load(NOTIFIED, {})
    propose_task_card("wake_model_stale",
        f"The 'yo kandor' wake model could use a refresh — {reason}. Ask me to retrain it "
        f"(I'll call retrain_wake_model), or run 'bash {os.path.join(WAKE_TRAIN_DIR, 'run_pipeline.sh')} all' "
        f"yourself.",
        notified)
    return True


register_periodic("morning_brief", 1, _check_morning_brief)
register_periodic("diagnose_weekly", 7, _check_diagnose)
register_periodic("eod_review", 1, _check_eod_review)
register_periodic("wake_model_freshness", 7, _check_wake_model_freshness)


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
        ctx = load(CTX, {})
        notified = load(NOTIFIED, {})
        state = load(STATE, {})
        now = int(time.time())

        run_periodic(ctx, state)
        if extras is not None:
            extras.tick(ctx, state)

        if ctx:
            for item in detect(ctx, state, notified):
                key, fact, urgency = item[0], item[1], item[2]
                task_prefill = item[3] if len(item) > 3 else None
                if now - notified.get(key, 0) < RENOTIFY:
                    continue
                if task_prefill:
                    propose_task_card(key, task_prefill, notified)
                elif key == "battery_low":
                    surface(key, fact, urgency, notified, also_notify=False)
                else:
                    surface(key, fact, urgency, notified)
            _maybe_react_song(state)
            _expire_passive(now)
            for k in [k for k, v in notified.items() if now - v > RENOTIFY * 2]:
                notified.pop(k, None)
            save(NOTIFIED, notified)
        save(STATE, state)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
