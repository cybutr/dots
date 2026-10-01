#!/usr/bin/env python3
import os, sys, json, time, shutil, subprocess, glob, random
import urllib.request, urllib.error
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import resident_card

HOME = os.path.expanduser("~")
QS = os.path.join(HOME, ".config/hypr/scripts/quickshell")
QS_MANAGER = os.path.join(HOME, ".config/hypr/scripts/qs_manager.sh")
ECO_DAEMON = os.path.join(HOME, ".config/hypr/scripts/eco_daemon.py")
ECO_STATE = "/tmp/qs_eco_state.json"
SETTINGS_FILE = os.path.join(HOME, ".config/hypr/settings.json")
SUGGEST = "/tmp/qs_resident_suggestion"
HISTORY = "/tmp/qs_resident_history.json"
NOTIFICATIONS = "/tmp/qs_notifications.json"
IDLE_STATE = "/tmp/qs_idle_state"
LOCK_BRIEF = "/tmp/qs_lock_brief.json"
WEATHER = os.path.join(HOME, ".cache/quickshell/weather/weather.json")
ACTIONS_SH = os.path.join(HERE, "resident_actions.sh")
REAPER = os.path.join(HOME, ".config/hypr/scripts/leak_reaper.py")
DOWNLOADS = os.path.join(HOME, "Downloads")
SMARTWS_BASE = os.path.join(HOME, ".config/hypr/smartws")
SMARTWS_RESTORE_LOG = os.path.join(SMARTWS_BASE, "restore_log.json")
SMARTWS_PY = os.path.join(HOME, ".config/hypr/scripts/smartws.py")
STARTUP_CONF = os.path.join(HOME, ".config/hypr/scripts/quickshell/startup_apps.json")
STARTUP_DRIFT_LOG = "/tmp/qs_resident_startup_drift.json"
APPLY_STARTUP_WS = os.path.join(HERE, "apply_startup_ws.py")
LAYOUT_SUGGEST_COOLDOWN = 6 * 3600
LAYOUT_MIN_OCCURRENCES = 3
LAYOUT_WINDOW_DAYS = 14
LAYOUT_HOUR_TOLERANCE = 1.5
STARTUP_DRIFT_MIN_DAYS = 3
STARTUP_DRIFT_WINDOW_DAYS = 21
STARTUP_DRIFT_COOLDOWN = 7 * 86400
MUSIC_STATS_PY = os.path.join(QS, "music", "music_stats.py")
STATE_FILE = "/tmp/qs_resident_state"   # same file claude_resident.py's main loop loads/saves every poll
ACTION_LOG = "/tmp/qs_resident_action_log.jsonl"   # written by resident_actions.sh on every action click
MIN_AWAY_SECS = 120
FIX_INTERVAL = 600
FIX_COOLDOWN = 6 * 3600
DISK_USED_PCT = 88
DISK_FREE_GB = 8
DISK_USED_PCT_SEVERE = 95
DISK_FREE_GB_SEVERE = 3
MEM_HOG_PCT = 30
MEM_HOG_PCT_SEVERE = 50
BAT_HEALTH_SEVERE = 60
UPDATES_SEVERE = 60
LEAKS_SEVERE = 100
LOW_BATTERY_MINS_DEFAULT = 30
LOW_BATTERY_CLEAR_MARGIN = 1.3   # hysteresis: ttm has to climb back above threshold*margin to count as "cleared"
LOW_BATTERY_CHECK_INTERVAL = 60  # this bypasses FIX_INTERVAL entirely, see tick_low_battery
LOW_BATTERY_RENOTIFY_SECS = 600  # re-propose even without worsening after this long, still critical + not applied
LOW_BATTERY_WORSEN_MINS = 2      # ttm drop (minutes) that counts as "worse" pre-apply -> re-propose immediately
LOW_BATTERY_WORSEN_MINS_APPLIED = 5   # bigger drop needed post-apply before nagging again (nothing left to do)
LOW_BATTERY_PRIOR_FILE = "/tmp/qs_low_battery_prior.json"   # written/removed by low_battery_action.py; its
# presence IS the "applied" flag — the card action runs in its own process (resident_actions.sh ->
# low_battery_action.py), so state persisted here in tick()'s in-memory `state` dict can't observe it
# directly. Checking the file each tick keeps a single source of truth instead of two copies drifting.
HOG_NAME_BLOCKLIST = {"ps", "pgrep", "pkill", "grep", "awk", "sed", "cut", "sort", "head", "tail"}
ESSENTIAL_PROCS = {"hyprland", "quickshell", "xwayland", "pipewire", "wireplumber", "systemd", "dbus-daemon",
                   "sddm", "greetd", "login", "kwin_wayland"}
DRY = False

# ---- per-severity cooldown + dismiss-quiet-list ---------------------------
# Each proactive-fix category gets a cooldown scaled to how urgent it is
# (COOLDOWN_BY_URGENCY, with a couple of explicit COOLDOWN_OVERRIDE bumps for
# categories whose default urgency undersells how fast they should retry).
#
# There's no real "the user clicked X" signal from the topbar dismiss button
# (that's pure QML/local-file state, see TopBar.qml's residentDismiss()) —
# so "dismissed" here is a proxy: if a category gets proposed again while
# still true, and no action from resident_actions.sh was logged for that
# category since the previous proposal, we count the previous proposal as
# an implicit dismiss. state["fix_track"][category] = {"dismiss_ts": [...],
# "muted": bool, "muted_ts": ts} lives inside the same /tmp/qs_resident_state
# blob find_fixes' cooldowns already used (state["fix_last"]).
#
# After MUTE_THRESHOLD dismissals inside a MUTE_WINDOW_DAYS rolling window,
# the category stops proposing entirely — unless find_fixes flags it
# "severe" (a second, worse threshold — see DISK_USED_PCT_SEVERE etc. above)
# or MUTE_BACKOFF_DAYS has passed since it was muted, which auto-unmutes it.
#
# Inspect/manage muted categories: `resident_extras.py --list-muted` /
# `resident_extras.py --unmute <category>`.
COOLDOWN_BY_URGENCY = {"high": 3600, "normal": 6 * 3600, "low": 18 * 3600}
COOLDOWN_OVERRIDE = {"failed_units": 3600}
MUTE_THRESHOLD = 3
MUTE_WINDOW_DAYS = 14
MUTE_BACKOFF_DAYS = 30


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def _save(path, obj):
    try:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(obj, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass


def settings():
    return _load(SETTINGS_FILE, {})


def _run(cmd, timeout=8):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


def _action(label, category, *args):
    cmd = "RESIDENT_FIX_CATEGORY=" + _q(category) + " bash " + ACTIONS_SH + " " + " ".join(_q(a) for a in args)
    return {"label": label, "cmd": cmd}


def _q(s):
    return "'" + str(s).replace("'", "'\\''") + "'"


def _suggest_if_free(key, msg, urgency, label, cmd, tag):
    cur = _load(SUGGEST, {})
    if cur and time.time() - cur.get("ts", 0) < 300:
        return
    _save(SUGGEST, {"key": key, "msg": msg, "urgency": urgency, "ts": int(time.time()),
                    "action_label": label, "action_cmd": cmd, "label": tag[:10]})
    hist = _load(HISTORY, [])
    hist.append({"ts": int(time.time()), "msg": msg})
    _save(HISTORY, hist[-8:])


def mailbox_post(to, msg, frm="resident"):
    """Tiny local mirror of claude_resident.py's mailbox_post — kept separate
    to avoid a circular import (claude_resident already imports this module).
    Same file/schema, so any client's mailbox_read sees these too."""
    MAILBOX = "/tmp/qs_claude_mailbox.json"
    MAILBOX_MAX = 100
    msgs = _load(MAILBOX, [])
    msgs.append({"id": int(time.time() * 1000), "from": frm, "to": to, "msg": msg,
                 "ts": int(time.time()), "read": False})
    _save(MAILBOX, msgs[-MAILBOX_MAX:])


def stats_summary():
    """Read-only rollup of the resident's own track record, for the Guide's
    stats view. No writes, safe to call anytime."""
    st = _load(STATE_FILE, {})
    fix_track = st.get("fix_track", {}) or {}
    fix_last = st.get("fix_last", {}) or {}
    categories = []
    for key in sorted(set(fix_track) | set(fix_last)):
        track = fix_track.get(key, {})
        dismissals = len(track.get("dismiss_ts", []))
        categories.append({
            "key": key,
            "proposed": 1 if key in fix_last else 0,
            "resolved": 1 if track.get("celebrated_ts") else 0,
            "dismissals": dismissals,
            "muted": bool(track.get("muted")),
            "last_proposed_ts": fix_last.get(key, 0),
        })
    muted = [c["key"] for c in categories if c["muted"]]
    periodic = st.get("periodic_last_run", {}) or {}
    return {
        "categories": categories,
        "muted": muted,
        "periodic_last_run": periodic,
        "fix_active": st.get("fix_active", []),
    }


def speak(text):
    if DRY:
        print("[espeak dry-run]", text)
        return
    try:
        subprocess.Popen(["espeak", "-s", "155", "-v", "en", text], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


# ---------------------------------------------------------------- morning brief

def _in_window(spec):
    try:
        a, b = spec.split("-")
        now = datetime.now().strftime("%H:%M")
        return a <= now <= b
    except Exception:
        return True


def _weather_line():
    d = _load(WEATHER, {})
    fc = (d.get("forecast") or [{}])[0]
    if not fc:
        return ""
    return f"{fc.get('desc', '')} {fc.get('min', '?')} to {fc.get('max', '?')} degrees".strip()


def _notif_count():
    n = _load(NOTIFICATIONS, [])
    n = [x for x in n if isinstance(x, dict) and (x.get("appName") or "").lower() not in ("claude",)]
    return len(n)


def brief_facts(ctx):
    sysd = (ctx or {}).get("system", {})
    bat = sysd.get("battery", {})
    sched = (ctx or {}).get("schedule", {})
    events = sched.get("events", []) or []
    tasks = sched.get("tasks", []) or []
    sug = _load(SUGGEST, {})
    return {
        "weather": _weather_line(),
        "events": [f"{e.get('title', '')} {e.get('time', '')}".strip() for e in events[:4]],
        "tasks": [t.get("title", "") for t in tasks[:4]],
        "battery": f"{bat.get('percent')}% {bat.get('status')}" if bat.get("percent") is not None else "",
        "notifs": _notif_count(),
        "nudge": sug.get("msg", "") if sug and time.time() - sug.get("ts", 0) < 3600 else "",
    }


GREETINGS_AM = ["Good morning.", "Morning.", "Hey — here's today.", "Rise and shine."]
GREETINGS_PM = ["Good day.", "Hey.", "Here's where things stand.", "Quick catch-up."]
BRIEF_SECTIONS = ("weather", "events", "tasks", "battery", "notifs", "nudge")


def _spoken_sections():
    """residentBriefSpokenSections: 'all', or a comma string / list of the
    BRIEF_SECTIONS names to actually read aloud — trims what espeak says
    without touching the card/text version, which always shows everything."""
    raw = settings().get("residentBriefSpokenSections", "all")
    if raw in ("all", "", None):
        return set(BRIEF_SECTIONS)
    if isinstance(raw, list):
        return {str(x).strip() for x in raw}
    return {s.strip() for s in str(raw).split(",") if s.strip()}


def brief_text(facts, sections=None):
    sections = sections if sections is not None else set(BRIEF_SECTIONS)
    parts = []
    hour = datetime.now().hour
    parts.append(random.choice(GREETINGS_AM if hour < 12 else GREETINGS_PM))
    if "weather" in sections and facts["weather"]:
        parts.append(f"Weather today: {facts['weather']}.")
    if "events" in sections:
        parts.append("On your calendar: " + "; ".join(facts["events"]) + "."
                      if facts["events"] else "Nothing on your calendar.")
    if "tasks" in sections and facts["tasks"]:
        parts.append(f"{len(facts['tasks'])} open tasks, first: {facts['tasks'][0]}.")
    if "battery" in sections and facts["battery"]:
        parts.append(f"Battery {facts['battery']}.")
    if "notifs" in sections and facts["notifs"]:
        parts.append(f"{facts['notifs']} notifications waiting.")
    if "nudge" in sections and facts["nudge"]:
        parts.append("Also: " + facts["nudge"])
    return " ".join(parts)


BRIEF_CFG = {
    "morning": ("residentMorningBrief", "residentBriefTime", "05:00-11:00", "Morning brief"),
    "afternoon": ("residentAfternoonBrief", "residentAfternoonBriefTime", "13:00-16:00", "Afternoon brief"),
    "night": ("residentNightBrief", "residentNightBriefTime", "20:30-23:59", "Night brief"),
}
GREET = {
    "morning": ["Good morning", "Morning", "Rise and shine", "New day"],
    "afternoon": ["Good afternoon", "Afternoon check-in", "Halfway there", "Post-lunch stretch"],
    "night": ["Good evening", "Winding down", "Evening", "Almost done"],
}


def _forecast(offset):
    from datetime import timedelta
    fc = (_load(WEATHER, {}).get("forecast") or [])
    want = (datetime.now() + timedelta(days=offset)).day
    f = next((x for x in fc if str(x.get("date", "")).split(" ")[0].lstrip("0") == str(want)), None)
    if f is None:
        if len(fc) <= offset:
            return {}
        f = fc[offset]
    return {"icon": f.get("icon", ""), "desc": f.get("desc", ""), "min": f.get("min", ""), "max": f.get("max", ""),
            "sunrise": f.get("sunrise", ""), "sunset": f.get("sunset", ""), "pop": f.get("pop", ""),
            "hourly": [{"time": h.get("time", ""), "temp": h.get("temp", ""), "icon": h.get("icon", "")}
                       for h in (f.get("hourly") or [])[:5]]}


def _tomorrow_events():
    from datetime import timedelta
    t = datetime.now() + timedelta(days=1)
    try:
        out = json.loads(_run(["bash", os.path.join(QS, "calendar/schedule/month_events.sh"), t.strftime("%Y-%m")], timeout=30) or "{}")
    except Exception:
        return []
    items = (out.get(t.strftime("%Y-%m-%d")) or {}).get("items", [])
    timed = sorted([i for i in items if i.get("type") == "event"], key=lambda i: i.get("time", ""))
    return [{"title": i.get("title", ""), "time": i.get("time", "").split(" – ")[0]} for i in timed + [i for i in items if i.get("type") != "event"]][:3]


def _screen_today():
    fs = _load(FOCUS_STATE, {})
    apps = [a for a in fs.get("apps", []) if a.get("class") not in FOCUS_IDLE_CLASSES][:3]
    total = fs.get("total", 0) or 0
    return {"total": _fmt_dur(total), "totalSecs": total,
            "apps": [{"name": a.get("name", ""), "secs": a.get("seconds", 0),
                      "pct": round(a.get("seconds", 0) / total * 100) if total else 0} for a in apps]}


def _focus_sessions_today():
    today = datetime.now().strftime("%Y-%m-%d")
    sess = [x for x in _load(FOCUS_SESSIONS, []) if x.get("day") == today]
    return {"count": len(sess), "total": _fmt_dur(sum(x.get("secs", 0) for x in sess))}


def brief_payload(period, ctx):
    facts = brief_facts(ctx)
    now = time.time()
    evs = _timed_events()
    bat = ((ctx or {}).get("system", {}) or {}).get("battery", {}) or {}
    data = {
        "period": period,
        "greeting": random.choice(GREET[period]),
        "dateStr": datetime.now().strftime("%A, %B %-d"),
        "battery": {"pct": bat.get("percent", ""), "status": bat.get("status", "")},
        "notifs": facts["notifs"],
        "tasks": facts["tasks"],
        "nudge": facts["nudge"],
    }
    if period == "morning":
        data["weather"] = _forecast(0)
        data["events"] = [{"title": e.get("subject", ""), "time": e.get("time", "").split(" - ")[0]} for e in evs][:4]
    elif period == "afternoon":
        w = _forecast(0)
        hr = datetime.now().strftime("%H:%M")
        nxt = next((h for h in w.get("hourly", []) if h["time"] >= hr), (w.get("hourly") or [{}])[-1] if w.get("hourly") else {})
        data["weather"] = {"icon": nxt.get("icon", w.get("icon", "")), "temp": nxt.get("temp", ""), "desc": w.get("desc", ""),
                           "sunset": w.get("sunset", "")}
        left = [e for e in evs if e.get("end", 0) > now]
        data["left"] = [{"title": e.get("subject", ""), "time": e.get("time", "").split(" - ")[0],
                         "start": e.get("start", 0), "end": e.get("end", 0)} for e in left][:4]
        data["doneCount"] = len(evs) - len(left)
        data["screen"] = _screen_today()
        data["focus"] = _focus_sessions_today()
    else:
        data["tomorrow"] = _forecast(1)
        data["tomorrowEvents"] = _tomorrow_events()
        data["screen"] = _screen_today()
        data["focus"] = _focus_sessions_today()
        try:
            data["uptimeDays"] = int(float(_read_sys("/proc/uptime").split()[0]) // 86400)
        except (ValueError, IndexError):
            data["uptimeDays"] = 0
    return data


def brief_body(d):
    p = d["period"]
    lines = []
    if p == "morning":
        w = d.get("weather") or {}
        if w:
            lines.append(f"Weather: {w.get('desc', '')} {w.get('min', '')}–{w.get('max', '')}°")
        lines.append("Calendar: " + ("; ".join(f"{e['time']} {e['title']}" for e in d["events"]) or "clear"))
    elif p == "afternoon":
        lines.append("Left today: " + ("; ".join(f"{e['time']} {e['title']}" for e in d["left"]) or "nothing scheduled"))
        lines.append(f"Screen time so far: {d['screen']['total']}")
    else:
        te = d.get("tomorrowEvents") or []
        lines.append("Tomorrow: " + (f"{te[0]['time']} {te[0]['title']}" if te else "clear morning"))
        lines.append(f"Screen time today: {d['screen']['total']}")
    if d["tasks"]:
        lines.append("Tasks: " + "; ".join(d["tasks"]))
    lines.append(f"Notifications: {d['notifs']}")
    return "\n".join(lines)


def brief_speech(d):
    p = d["period"]
    parts = [d["greeting"] + "."]
    if p == "morning":
        w = d.get("weather") or {}
        if w:
            parts.append(f"{w.get('desc', '')}, {w.get('min', '')} to {w.get('max', '')} degrees.")
        parts.append(("First up: " + d["events"][0]["title"] + " at " + d["events"][0]["time"] + ".") if d["events"] else "Your calendar is clear.")
    elif p == "afternoon":
        parts.append((f"{len(d['left'])} things left today, next is {d['left'][0]['title']} at {d['left'][0]['time']}.") if d["left"] else "Nothing else on the calendar today.")
        parts.append(f"You've had {d['screen']['total']} of screen time so far.")
    else:
        te = d.get("tomorrowEvents") or []
        parts.append(("Tomorrow starts with " + te[0]["title"] + " at " + te[0]["time"] + ".") if te else "Tomorrow morning is clear.")
        parts.append(f"{d['screen']['total']} on screen today. Time to wind down.")
    if d["notifs"]:
        parts.append(f"{d['notifs']} notifications waiting.")
    return " ".join(parts)


def run_brief(period, ctx, state, force=False, dry=False):
    global DRY
    DRY = dry
    s = settings()
    mode_key, win_key, win_default, title = BRIEF_CFG[period]
    mode = s.get(mode_key, "text")
    if mode == "off" and not force:
        return True
    if not force and not _in_window(s.get(win_key, win_default)):
        return False
    if not force and _is_away():
        return False
    data = brief_payload(period, ctx)
    body = brief_body(data)
    card = resident_card.emit(title, body, "weather-clear", "normal", None, [], "resident",
                              f"brief-{period}-" + datetime.now().strftime("%Y%m%d"), kind="brief", data=data)
    if mode == "spoken" or (force and not dry):
        speak(brief_speech(data))
    elif dry:
        print("[espeak dry-run]", brief_speech(data))
    if not dry:
        mailbox_post("user", f"{title}: " + body.splitlines()[0], frm="resident")
    return card or True


def run_morning_brief(ctx, state, force=False, dry=False):
    return run_brief("morning", ctx, state, force, dry)


def tick_day_briefs(ctx, state):
    done = state.setdefault("brief_done", {})
    today = datetime.now().strftime("%Y-%m-%d")
    for period in ("afternoon", "night"):
        if done.get(period) == today:
            continue
        if run_brief(period, ctx, state):
            done[period] = today


# ---------------------------------------------------------------- catch-up

def _is_locked():
    return bool(_run(["pgrep", "-f", "quickshell.*Lock.qml"]))


def _is_away():
    try:
        with open(IDLE_STATE) as f:
            if f.read().strip() == "idle":
                return True
    except OSError:
        pass
    return _is_locked()


def _max_uid():
    n = _load(NOTIFICATIONS, [])
    uids = [x.get("uid", 0) for x in n if isinstance(x, dict)]
    return max(uids) if uids else 0


def _new_downloads(since):
    out = []
    try:
        for name in os.listdir(DOWNLOADS):
            if name.endswith((".part", ".crdownload", ".tmp")) or name.startswith("."):
                continue
            p = os.path.join(DOWNLOADS, name)
            if os.path.getmtime(p) > since:
                out.append(name)
    except OSError:
        pass
    return out[:6]


def _git_changes(ctx, since):
    focus = (ctx or {}).get("focus", {}) or {}
    cwd = focus.get("cwd") or ""
    if not cwd or not os.path.isdir(cwd):
        return ""
    top = _run(["git", "-C", cwd, "rev-parse", "--show-toplevel"])
    if not top:
        return ""
    n = _run(["git", "-C", top, "log", f"--since=@{int(since)}", "--oneline"]).splitlines()
    dirty = [ln for ln in _run(["git", "-C", top, "status", "--porcelain"]).splitlines() if ln.strip()]
    bits = []
    if n:
        bits.append(f"{len(n)} new commit{'s' if len(n) != 1 else ''}")
    if dirty:
        files = [ln[3:].strip() for ln in dirty]
        shown = ", ".join(files[:5]) + (f" +{len(files) - 5} more" if len(files) > 5 else "")
        bits.append(f"{len(files)} changed file{'s' if len(files) != 1 else ''}: {shown}")
    return f"{os.path.basename(top)}: " + "; ".join(bits) if bits else ""


def _discord_count():
    import socket
    path = os.environ.get("DISCORD_MCP_SOCK", f"/run/user/{os.getuid()}/discord-mcp-bridge.sock")
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.5)
        s.connect(path)
        s.sendall(json.dumps({"id": 1, "action": "__bridge_queue"}).encode() + b"\n")
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        s.close()
        return len((json.loads(buf.split(b"\n", 1)[0]).get("result") or {}).get("pending", []) or [])
    except Exception:
        return 0


def _dur(secs):
    m = int(secs // 60)
    return f"{m // 60}h {m % 60}m" if m >= 60 else f"{m}m"


def build_catchup(ctx, away):
    start = away["start"]
    items = []
    notes = _load(NOTIFICATIONS, [])
    new = [x for x in notes if isinstance(x, dict) and x.get("uid", 0) > away.get("uid", 0)
           and (x.get("appName") or "").lower() != "claude"]
    if new:
        apps = {}
        for x in new:
            apps[x.get("appName", "app")] = apps.get(x.get("appName", "app"), 0) + 1
        top = ", ".join(f"{a} ×{c}" if c > 1 else a for a, c in sorted(apps.items(), key=lambda kv: -kv[1])[:3])
        items.append(f"{len(new)} new notifications ({top})")
    dl = _new_downloads(start)
    if dl:
        items.append("Downloaded: " + ", ".join(dl[:3]) + (f" +{len(dl) - 3} more" if len(dl) > 3 else ""))
    git = _git_changes(ctx, start)
    if git:
        items.append(git)
    dc = _discord_count()
    if dc:
        items.append(f"{dc} Discord conversation{'s' if dc != 1 else ''} waiting for a reply")
    bat = ((ctx or {}).get("system", {}) or {}).get("battery", {}) or {}
    if bat.get("percent") is not None and away.get("battery") not in (None, bat.get("percent")):
        items.append(f"Battery {away['battery']}% → {bat.get('percent')}%")
    dur = _dur(time.time() - start)
    if items:
        lead = random.choice([f"Away {dur}", f"While you were away ({dur})", f"You were gone {dur}"])
        headline = f"{lead} — {len(items)} thing{'s' if len(items) != 1 else ''} to know"
    else:
        headline = random.choice([f"Away {dur} — nothing happened", f"Away {dur} — quiet, nothing to report"])
    return {"ts": int(time.time()), "headline": headline, "items": items}


def tick_catchup(ctx, state, force_finalize=False, dry=False):
    global DRY
    DRY = dry
    if not settings().get("residentCatchUp", True):
        state.pop("away", None)
        return
    away_now = _is_away()
    away = state.get("away")
    bat = (((ctx or {}).get("system", {}) or {}).get("battery", {}) or {}).get("percent")
    if away_now and not away:
        state["away"] = {"start": int(time.time()), "uid": _max_uid(), "battery": bat}
        return
    if away and away_now:
        if time.time() - away["start"] >= MIN_AWAY_SECS:
            _save(LOCK_BRIEF, build_catchup(ctx, away))
        return
    if away and not away_now:
        state.pop("away", None)
        if time.time() - away["start"] < MIN_AWAY_SECS:
            return
        brief = build_catchup(ctx, away)
        _save(LOCK_BRIEF, brief)
        resident_card.emit("While you were away", brief["headline"] + ("\n" + "\n".join("• " + i for i in brief["items"]) if brief["items"] else ""),
                           "history", "low", None, [], "resident", "catchup-" + str(away["start"]))
        if brief["items"]:
            mailbox_post("user", brief["headline"] + ": " + "; ".join(brief["items"]))


# ---------------------------------------------------------------- proactive fixes

def _cooldown_ok(state, key, urgency="normal"):
    last = state.get("fix_last", {})
    secs = COOLDOWN_OVERRIDE.get(key, COOLDOWN_BY_URGENCY.get(urgency, FIX_COOLDOWN))
    return time.time() - last.get(key, 0) >= secs


def _action_ran_since(category, since_ts):
    try:
        with open(ACTION_LOG) as f:
            lines = f.read().splitlines()
    except OSError:
        return False
    for ln in lines[-500:]:
        try:
            e = json.loads(ln)
        except Exception:
            continue
        if e.get("category") == category and e.get("ts", 0) >= since_ts:
            return True
    return False


TITLE_VARIANTS = {
    "disk_full": ["Disk nearly full", "Running low on disk space", "Disk space is getting tight"],
    "leaks": ["Leaked watchers piling up", "Orphaned processes stacking up", "Some watchers never got cleaned up"],
    "bat_health": ["Battery health {pct}%", "Battery's at {pct}% health now", "Battery wear check: {pct}%"],
}


def _vary(key, title, **fmt):
    variants = TITLE_VARIANTS.get(key)
    if not variants:
        return title
    return random.choice(variants).format(**fmt) if fmt else random.choice(variants)


CATEGORY_LABEL = {
    "disk_full": "disk warning", "leaks": "leaked watchers", "failed_units": "failed service(s)",
    "updates": "pending updates",
}
CELEBRATE_PHRASES = [
    "Cleared {thing} — nice.",
    "Good news: {thing} is sorted now.",
    "{thing} looks clear again.",
]


def _celebrate_label(key):
    if key.startswith("mem_hog_"):
        return f"the {key[len('mem_hog_'):]} memory hog"
    return "the " + (CATEGORY_LABEL.get(key) or key.replace("_", " "))


def _celebrate_resolved(state, prev_keys, cur_keys):
    """A category that was active last scan and isn't anymore, where an
    action for it actually ran since it was last proposed, gets a short
    low-key confirmation card — the follow-up half of the fire-and-forget
    action loop (was previously silent either way)."""
    resolved = set(prev_keys) - set(cur_keys)
    fix_last = state.get("fix_last", {})
    for key in resolved:
        last_ts = fix_last.get(key, 0)
        if not last_ts or not _action_ran_since(key, last_ts):
            continue
        track = state.setdefault("fix_track", {}).setdefault(key, {})
        if track.get("celebrated_ts", 0) >= last_ts:
            continue
        track["celebrated_ts"] = time.time()
        thing = _celebrate_label(key)
        msg = random.choice(CELEBRATE_PHRASES).format(thing=thing)
        osd_fact = ""
        if key == "disk_full" and state.get("fix_disk_free_at_propose"):
            freed = shutil.disk_usage("/").free - state["fix_disk_free_at_propose"]
            if freed > 100 * 1e6:
                osd_fact = f"freed {_gb(freed)}"
                msg += f" Freed about {_gb(freed)}."
        resident_card.emit("Nice — fixed", msg, "emblem-default", "low", 10, [], "resident",
                           "celebrate-" + key + "-" + str(int(time.time())))
        # Shortest-lived channel — a quick flash for the single headline fact
        # instead of making them read the full card for something this
        # small. Only fired here, at the resolve-confirmation moment.
        resident_card.osd(osd_fact if osd_fact else thing + " fixed", "emblem-default", "#a6e3a1")
        # Light two-way mailbox touch — any other Claude Code session working
        # in this repo can mailbox_read('user') and see what the resident
        # just handled, without needing to have been watching the card queue.
        mailbox_post("user", msg, frm="resident")


def _biggest_caches(n=3):
    root = os.path.join(HOME, ".cache")
    sizes = []
    try:
        for name in os.listdir(root):
            p = os.path.join(root, name)
            if os.path.isdir(p) and not os.path.islink(p):
                out = _run(["du", "-sk", p], timeout=15)
                if out:
                    sizes.append((int(out.split()[0]) * 1024, name))
    except OSError:
        pass
    return sorted(sizes, reverse=True)[:n]


def _gb(b):
    return f"{b / 1e9:.1f}GB"


SPOTIFY_MCP_DIR = os.path.join(HOME, ".local/share/spotify-mcp")
SPOTIFY_CONFIG = os.path.join(SPOTIFY_MCP_DIR, "spotify-config.json")
CALENDAR_TOKEN = os.path.join(HOME, ".local/share/qs_calendar_oauth")
CALENDAR_SETUP = os.path.join(QS, "calendar/schedule/setup_auth.py")


def _check_spotify_auth():
    # Read-only probe (GET /v1/me with the stored access token) — NOT a
    # refresh-token exchange. A refresh call actually consumes the stored
    # refresh token, and this rice can have several spotify-mcp node
    # processes alive at once (one per concurrent Claude Code session, each
    # with its own in-memory copy) — a real failure seen once was diagnosed
    # as exactly that: one session's refresh had already rotated the shared
    # on-disk token hours after another session's process last read it, and
    # a naive test-refresh here would only add a fourth racer. Read-only
    # avoids that class of self-inflicted problem entirely.
    try:
        with open(SPOTIFY_CONFIG) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return None  # not configured — not this rice's problem to flag
    token = cfg.get("accessToken", "")
    if not token:
        return False
    try:
        req = urllib.request.Request(
            "https://api.spotify.com/v1/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urllib.request.urlopen(req, timeout=6) as resp:
            resp.read()
        return True
    except urllib.error.HTTPError as e:
        return e.code != 401
    except Exception:
        return None  # network hiccup etc — not a credential verdict, don't flag


def _check_calendar_auth():
    if not os.path.exists(CALENDAR_TOKEN):
        return None
    try:
        import pickle
        with open(CALENDAR_TOKEN, "rb") as f:
            creds = pickle.load(f)
        if not creds.expired:
            return True
        if not creds.refresh_token:
            return False
        from google.auth.transport.requests import Request
        creds.refresh(Request())
        return True
    except ImportError:
        return None  # google-auth libs unavailable to this interpreter — skip, don't false-positive
    except Exception:
        return False


MIRA_UNREAD_FILE = "/tmp/qs_mira_unread.json"


def _read_mira_unread():
    try:
        with open(MIRA_UNREAD_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def _check_gmail_auth():
    # Same token file as calendar — the failure mode this actually needs to
    # catch is "token exists and refreshes fine but lacks gmail.readonly"
    # (e.g. scope added after the token was first created, user hasn't
    # re-run setup_auth.py yet), which _check_calendar_auth's expiry-only
    # check wouldn't catch since the token can be perfectly valid for
    # calendar while still missing the gmail scope entirely.
    if not os.path.exists(CALENDAR_TOKEN):
        return None
    try:
        import pickle
        with open(CALENDAR_TOKEN, "rb") as f:
            creds = pickle.load(f)
        if "https://www.googleapis.com/auth/gmail.readonly" not in (creds.scopes or []):
            return False
        if creds.expired and not creds.refresh_token:
            return False
        return True
    except ImportError:
        return None
    except Exception:
        return False


def find_fixes(state, force=False):
    # each finding is (key, title, body, icon, urgency, actions, severe) —
    # "severe" is the second, worse threshold that can bypass a mute (see
    # the dismiss/mute block above _cooldown_ok).
    found = []

    spotify_ok = _check_spotify_auth()
    if spotify_ok is False or force:
        found.append(("spotify_auth", "Spotify credentials expired",
                      "The stored access token is being rejected (401) — this is the on-disk credential itself, not "
                      "just one session's stale connection, so a plain reconnect won't fix it. Re-authenticate.",
                      "dialog-password", "normal",
                      [_action("copy reauth command", "spotify_auth", "copy",
                                f"cd {SPOTIFY_MCP_DIR} && npm run auth")],
                      True))
    calendar_ok = _check_calendar_auth()
    if calendar_ok is False or force:
        found.append(("calendar_auth", "Calendar credentials expired",
                      "Google Calendar's refresh token is dead — the clock pill's agenda will stay stale until you re-authenticate.",
                      "dialog-password", "normal",
                      [_action("copy reauth command", "calendar_auth", "copy",
                                f"python3 {CALENDAR_SETUP}")],
                      True))
    gmail_ok = _check_gmail_auth()
    if gmail_ok is False or force:
        found.append(("gmail_auth", "Gmail credentials need re-auth",
                      "The gmail code-watcher can't read your inbox — either the token is missing the gmail.readonly "
                      "scope or it's expired. Re-authenticate to fix both.",
                      "dialog-password", "normal",
                      [_action("copy reauth command", "gmail_auth", "copy",
                                f"python3 {CALENDAR_SETUP}")],
                      True))

    mira_unread = _read_mira_unread()
    if mira_unread and mira_unread.get("error") == "reauth":
        found.append(("mira_auth", "Mira needs reauth",
                      "Gmail client's stored token was rejected (likely the Google Cloud OAuth consent "
                      "screen is still in Testing mode, which force-expires refresh tokens weekly). "
                      "Open Mira and reconnect the account.",
                      "dialog-password", "normal",
                      [_action("open mira", "mira_auth", "open_mira")],
                      True))

    du = shutil.disk_usage("/")
    pct = du.used / du.total * 100
    if pct >= DISK_USED_PCT or du.free < DISK_FREE_GB * 1e9 or force:
        caches = _biggest_caches()
        acts = []
        if caches:
            size, name = caches[0]
            acts.append(_action(f"clear {name} ({_gb(size)})", "disk_full", "clear_cache", name))
        acts.append(_action("vacuum user journal", "disk_full", "vacuum_user_journal"))
        acts.append(_action("copy pacman cleanup", "disk_full", "copy", "sudo paccache -rk2"))
        body = f"Root is {pct:.0f}% full, {_gb(du.free)} free."
        if caches:
            body += "\nBiggest caches: " + ", ".join(f"{n} {_gb(s)}" for s, n in caches)
        severe = pct >= DISK_USED_PCT_SEVERE or du.free < DISK_FREE_GB_SEVERE * 1e9
        found.append(("disk_full", "Disk nearly full", body, "drive-harddisk", "high", acts, severe))
    ppid1 = _run(["bash", "-c", "ps -eo ppid=,args= | awk '$1==1' | grep -c 'inotifywait\\|playerctl'"])
    reaper_up = bool(_run(["pgrep", "-f", "leak_reaper.py"]))
    if (ppid1.isdigit() and int(ppid1) > 40 and not reaper_up) or force and not reaper_up:
        n = int(ppid1) if ppid1.isdigit() else 0
        found.append(("leaks", "Leaked watchers piling up",
                      f"{ppid1} orphaned watcher processes and the leak reaper isn't running.",
                      "utilities-system-monitor", "normal",
                      [_action("start leak reaper", "leaks", "start_leak_reaper")], n > LEAKS_SEVERE))
    total_kb = 0
    try:
        with open("/proc/meminfo") as f:
            total_kb = int(f.readline().split()[1])
    except (OSError, ValueError):
        pass
    if total_kb:
        out = _run(["ps", "-eo", "pid=,rss=,comm=", "--sort=-rss"]).splitlines()[:1]
        for line in out:
            parts = line.split(None, 2)
            if len(parts) == 3:
                pid, rss, comm = parts
                share = int(rss) / total_kb * 100
                if (share >= MEM_HOG_PCT or force) and comm.lower() not in HOG_NAME_BLOCKLIST | ESSENTIAL_PROCS:
                    found.append(("mem_hog_" + comm, f"{comm} is using {share:.0f}% of RAM",
                                  f"{comm} (pid {pid}) holds {_gb(int(rss) * 1024)}.", "dialog-warning", "normal",
                                  [_action(f"kill {comm}", "mem_hog_" + comm, "kill_hog", pid)],
                                  share >= MEM_HOG_PCT_SEVERE))
    failed = [ln.split()[1] if ln.startswith("●") else ln.split()[0]
              for ln in _run(["systemctl", "--user", "--failed", "--no-legend"]).splitlines() if ln.strip()]
    if failed:
        found.append(("failed_units", f"{len(failed)} user service{'s' if len(failed) != 1 else ''} failed",
                      ", ".join(failed[:5]), "dialog-error", "normal",
                      [_action(f"restart {failed[0]}", "failed_units", "restart_failed_unit", failed[0])],
                      len(failed) >= 3))
    if shutil.which("checkupdates"):
        ups = [ln for ln in _run(["checkupdates"], timeout=30).splitlines() if ln.strip()]
        if len(ups) >= 25 or (force and ups):
            found.append(("updates", f"{len(ups)} package updates pending",
                          ", ".join(ln.split()[0] for ln in ups[:6]) + (" …" if len(ups) > 6 else ""),
                          "software-update-available", "low",
                          [_action("copy update command", "updates", "copy", "sudo pacman -Syu")],
                          len(ups) >= UPDATES_SEVERE))
    try:
        full = int(open("/sys/class/power_supply/BAT0/energy_full").read())
        design = int(open("/sys/class/power_supply/BAT0/energy_full_design").read())
        health = full / design * 100
        if health < 80 or force:
            found.append(("bat_health", f"Battery health {health:.0f}%",
                          "Keep it between 20% and 80% and avoid heat; a charge limit would slow the wear.",
                          "battery", "low",
                          [{"label": "open battery", "cmd": f"bash {QS_MANAGER} open battery"}],
                          health < BAT_HEALTH_SEVERE))
    except (OSError, ValueError, ZeroDivisionError):
        pass
    return found


# ---------------------------------------------------------------- low battery emergency
#
# Deliberately NOT folded into find_fixes()/tick_fixes() — that pipeline's
# mute-after-3-dismissals + COOLDOWN_BY_URGENCY scaling is exactly wrong for
# a battery emergency (see module docstring-equivalent note in the handback:
# routine nags should go quiet, "empty in 12 minutes" never should). This
# runs its own tiny state machine, called directly from tick(), keyed off
# upower's real time-to-empty rather than the coarse percent check
# claude_resident.py's own detect()/battery_low already does.

def _battery_device():
    for line in _run(["upower", "-e"]).splitlines():
        line = line.strip()
        if "/battery_" in line:
            return line
    return None


def _parse_upower_minutes(raw):
    """upower prints e.g. '30,0 minutes' or '1,2 hours' (locale-decimal)."""
    parts = raw.replace(",", ".").split()
    if len(parts) < 2:
        return None
    try:
        val = float(parts[0])
    except ValueError:
        return None
    return val * 60 if parts[1].lower().startswith("hour") else val


def _battery_info():
    dev = _battery_device()
    if not dev:
        return None
    info = {"status": None, "percent": None, "ttm_mins": None}
    for line in _run(["upower", "-i", dev]).splitlines():
        line = line.strip()
        if line.startswith("state:"):
            info["status"] = line.split(":", 1)[1].strip().lower()
        elif line.startswith("percentage:"):
            try:
                info["percent"] = int(line.split(":", 1)[1].strip().rstrip("%"))
            except ValueError:
                pass
        elif line.startswith("time to empty:"):
            info["ttm_mins"] = _parse_upower_minutes(line.split(":", 1)[1].strip())
    return info


def _low_battery_applied():
    return os.path.exists(LOW_BATTERY_PRIOR_FILE)


def _propose_low_battery_revert(lb):
    body = ("Battery's no longer critical — restore normal eco freeze/throttle timing "
            "(the emergency settings are still active).")
    return resident_card.emit(
        "Restore normal eco settings?", body, "battery-good", "normal", None,
        [_action("restore normal eco settings", "low_battery", "restore_eco")],
        "resident", "low-battery-revert-" + str(int(time.time())))


def tick_low_battery(state, force=False, dry=False):
    global DRY
    DRY = dry
    now = time.time()
    if not force and now - state.get("low_battery_checked", 0) < LOW_BATTERY_CHECK_INTERVAL:
        return None
    state["low_battery_checked"] = now

    info = _battery_info()
    lb = state.setdefault("low_battery", {})
    discharging = bool(info) and info.get("status") == "discharging" and info.get("ttm_mins") is not None
    applied = _low_battery_applied()

    if not discharging:
        # plugged in / charging / full / unreadable -> if the emergency fix
        # is still active, propose putting eco settings back, once.
        if applied and not lb.get("revert_proposed"):
            lb["revert_proposed"] = True
            return _propose_low_battery_revert(lb)
        if not info or info.get("status") != "discharging":
            state["low_battery"] = {}   # discharge cycle over, start clean next time
        return None

    threshold = float(settings().get("residentLowBatteryMins", LOW_BATTERY_MINS_DEFAULT)
                       or LOW_BATTERY_MINS_DEFAULT)
    ttm = info["ttm_mins"]
    pct = info.get("percent")

    if ttm >= threshold * LOW_BATTERY_CLEAR_MARGIN:
        if applied and not lb.get("revert_proposed"):
            lb["revert_proposed"] = True
            return _propose_low_battery_revert(lb)
        return None
    if ttm >= threshold:
        return None   # in the hysteresis band, not critical, don't (re)propose

    lb["revert_proposed"] = False

    if applied:
        worst = lb.get("worst_ttm", ttm)
        if ttm > worst - LOW_BATTERY_WORSEN_MINS_APPLIED:
            return None   # already handled it, hasn't meaningfully worsened since
        lb["worst_ttm"] = ttm
        body = f"Battery empty in ~{ttm:.0f} min ({pct}%) — still dropping with emergency power-save already on."
        return resident_card.emit("Battery still critical", body, "battery-caution", "high", None, [],
                                  "resident", "low-battery-worse-" + str(int(now)))

    last_ttm = lb.get("last_proposed_ttm")
    last_ts = lb.get("last_proposed_ts", 0)
    worsened = last_ttm is None or ttm <= last_ttm - LOW_BATTERY_WORSEN_MINS
    stale = now - last_ts >= LOW_BATTERY_RENOTIFY_SECS
    if not (worsened or stale):
        return None

    lb["last_proposed_ttm"] = ttm
    lb["last_proposed_ts"] = now
    lb["worst_ttm"] = min(ttm, lb.get("worst_ttm", ttm))
    body = f"Battery empty in ~{ttm:.0f} min ({pct}%) — freeze background apps hard to stretch it?"
    actions = [_action("apply emergency power-save", "low_battery", "emergency_power_save")]
    return resident_card.emit("Battery critically low", body, "battery-caution", "high", None, actions,
                              "resident", "low-battery-" + str(int(now)))


def tick_fixes(state, force=False, dry=False):
    if settings().get("residentProactiveFixes", "suggest") == "off" and not force:
        return []
    now = time.time()
    if not force and now - state.get("fix_checked", 0) < FIX_INTERVAL:
        return []
    state["fix_checked"] = now

    found = find_fixes(state, force)
    found_keys = {f[0] for f in found}
    _celebrate_resolved(state, state.get("fix_active", []), found_keys)
    state["fix_active"] = sorted(found_keys)

    emitted = []
    for key, title, body, icon, urgency, actions, severe in found:
        track = state.setdefault("fix_track", {}).setdefault(key, {})
        if track.get("muted") and not force:
            if severe:
                pass   # meaningfully worse now — surface it once despite the mute
            elif now - track.get("muted_ts", 0) >= MUTE_BACKOFF_DAYS * 86400:
                track["muted"] = False
                track["dismiss_ts"] = []
            else:
                continue
        if not force and not _cooldown_ok(state, key, urgency):
            continue

        prev_ts = state.get("fix_last", {}).get(key, 0)
        if prev_ts and not _action_ran_since(key, prev_ts):
            ts_list = [t for t in track.get("dismiss_ts", []) if t >= now - MUTE_WINDOW_DAYS * 86400]
            ts_list.append(now)
            track["dismiss_ts"] = ts_list
            if len(ts_list) >= MUTE_THRESHOLD and not severe:
                track["muted"] = True
                track["muted_ts"] = now
        state.setdefault("fix_last", {})[key] = now
        if key == "disk_full":
            state["fix_disk_free_at_propose"] = shutil.disk_usage("/").free

        vtitle = _vary(key, title) if key != "bat_health" else _vary(key, title, pct=title.split()[-1].rstrip("%"))
        card = resident_card.emit(vtitle, body, icon, urgency, None, actions, "resident", "fix-" + key)
        emitted.append(card)
        pill = resident_card.pill_for_fix_key(key)
        if pill:
            resident_card.pill_flag(pill, urgency=urgency)
        if actions:
            _suggest_if_free("fix_" + key, f"{vtitle}: {body.splitlines()[0]}", urgency,
                             actions[0]["label"][:24], actions[0]["cmd"], "fix")
    return emitted


# ---------------------------------------------------------------- layout suggestions

def _hour_close(a, b, tol=LAYOUT_HOUR_TOLERANCE):
    d = abs(a - b) % 24
    return min(d, 24 - d) <= tol


def tick_layout_suggest(state):
    """Notices recurring manual `smartws restore <name>` patterns around the
    current time of day (via smartws.py's restore_log.json) and proposes
    re-running the same restore — simple frequency/recency heuristic, not
    meant to be anything smarter than that. Never auto-restores."""
    s = settings()
    if not s.get("residentLayoutSuggestions", True) or not s.get("smartWsLayoutsEnabled", True):
        return
    log = _load(SMARTWS_RESTORE_LOG, [])
    if not log:
        return
    now = time.time()
    now_dt = datetime.now()
    cur_hour = now_dt.hour + now_dt.minute / 60.0
    cutoff = now - LAYOUT_WINDOW_DAYS * 86400
    by_name = {}
    for e in log:
        if not isinstance(e, dict) or e.get("ts", 0) < cutoff or not e.get("name"):
            continue
        by_name.setdefault(e["name"], []).append(e)

    today = now_dt.date().isoformat()
    best = None
    for name, events in by_name.items():
        near = [e for e in events if _hour_close(e.get("hour", 0), cur_hour)]
        if len(near) < LAYOUT_MIN_OCCURRENCES:
            continue
        if any(datetime.fromtimestamp(e["ts"]).date().isoformat() == today for e in events):
            continue   # already restored (this layout) today
        if not best or len(near) > len(best[1]):
            best = (name, near)
    if not best:
        return
    name, near = best
    track = state.setdefault("layout_suggest_track", {})
    if now - track.get(name, 0) < LAYOUT_SUGGEST_COOLDOWN:
        return
    track[name] = now
    resident_card.emit(
        f'Restore "{name}" layout?',
        f"You've restored this layout around this time of day {len(near)} times in the last "
        f"{LAYOUT_WINDOW_DAYS} days.",
        "view-restore", "low", None,
        [{"label": f"restore {name}", "cmd": f"python3 {SMARTWS_PY} restore {_q(name)}"}],
        "resident", "layout-suggest-" + name)


def _startup_entries():
    return [e for e in _load(STARTUP_CONF, [])
            if isinstance(e, dict) and e.get("class") and e.get("workspace")]


def _live_class_workspaces():
    out = _run(["hyprctl", "clients", "-j"])
    try:
        clients = json.loads(out or "[]")
    except Exception:
        return {}
    by_cls = {}
    for c in clients:
        if not isinstance(c, dict):
            continue
        cls = c.get("class", "")
        ws = c.get("workspace", {}).get("name")
        if ws is None:
            ws = c.get("workspace", {}).get("id")
        if not cls or ws is None:
            continue
        by_cls.setdefault(cls, []).append(str(ws))
    return by_cls


def tick_startup_drift(state):
    """Complements tick_layout_suggest: if a startup_apps.json-managed app
    keeps ending up (drifting to) a workspace that ISN'T the one configured
    for it, on enough distinct days, propose updating startup_apps.json to
    match reality instead of leaving the config to silently go stale.
    Proposal-only — the card action runs apply_startup_ws.py, nothing here
    ever edits startup_apps.json on its own."""
    if not settings().get("residentLayoutSuggestions", True):
        return
    entries = _startup_entries()
    if not entries:
        return
    live = _live_class_workspaces()
    today = datetime.now().date().isoformat()
    cutoff = time.time() - STARTUP_DRIFT_WINDOW_DAYS * 86400
    log = [e for e in _load(STARTUP_DRIFT_LOG, []) if isinstance(e, dict) and e.get("ts", 0) >= cutoff]

    changed = False
    for entry in entries:
        cls, configured_ws = entry["class"], str(entry["workspace"])
        observed = [w for w in (live.get(cls) or []) if w and not w.startswith("special") and w != configured_ws]
        if not observed:
            continue
        if any(e.get("class") == cls and e.get("day") == today for e in log):
            continue
        log.append({"class": cls, "observed": observed[0], "day": today, "ts": time.time()})
        changed = True
    if changed:
        log = log[-400:]
        _save(STARTUP_DRIFT_LOG, log)

    track = state.setdefault("startup_drift_track", {})
    for entry in entries:
        cls, configured_ws = entry["class"], str(entry["workspace"])
        name = entry.get("name") or cls
        recs = [e for e in log if e.get("class") == cls]
        if not recs:
            continue
        counts = {}
        for e in recs:
            counts[e.get("observed")] = counts.get(e.get("observed"), 0) + 1
        if not counts:
            continue
        target, n = max(counts.items(), key=lambda kv: kv[1])
        distinct_days = len({e.get("day") for e in recs if e.get("observed") == target})
        if distinct_days < STARTUP_DRIFT_MIN_DAYS:
            continue
        if time.time() - track.get(cls, 0) < STARTUP_DRIFT_COOLDOWN:
            continue
        track[cls] = time.time()
        resident_card.emit(
            f'Move "{name}" startup workspace to {target}?',
            f"{name} has landed on workspace {target} instead of its configured {configured_ws} on "
            f"{distinct_days} different days recently — looks like where you actually want it.",
            "preferences-system", "low", None,
            [{"label": f"update to workspace {target}", "cmd": f"python3 {APPLY_STARTUP_WS} {_q(cls)} {_q(target)}"}],
            "resident", "startup-drift-" + cls)


# ---------------------------------------------------------------- eco notice

ECO_NOTICE_COOLDOWN = 6 * 3600


def tick_eco_notice(state):
    """Low-key heads-up when eco mode freezes an app the user might want to
    know is paused — throttle is quiet/expected (Spotify's default policy),
    only freeze (the disruptive one) gets a card, at most once per app per
    cooldown window."""
    if not settings().get("residentEcoNotice", True):
        return
    frozen = [e for e in _load(ECO_STATE, []) if isinstance(e, dict) and e.get("level") == "freeze"]
    if not frozen:
        return
    notified = state.setdefault("eco_notified", {})
    now = time.time()
    for e in frozen:
        cls = e.get("class") or "app"
        key = "eco_" + cls
        if now - notified.get(key, 0) < ECO_NOTICE_COOLDOWN:
            continue
        notified[key] = now
        wins = e.get("wins") or []
        ws = wins[0].get("ws") if wins else None
        title = (wins[0].get("title") if wins else "") or cls
        actions = []
        if ws is not None:
            actions.append({"label": f"open workspace {ws}", "cmd": f"hyprctl dispatch workspace {ws}"})
        actions.append({"label": "thaw all", "cmd": f"python3 {ECO_DAEMON} --thaw"})
        resident_card.emit(
            f"{cls} paused by eco mode",
            f"{title} has been hidden/unfocused a while, so eco mode froze it to save CPU.",
            "weather-snow", "low", None, actions, "resident", "eco-" + cls)


# ---------------------------------------------------------------- entry points

def _music_stats():
    try:
        out = subprocess.check_output(["python3", MUSIC_STATS_PY], timeout=10, text=True)
        return json.loads(out)
    except Exception:
        return None


def _fmt_dur(secs):
    if not secs or secs <= 0:
        return "0m"
    h, m = divmod(round(secs / 60), 60)
    return (f"{h}h {m}m" if h else f"{m}m")


WRAPPED_NUDGE_COOLDOWN_WEEK = 6 * 86400
WRAPPED_NUDGE_COOLDOWN_MONTH = 27 * 86400


def _hi_res_art(url):
    return (url or "").replace("ab67616d00004851", "ab67616d00001e02")


def _wrapped_payload(stats, period_key, period):
    p = stats.get(period_key) or {}
    artists = p.get("topArtists") or []
    tracks = p.get("topTracks") or []
    top_artist = artists[0] if artists else None
    top_track = tracks[0] if tracks else None
    sp = stats.get("spotify") or {}
    large = {}
    for t in (sp.get("topTracksShort") or []) + (sp.get("topTracksLong") or []) + (sp.get("recentlyPlayed") or []):
        if t.get("artLarge"):
            large.setdefault((t.get("artist", "").lower(), t.get("title", "").lower()), t["artLarge"])
    arts = []
    for t in tracks:
        a = large.get((t.get("artist", "").lower(), t.get("title", "").lower())) or _hi_res_art(t.get("art"))
        if a and a not in arts:
            arts.append(a)
        if len(arts) == 3:
            break
    grad = ""
    lead = (top_artist[0] if top_artist else "").split(",")[0].strip().lower()
    recent = (stats.get("recentlyPlayed") or []) + (stats.get("topAllTime") or [])
    for e in recent:
        g = e.get("vibrantGrad") or e.get("grad") or ""
        if not g:
            continue
        if not grad:
            grad = g
        if lead and (e.get("artist") or "").split(",")[0].strip().lower() == lead:
            grad = g
            break
    return {
        "period": period,
        "listen": _fmt_dur(p.get("listenSeconds", 0)),
        "listenSeconds": p.get("listenSeconds", 0),
        "plays": p.get("plays", 0),
        "spanDays": p.get("spanDays", 0),
        "topArtist": top_artist[0] if top_artist else "",
        "topArtistCount": top_artist[1] if top_artist else 0,
        "topTrack": top_track.get("title", "") if top_track else "",
        "topTrackArtist": top_track.get("artist", "") if top_track else "",
        "arts": arts,
        "grad": grad,
    }


def tick_wrapped_nudge(state, force=None):
    """A periodic 'check your Wrapped' nudge — same idiom as Spotify's own
    Wrapped push notification. Emitted as a custom-kind card
    (kind="wrapped", see CARD_KINDS.md) so TopBar.qml renders it as a mini
    Wrapped hero card instead of the generic template. Weekly (once every
    ~6 days) and monthly (once every ~27 days) so it doesn't nag.
    `force` = "week" / "month" skips the cooldowns (testing).
    """
    track = state.setdefault("wrapped_nudge_track", {})
    now = time.time()
    stats = None

    due_week = force == "week" or (force is None and now - track.get("week", 0) >= WRAPPED_NUDGE_COOLDOWN_WEEK)
    due_month = force == "month" or (force is None and now - track.get("month", 0) >= WRAPPED_NUDGE_COOLDOWN_MONTH)

    for period, key, card_id, title, due in (
        ("month", "spotifyMonth", "wrapped-monthly", "Your Monthly Wrapped is ready", due_month),
        ("week", "spotifyWeek", "wrapped-weekly", "Your Weekly Wrapped is ready", due_week),
    ):
        if not due:
            continue
        stats = stats or _music_stats()
        p = stats.get(key) if stats else None
        if not p or p.get("trackedPlays", 0) <= 0:
            continue
        data = _wrapped_payload(stats, key, period)
        body = data["listen"] + " listened over the last " + str(p.get("spanDays", "?")) + "d"
        if data["topArtist"]:
            body += "\nTop artist: " + data["topArtist"]
        resident_card.emit(
            title, body, "face-smile", "low", None,
            [{"label": "Open Wrapped", "cmd": f"bash {QS_MANAGER} open guide musicstats-{period}"}],
            "resident", card_id, kind="wrapped", data=data,
        )
        track[period] = now
        if period == "month":
            track["week"] = now
        return


def _nudge_on(key):
    s = settings()
    return s.get("residentCardsEnabled", True) and s.get(key, True)


MUSIC_DIR = os.path.join(QS, "music")
NOWPLAYING_STEP = 20
NOWPLAYING_FRESH_SECS = 900


def _music_mod():
    if MUSIC_DIR not in sys.path:
        sys.path.insert(0, MUSIC_DIR)
    import music_stats
    return music_stats


def _play_counts(plays):
    counts, first, latest = {}, {}, {}
    for p in plays:
        h = p.get("hash")
        if not h or not p.get("artist"):
            continue
        counts[h] = counts.get(h, 0) + 1
        first.setdefault(h, p.get("ts", 0))
        latest[h] = p
    return counts, first, latest


def _nowplaying_payload(ms, h, count, first_ts, entry, counts):
    cache = ms.load_cache()
    lookup = {}
    snap = ms.load_spotify() or {}
    for pool in (ms.load_spotify_history(), snap.get("recentlyPlayed", []),
                 snap.get("topTracksShort", []), snap.get("topTracksLong", [])):
        for p in pool:
            if p.get("art"):
                lookup.setdefault(ms._art_key(p.get("artist", ""), p.get("title", "")), p.get("artLarge") or p["art"])
    e = ms.enrich(entry, cache, lookup)
    dur = entry.get("durationSec") or 0
    rank = 1 + sum(1 for c in counts.values() if c > count)
    return {
        "title": e["title"],
        "artist": e["artist"],
        "count": count,
        "milestone": count - count % NOWPLAYING_STEP if count >= NOWPLAYING_STEP else count,
        "rank": rank,
        "firstTs": first_ts,
        "firstStr": datetime.fromtimestamp(first_ts).strftime("%b %-d, %Y") if first_ts else "",
        "listen": _fmt_dur(dur * count),
        "listenSeconds": dur * count,
        "arts": [_hi_res_art(e["art"])] if e["art"] else [],
        "grad": e["vibrantGrad"] or e["grad"],
        "hash": h,
    }


def tick_nowplaying_milestone(state, force=False):
    if not force and not _nudge_on("residentNowPlayingEnabled"):
        return None
    ms = _music_mod()
    plays = ms.load_history()
    counts, first, latest = _play_counts(plays)
    if not counts:
        return None
    fired = state.get("np_milestones")
    if fired is None:
        state["np_milestones"] = {h: c - c % NOWPLAYING_STEP for h, c in counts.items()}
        if not force:
            return None
        fired = state["np_milestones"]
    if force:
        h = max(counts, key=lambda k: (counts[k], latest[k].get("ts", 0)))
    else:
        last = next((p for p in reversed(plays) if p.get("artist") and p.get("hash")), None)
        if not last or time.time() - last.get("ts", 0) > NOWPLAYING_FRESH_SECS:
            return None
        h = last["hash"]
        c = counts[h]
        if c < NOWPLAYING_STEP or c % NOWPLAYING_STEP != 0 or fired.get(h, 0) >= c:
            return None
    fired[h] = counts[h]
    data = _nowplaying_payload(ms, h, counts[h], first.get(h, 0), latest[h], counts)
    body = f"{data['title']} — {data['artist']}\n{data['count']} plays, {data['listen']} total"
    return resident_card.emit(
        f"{data['count']} plays of {data['title']}", body, "music", "low", 25,
        [{"label": "Open Music Stats", "cmd": f"bash {QS_MANAGER} open guide musicstats-week"}],
        "resident", "nowplaying-" + h[:10], kind="nowplaying", data=data,
    )


SCHEDULE_MANAGER = os.path.join(QS, "calendar/schedule/schedule_manager.sh")
CAL_NUDGE_LEAD = 15 * 60
CAL_NUDGE_CHECK = 60


def _timed_events():
    try:
        out = json.loads(_run(["bash", SCHEDULE_MANAGER], timeout=30) or "{}")
    except Exception:
        return []
    evs = [l for l in out.get("lessons", []) if l.get("type") == "class" and l.get("time") not in ("All day", "Task")]
    return sorted(evs, key=lambda l: l.get("start", 0))


def calendar_nudged(state, start):
    return any(k.split("|", 1)[0] == str(start) for k in state.get("calendar_nudged", {}))


def _calendar_payload(ev, nxt):
    return {
        "title": ev.get("subject", "event"),
        "start": ev.get("start", 0),
        "end": ev.get("end", 0),
        "time": ev.get("time", ""),
        "room": ev.get("room", ""),
        "calendar": ev.get("calendar", ""),
        "color": ev.get("color", ""),
        "next": nxt.get("subject", "") if nxt else "",
        "nextTime": nxt.get("time", "").split(" - ")[0] if nxt else "",
    }


def tick_calendar_nudge(state, force=False):
    if not force and not _nudge_on("residentCalendarNudgeEnabled"):
        return None
    now = time.time()
    if not force and now - state.get("calendar_nudge_check", 0) < CAL_NUDGE_CHECK:
        return None
    state["calendar_nudge_check"] = now
    nudged = state.setdefault("calendar_nudged", {})
    for k in [k for k, v in nudged.items() if now - v > 2 * 86400]:
        nudged.pop(k, None)
    evs = [e for e in _timed_events() if e.get("start", 0) > now]
    ev = None
    if force:
        ev = evs[0] if evs else {"subject": "Test event", "start": int(now + 12 * 60), "end": int(now + 72 * 60),
                                 "time": datetime.fromtimestamp(now + 720).strftime("%H:%M") + " - " +
                                         datetime.fromtimestamp(now + 4320).strftime("%H:%M"),
                                 "room": "Meeting room 2", "calendar": "Test", "color": ""}
    else:
        for e in evs:
            if e["start"] - now <= CAL_NUDGE_LEAD and not calendar_nudged(state, e["start"]):
                ev = e
                break
    if not ev:
        return None
    nudged[f"{ev['start']}|{ev.get('subject', '')}"] = now
    later = [e for e in evs if e.get("start", 0) > ev["start"]]
    data = _calendar_payload(ev, later[0] if later else None)
    mins = max(0, round((ev["start"] - now) / 60))
    body = f"{data['time']}" + (f" · {data['room']}" if data["room"] else "") + f"\nstarts in {mins} min"
    return resident_card.emit(
        data["title"], body, "calendar", "normal", int(max(60, ev["start"] - now + 60)),
        [{"label": "Open calendar", "cmd": f"bash {QS_MANAGER} open calendar"}],
        "calendar", f"cal_{ev['start']}", kind="calendar", data=data,
    )


BAT_HEALTH_COOLDOWN = 7 * 86400
BAT_HEALTH_FIRST_DELAY = 86400


def _read_sys(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def battery_health_info():
    bats = sorted(glob.glob("/sys/class/power_supply/BAT*"))
    if not bats:
        return None
    b = bats[0]
    full, design, unit = _read_sys(b + "/energy_full"), _read_sys(b + "/energy_full_design"), "Wh"
    if not full or not design:
        full, design, unit = _read_sys(b + "/charge_full"), _read_sys(b + "/charge_full_design"), "Ah"
    try:
        full, design = int(full) / 1e6, int(design) / 1e6
    except ValueError:
        return None
    if design <= 0:
        return None
    health = full / design * 100
    cycles = _read_sys(b + "/cycle_count")
    cap = _read_sys(b + "/capacity")
    limit = _read_sys(b + "/charge_control_end_threshold")
    return {
        "healthPct": round(health, 1),
        "wearPct": round(100 - health, 1),
        "full": round(full, 1),
        "design": round(design, 1),
        "unit": unit,
        "cycles": int(cycles) if cycles.isdigit() else -1,
        "capacityPct": int(cap) if cap.isdigit() else -1,
        "limitPct": int(limit) if limit.isdigit() else 100,
        "status": _read_sys(b + "/status"),
        "model": " ".join(x for x in (_read_sys(b + "/manufacturer"), _read_sys(b + "/model_name")) if x),
        "tech": _read_sys(b + "/technology"),
    }


def tick_battery_health(state, force=False):
    if not force and not _nudge_on("residentBatteryHealthEnabled"):
        return None
    now = time.time()
    track = state.setdefault("bat_health_card", {})
    if not force:
        if "last" not in track:
            track["last"] = now - BAT_HEALTH_COOLDOWN + BAT_HEALTH_FIRST_DELAY
            return None
        if now - track["last"] < BAT_HEALTH_COOLDOWN or _is_away():
            return None
    info = battery_health_info()
    if not info:
        return None
    prev = track.get("health")
    info["deltaPct"] = round(info["healthPct"] - prev, 1) if prev is not None else None
    info["prevCycles"] = track.get("cycles", -1)
    track.update({"last": now, "health": info["healthPct"], "cycles": info["cycles"]})
    body = f"{info['healthPct']}% of design capacity ({info['full']}/{info['design']} {info['unit']})"
    if info["cycles"] >= 0:
        body += f"\n{info['cycles']} charge cycles"
    return resident_card.emit(
        "Battery health check", body, "battery", "low", 30,
        [{"label": "Battery details", "cmd": f"bash {QS_MANAGER} open battery"}],
        "resident", "battery-health", kind="batteryhealth", data=info,
    )


UPTIME_TIERS = [3, 5, 7, 10, 14, 21, 30, 45, 60, 90]
UPTIME_QUIPS = {
    3: "Three days awake. Your RAM has started writing poetry.",
    5: "Five days. The kernel is getting sentimental.",
    7: "A full week up. Somewhere, a pending update weeps.",
    10: "Ten days. Even the swap file wants a nap.",
    14: "Two weeks. This is a lifestyle now.",
    21: "Three weeks. Legally this machine is nocturnal.",
    30: "A month. You are the uptime.",
}


def _boot_ts():
    for line in _read_sys("/proc/stat").splitlines():
        if line.startswith("btime "):
            return int(line.split()[1])
    return int(time.time() - float(_read_sys("/proc/uptime").split()[0]))


def _kernel_stale():
    return not os.path.isdir("/usr/lib/modules/" + os.uname().release)


def tick_uptime_guilt(state, force=False):
    if not force and not _nudge_on("residentUptimeGuiltEnabled"):
        return None
    try:
        up = float(_read_sys("/proc/uptime").split()[0])
    except (ValueError, IndexError):
        return None
    boot = _boot_ts()
    days = up / 86400
    track = state.setdefault("uptime_guilt", {})
    if abs(track.get("boot", 0) - boot) > 5:
        track.clear()
        track.update({"boot": boot, "tier": 0})
    tier = max([t for t in UPTIME_TIERS if days >= t], default=0)
    if not force:
        if tier <= track.get("tier", 0) or _is_away():
            return None
    track["tier"] = max(tier, track.get("tier", 0))
    d, rem = divmod(int(up), 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    shown_tier = tier or UPTIME_TIERS[0]
    quip = (UPTIME_QUIPS.get(shown_tier) or f"{shown_tier} days. At this point it's a pet, not a computer.") if tier \
        else "Barely broken in. The real guilt starts at 3 days."
    data = {
        "days": d, "hours": h, "minutes": m,
        "uptimeStr": f"{d}d {h}h {m}m",
        "bootTs": boot,
        "bootStr": datetime.fromtimestamp(boot).strftime("%a %b %-d, %H:%M"),
        "tier": shown_tier,
        "quip": quip,
        "kernelStale": _kernel_stale(),
    }
    body = f"Up {data['uptimeStr']} since {data['bootStr']}.\n{quip}"
    if data["kernelStale"]:
        body += "\nA newer kernel is installed and waiting."
    return resident_card.emit(
        f"{d} day{'s' if d != 1 else ''} without sleep", body, "weather-clear-night", "low", 30,
        [{"label": "Power menu", "cmd": f"bash {QS_MANAGER} open power"}],
        "resident", "uptime-guilt", kind="uptimeguilt", data=data,
    )


FOCUS_DB = os.path.join(HOME, ".local/share/focustime/focustime.db")
FOCUS_STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), "focustime_state.json")
FOCUS_SESSIONS = "/tmp/qs_focus_sessions.json"
FOCUS_IDLE_CLASSES = {"Desktop", "Locked", "Quickshell", "Unknown"}


def _focus_breakdown(start, end):
    import sqlite3
    from collections import defaultdict
    per = defaultdict(int)
    try:
        conn = sqlite3.connect(f"file:{FOCUS_DB}?mode=ro", uri=True, timeout=2)
        spans = defaultdict(list)
        t = int(start) - int(start) % 60
        while t < end:
            dt = datetime.fromtimestamp(t)
            spans[dt.strftime("%Y-%m-%d")].append(dt.hour * 60 + dt.minute)
            t += 60
        for day, mins in spans.items():
            for cls, secs in conn.execute(
                    "SELECT app_class, SUM(seconds) FROM focus_minutes WHERE log_date=? AND minute_idx BETWEEN ? AND ? GROUP BY app_class",
                    (day, min(mins), max(mins))):
                per[cls] += secs
        conn.close()
    except Exception:
        return [], 0
    names = {a.get("class"): a for a in _load(FOCUS_STATE, {}).get("apps", [])}
    total = sum(per.values())
    apps = []
    for cls, secs in sorted(per.items(), key=lambda kv: -kv[1]):
        if cls in FOCUS_IDLE_CLASSES:
            continue
        a = names.get(cls, {})
        apps.append({"name": a.get("name") or cls, "icon": a.get("icon", ""), "secs": secs,
                     "pct": round(secs / total * 100, 1) if total else 0})
    return apps[:4], total


def focus_done(duration, end_ts=None, force=False):
    end_ts = end_ts or time.time()
    s = settings()
    label = _fmt_dur(duration)
    if not s.get("residentCardsEnabled", True):
        return None
    if not force and not s.get("residentFocusDoneEnabled", True):
        return resident_card.emit("Timer done", f"{label} elapsed", "timer", "normal", 10, [], "timer",
                                  f"timer_{int(end_ts)}")
    start = end_ts - duration
    apps, tracked = _focus_breakdown(start, end_ts)
    today = datetime.fromtimestamp(end_ts).strftime("%Y-%m-%d")
    sess = [x for x in _load(FOCUS_SESSIONS, []) if x.get("day") == today and abs(x.get("end", 0) - end_ts) > 5]
    sess.append({"day": today, "end": int(end_ts), "secs": int(duration)})
    if not force:
        _save(FOCUS_SESSIONS, sess)
    fs = _load(FOCUS_STATE, {})
    data = {
        "durationSecs": int(duration),
        "label": label,
        "startTs": int(start),
        "endTs": int(end_ts),
        "apps": apps,
        "trackedSecs": tracked,
        "sessionsToday": len(sess),
        "focusToday": _fmt_dur(sum(x.get("secs", 0) for x in sess)),
        "screenToday": _fmt_dur(fs.get("total", 0)),
    }
    top = apps[0] if apps else None
    body = f"{label} session complete" + (f"\nmostly {top['name']} ({round(top['pct'])}%)" if top else "")
    return resident_card.emit(
        "Focus session done", body, "timer", "normal", 45,
        [{"label": "Start another", "cmd": "printf start > /tmp/qs_timer_cmd"}],
        "timer", f"timer_{int(end_ts)}", kind="focusdone", data=data,
    )


def tick_mira_mail(state):
    """New-mail notification — a normal notify-send (swaync), separate from
    the reauth resident card in find_fixes(). Fires only on an actual
    increase in unread count since the last tick, never on every poll."""
    d = _read_mira_unread()
    if not d or d.get("error"):
        return
    unread = d.get("unread")
    if unread is None:
        return
    last = state.get("mira_last_unread")
    state["mira_last_unread"] = unread
    if last is None:
        return  # first observation — don't fire on daemon startup
    delta = unread - last
    if delta <= 0:
        return
    body = f"{delta} new message" + ("s" if delta != 1 else "")
    try:
        subprocess.run(["notify-send", "-a", "Mira", "-u", "normal", "-i", "mail-unread",
                        "New mail", body], timeout=5, check=False)
    except Exception:
        pass


TAILSCALE_WARN_DAYS = 14
# The REUSABLE AUTH KEY's own expiry (shown only in the admin console UI —
# Tailscale doesn't expose this via `tailscale status`/CLI at all, only a
# per-device *session* KeyExpiry, which is a different, longer-lived number
# and not what the user actually wants tracked here). Confirmed by the user
# 2026-09-30 via the admin console screenshot: "This key will expire on Dec
# 29, 2026." Update this constant if/when a new key is generated.
TAILSCALE_AUTHKEY_EXPIRY = "2026-12-29"


def _tailscale_devices():
    """Self + all peers, real names via DNSName (HostName can be a generic
    'localhost' on some clients, e.g. the Android peer seen this session)."""
    try:
        out = _run(["tailscale", "status", "--json"])
        d = json.loads(out)
        devices = []
        self_ = d.get("Self", {})
        devices.append({
            "name": (self_.get("DNSName") or self_.get("HostName") or "?").split(".")[0],
            "online": True, "self": True,
        })
        for p in (d.get("Peer") or {}).values():
            devices.append({
                "name": (p.get("DNSName") or p.get("HostName") or "?").split(".")[0],
                "online": bool(p.get("Online")), "self": False,
                "lastSeen": (p.get("LastSeen") or "")[:10],
            })
        return devices
    except Exception:
        return []


def tick_tailscale_key(state, force=False):
    """Auth-key expiry nudge — user explicitly wants this hard to miss (they
    manually re-key every ~90 days and want to catch every device on the
    tailnet before it lapses, not just this laptop), so unlike most cards
    this is high urgency + infinite hold (0) starting inside the warn
    window, and re-emits with the same card_id daily so an accidental
    dismiss doesn't lose it for long. See CARD_KINDS.md for the 'tailscale'
    kind shape."""
    from datetime import datetime, timezone
    exp = datetime.strptime(TAILSCALE_AUTHKEY_EXPIRY, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    days_left = (exp - now).total_seconds() / 86400
    if days_left > TAILSCALE_WARN_DAYS and not force:
        return
    last = state.get("tailscale_nudge_day")
    today = now.strftime("%Y-%m-%d")
    if last == today and not force:
        return
    state["tailscale_nudge_day"] = today
    urgency = "high" if days_left <= 3 else "normal"
    devices = _tailscale_devices()
    data = {"daysLeft": round(max(0, days_left)), "expiry": TAILSCALE_AUTHKEY_EXPIRY, "devices": devices}
    stale = [dv["name"] for dv in devices if not dv["online"] and not dv.get("self")]
    body = f"{data['daysLeft']}d left ({data['expiry']}) — re-auth every device on the tailnet before then."
    if stale:
        body += "\nStill offline: " + ", ".join(stale)
    resident_card.emit(
        "Tailscale key expiring",
        body,
        "network-vpn", urgency, 0,
        [{"label": "Open admin console", "cmd": "xdg-open https://login.tailscale.com/admin/machines"}],
        "resident", "tailscale-key-expiry", kind="tailscale", data=data,
    )


FLEET_FILE = "/tmp/qs_fleet.json"
FLEET_FRESH_SECS = 600
FLEET_WINDOWS_IDLE_DAYS = 3
FLEET_VPS_DISK_PCT = 90
FLEET_VPS_DISK_PCT_SEVERE = 95
BASECAMP_URL = "https://basecamp.czeddaru.dev"


def _fleet():
    """None unless the hub answered recently — never nag off a frozen snapshot
    (tailnet down, watcher dead), the ages in it keep counting regardless."""
    d = _load(FLEET_FILE, {})
    if not isinstance(d, dict) or time.time() - (d.get("last_ok") or 0) > FLEET_FRESH_SECS:
        return None
    return d


def _fleet_device(d, *names, os_hint=None):
    devs = d.get("devices") or []
    for dv in devs:
        if (dv.get("name") or "").lower() in names:
            return dv
    for dv in devs if os_hint else []:
        if os_hint in (dv.get("os") or "").lower():
            return dv
    return None


def _show_fleet_action():
    cmd = ("python3 -c " + _q("import sys; sys.path.insert(0, " + repr(HERE) + "); import resident_card; "
                              "resident_card.pill_flag('fleet', open_card=True, ttl_secs=20)"))
    return {"label": "Show fleet", "cmd": cmd}


def _daily_gate(state, key, sig, force):
    today = datetime.now().strftime("%Y-%m-%d")
    if not force and state.get(key) == [today, sig]:
        return False
    state[key] = [today, sig]
    return True


def tick_fleet_windows_idle(state, force=False):
    if not force and not _nudge_on("residentFleetNudges"):
        return None
    d = _fleet()
    dv = _fleet_device(d, "windows", os_hint="windows") if d else None
    if not dv or dv.get("state") == "offline":
        state.pop("fleet_windows_idle_day", None)
        return None
    days = (dv.get("idle_s") or 0) / 86400
    if days < FLEET_WINDOWS_IDLE_DAYS and not force:
        state.pop("fleet_windows_idle_day", None)
        return None
    if not _daily_gate(state, "fleet_windows_idle_day", "idle", force):
        return None
    body = f"No input for {days:.0f} days but it's still reporting in."
    if dv.get("foreground"):
        body += f"\nForeground: {dv['foreground']}"
    resident_card.pill_flag("fleet", urgency="low")
    return resident_card.emit(
        f"Windows PC idle {days:.0f}d: still on?", body, "computer", "low", None,
        [{"label": "Open basecamp", "cmd": "xdg-open " + BASECAMP_URL}, _show_fleet_action()],
        "resident", "fleet-windows-idle",
    )


def tick_fleet_vps_disk(state, force=False):
    if not force and not _nudge_on("residentFleetNudges"):
        return None
    d = _fleet()
    dv = _fleet_device(d, "vps", "basecamp") if d else None
    pct = (dv or {}).get("disk_pct")
    if pct is None or (pct < FLEET_VPS_DISK_PCT and not force):
        state.pop("fleet_vps_disk_day", None)
        return None
    severe = pct >= FLEET_VPS_DISK_PCT_SEVERE
    if not _daily_gate(state, "fleet_vps_disk_day", "severe" if severe else "warn", force):
        return None
    worst = max(dv.get("disks") or [{}], key=lambda x: x.get("used_pct") or 0)
    body = f"{worst.get('drive') or 'disk'} at {pct:.0f}%"
    if worst.get("free_gb") is not None:
        body += f", {worst['free_gb']:.1f} GB free"
    resident_card.pill_flag("fleet", urgency="high" if severe else "normal")
    return resident_card.emit(
        f"VPS disk {pct:.0f}%", body, "drive-harddisk", "high" if severe else "normal", 0 if severe else None,
        [{"label": "Open Portainer", "cmd": "xdg-open https://portainer.basecamp.czeddaru.dev"}, _show_fleet_action()],
        "resident", "fleet-vps-disk",
    )


def tick_fleet_containers(state, force=False):
    """Only containers seen up at least once count as 'known' — a stopped
    one-off or a never-started service shouldn't page anyone."""
    if not force and not _nudge_on("residentFleetNudges"):
        return None
    d = _fleet()
    if not d:
        return None
    known = set(state.get("fleet_known_ctrs") or [])
    down = []
    for dv in d.get("devices") or []:
        if dv.get("state") == "offline":
            continue
        for c in dv.get("containers") or []:
            key = f"{dv.get('name')}/{c.get('name')}"
            if c.get("up"):
                known.add(key)
            elif key in known or force:
                down.append(key)
    state["fleet_known_ctrs"] = sorted(known)[-200:]
    if not down:
        state.pop("fleet_ctr_day", None)
        return None
    down.sort()
    if not _daily_gate(state, "fleet_ctr_day", ",".join(down), force):
        return None
    names = [k.split("/", 1)[1] for k in down]
    title = f"{names[0]} container down" if len(names) == 1 else f"{len(names)} containers down"
    resident_card.pill_flag("fleet", urgency="high", style="border")
    return resident_card.emit(
        title, "\n".join("• " + k for k in down), "dialog-warning", "high", 0,
        [{"label": "Open Portainer", "cmd": "xdg-open https://portainer.basecamp.czeddaru.dev"}, _show_fleet_action()],
        "resident", "fleet-containers",
    )


def tick(ctx, state):
    try:
        tick_catchup(ctx, state)
    except Exception:
        pass
    try:
        tick_fixes(state)
    except Exception:
        pass
    try:
        tick_low_battery(state)
    except Exception:
        pass
    try:
        tick_eco_notice(state)
    except Exception:
        pass
    try:
        tick_layout_suggest(state)
    except Exception:
        pass
    try:
        tick_startup_drift(state)
    except Exception:
        pass
    try:
        tick_wrapped_nudge(state)
    except Exception:
        pass
    try:
        tick_day_briefs(ctx, state)
    except Exception:
        pass
    for fn in (tick_nowplaying_milestone, tick_calendar_nudge, tick_battery_health, tick_uptime_guilt):
        try:
            fn(state)
        except Exception:
            pass
    try:
        tick_mira_mail(state)
    except Exception:
        pass
    try:
        tick_tailscale_key(state)
    except Exception:
        pass
    for fn in (tick_fleet_windows_idle, tick_fleet_vps_disk, tick_fleet_containers):
        try:
            fn(state)
        except Exception:
            pass


def main():
    args = sys.argv[1:]
    ctx = _load("/tmp/qs_context.json", {})
    state = {}
    if "--test-brief" in args:
        print(json.dumps(run_morning_brief(ctx, state, force=True, dry=True), ensure_ascii=False))
    elif "--test-catchup" in args:
        away = {"start": int(time.time()) - 1800, "uid": max(0, _max_uid() - 3), "battery": 90}
        brief = build_catchup(ctx, away)
        _save(LOCK_BRIEF, brief)
        card = resident_card.emit("While you were away", brief["headline"] + "\n" + "\n".join("• " + i for i in brief["items"]),
                                  "history", "low", None, [], "resident", "catchup-test")
        print(json.dumps({"brief": brief, "card": card}, ensure_ascii=False, indent=1))
    elif "--test-fixes" in args:
        for c in tick_fixes(state, force=True, dry=True):
            print(json.dumps(c, ensure_ascii=False))
    elif "--test-low-battery" in args:
        info = _battery_info()
        print(json.dumps({"info": info, "applied": _low_battery_applied()}, ensure_ascii=False))
        card = tick_low_battery(state, force=True, dry=True)
        print(json.dumps(card, ensure_ascii=False) if card else "no card (not discharging / above threshold / throttled)")
    elif "--test-wrapped" in args:
        i = args.index("--test-wrapped")
        which = args[i + 1] if i + 1 < len(args) and args[i + 1] in ("week", "month") else "week"
        tick_wrapped_nudge(state, force=which)
        print("emitted wrapped-" + ("monthly" if which == "month" else "weekly"))
    elif "--test-brief-card" in args:
        i = args.index("--test-brief-card")
        which = args[i + 1] if i + 1 < len(args) and args[i + 1] in BRIEF_CFG else "morning"
        print(json.dumps(run_brief(which, ctx, state, force=True, dry=True), ensure_ascii=False))
    elif "--test-nowplaying" in args:
        print(json.dumps(tick_nowplaying_milestone(state, force=True), ensure_ascii=False))
    elif "--test-calendar" in args:
        print(json.dumps(tick_calendar_nudge(state, force=True), ensure_ascii=False))
    elif "--test-batteryhealth" in args:
        print(json.dumps(tick_battery_health(state, force=True), ensure_ascii=False))
    elif "--test-uptimeguilt" in args:
        print(json.dumps(tick_uptime_guilt(state, force=True), ensure_ascii=False))
    elif "--test-fleet" in args:
        for fn in (tick_fleet_windows_idle, tick_fleet_vps_disk, tick_fleet_containers):
            print(fn.__name__, json.dumps(fn(state, force=True), ensure_ascii=False))
    elif "--test-focusdone" in args:
        i = args.index("--test-focusdone")
        mins = float(args[i + 1]) if i + 1 < len(args) and args[i + 1].replace(".", "", 1).isdigit() else 25
        print(json.dumps(focus_done(mins * 60, time.time(), force=True), ensure_ascii=False))
    elif "--focus-done" in args:
        i = args.index("--focus-done")
        dur = float(args[i + 1]) if i + 1 < len(args) else 0
        end = float(args[i + 2]) if i + 2 < len(args) else time.time()
        focus_done(dur, end / 1000 if end > 1e11 else end)
    elif "--test-layout" in args:
        log = _load(SMARTWS_RESTORE_LOG, [])
        print(f"{len(log)} restore_log entries")
        tick_layout_suggest(state)
    elif "--test-startup-drift" in args:
        tick_startup_drift(state)
        print(json.dumps(_load(STARTUP_DRIFT_LOG, []), ensure_ascii=False, indent=1))
    elif "--list-muted" in args:
        tr = _load(STATE_FILE, {}).get("fix_track", {})
        muted = {k: v for k, v in tr.items() if v.get("muted")}
        if not muted:
            print("no muted categories")
        for k, v in muted.items():
            days = (time.time() - v.get("muted_ts", 0)) / 86400
            print(f"{k}: muted {days:.1f}d ago ({len(v.get('dismiss_ts', []))} dismissals tracked)")
    elif "--unmute" in args:
        idx = args.index("--unmute")
        cat = args[idx + 1] if idx + 1 < len(args) else ""
        if not cat:
            print("usage: resident_extras.py --unmute <category>")
        else:
            st = _load(STATE_FILE, {})
            tr = st.setdefault("fix_track", {})
            if cat in tr:
                tr[cat]["muted"] = False
                tr[cat]["dismiss_ts"] = []
                _save(STATE_FILE, st)
                print(f"unmuted {cat}")
            else:
                print(f"no tracked state for {cat!r} — check --list-muted for valid category keys")
    elif "--stats" in args:
        print(json.dumps(stats_summary(), ensure_ascii=False))
    else:
        print("usage: resident_extras.py --test-brief | --test-catchup | --test-fixes | "
              "--test-low-battery | --test-layout | --test-startup-drift | --test-nowplaying | --test-calendar | "
              "--test-batteryhealth | --test-uptimeguilt | --test-fleet | --test-focusdone [mins] | "
              "--test-brief-card morning|afternoon|night | --list-muted | "
              "--unmute <category> | --stats")


if __name__ == "__main__":
    main()
