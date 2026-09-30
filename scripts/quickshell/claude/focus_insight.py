#!/usr/bin/env python3
"""Watches /tmp/qs_active_widget; when it becomes 'focustime', pulls today's
focus stats and writes a one-line Claude insight to /tmp/qs_focus_insight.
Also runs two lightweight background threads:
 - deep-work-guard (#5): nudges back to work when you drift into a
   distraction app after a sustained productive streak.
 - focus-soundtrack (#11): suggests a vibe when you open focustime with
   nothing playing (opt-in via settings.musicSuggest)."""
import os, sys, json, subprocess, time, threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import resident_card
except Exception:
    resident_card = None

try:
    from claude_say import say as _say
    def say(prompt: str) -> str: return _say(prompt)
except Exception:
    def say(prompt: str) -> str: return ""

try:
    from claude_resident import load, save, notify, settings as resident_settings, SUGGEST
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

    def resident_settings():
        return load(os.path.expanduser("~/.config/hypr/settings.json"), {})

    SUGGEST = "/tmp/qs_resident_suggestion"

QS   = os.path.join(os.path.expanduser("~"), ".config/hypr/scripts/quickshell")
ACTIVE  = "/tmp/qs_active_widget"
INSIGHT = "/tmp/qs_focus_insight"
GOAL_F  = "/tmp/qs_focus_goal"
STATS   = os.path.join(QS, "focustime/get_stats.py")
CTX     = "/tmp/qs_context.json"
MUSIC_INFO = "/tmp/music_info.json"
COOLDOWN = 120

DISTRACTION_APPS = {"discord", "vesktop", "steam", "lutris", "heroic", "org.gnome.steam",
                     "steamwebhelper"}
DISTRACTION_TITLE_HINTS = ("youtube", "netflix", "twitch.tv", "reddit.com")
GUARD_POLL = 20
GUARD_STREAK_SAMPLES = 30   # 30 * 20s = 10 min of productive time before a switch counts
GUARD_COOLDOWN = 600

_last_written = 0


def get_stats():
    try:
        r = subprocess.run(["python3", STATS, "today"], capture_output=True, text=True, timeout=8)
        return json.loads(r.stdout) if r.returncode == 0 else {}
    except Exception:
        return {}


def read_goal():
    try:
        return int(open(GOAL_F).read().strip())
    except Exception:
        return 240


def write_insight(text):
    try:
        with open(INSIGHT, "w") as f:
            f.write(text.strip())
    except OSError:
        pass


def build_insight():
    global _last_written
    now = time.time()
    if now - _last_written < COOLDOWN:
        return
    _last_written = now

    stats = get_stats()
    goal  = read_goal()

    total_s = stats.get("total_seconds", 0) if isinstance(stats, dict) else 0
    total_m = total_s // 60
    apps    = stats.get("apps", []) if isinstance(stats, dict) else []
    top     = apps[0].get("name", apps[0].get("app", "")) if apps else "nothing yet"

    prompt = (
        f"Today: {total_m} min focused (goal {goal} min), top app: {top}. "
        f"Write ONE short sentence coaching me on my focus progress. "
        f"Warm, direct, under 15 words. No greeting."
    )
    out = say(prompt)
    if out:
        write_insight(out)

    maybe_suggest_soundtrack(stats)


def watch():
    open(ACTIVE, "a").close()
    proc = subprocess.Popen(
        ["inotifywait", "-m", "-e", "close_write,create,moved_to", ACTIVE],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
    )
    if proc.stdout is None:
        return
    for _ in proc.stdout:
        try:
            widget = open(ACTIVE).read().strip()
        except OSError:
            continue
        if widget == "focustime":
            build_insight()


# ---- #11 focus-soundtrack ─────────────────────────────────────────────────
# Off by default (settings.musicSuggest) — only fires when the user opens
# focustime, nothing is currently playing, and they've opted in.

_last_soundtrack = 0


def maybe_suggest_soundtrack(stats):
    global _last_soundtrack
    if not resident_settings().get("musicSuggest", False):
        return
    now = time.time()
    if now - _last_soundtrack < COOLDOWN:
        return
    m = load(MUSIC_INFO, {})
    if m.get("status") == "Playing":
        return
    apps = stats.get("apps", []) if isinstance(stats, dict) else []
    top = apps[0].get("name", apps[0].get("app", "")) if apps else "nothing yet"
    hour = time.localtime().tm_hour
    tod = "late night" if hour >= 23 or hour < 5 else \
          "early morning" if hour < 9 else "morning" if hour < 12 else \
          "afternoon" if hour < 17 else "evening"
    out = say(f"It's {tod}, about to focus with top app '{top}', nothing playing right now. "
              f"Suggest ONE short music vibe/genre for this focus session. Under 12 words, "
              f"no greeting, no track names, just a vibe suggestion.")
    if not out:
        return
    _last_soundtrack = now
    if resident_card is not None:
        resident_card.emit("Claude", out, "emblem-music-symbolic", "low", None,
                           [{"label": "play", "cmd": "playerctl play"}], "resident",
                           "focus-soundtrack-" + str(int(now)))
    else:
        notify("Claude", out, "low")
    save(SUGGEST, {"key": "focus_soundtrack", "msg": out, "urgency": "low",
                   "ts": int(now), "action_label": "play", "action_cmd": "playerctl play",
                   "label": "vibe"})


# ---- #5 deep-work-guard ────────────────────────────────────────────────────
# Tracks a rolling window of (app, is_distraction) samples from the shared
# context file. When a sustained productive streak is broken by switching
# into a known distraction app, fires one gentle nudge with a "back to work"
# hyprctl dispatch, gated by a 600s cooldown so it never nags.

_last_guard_nudge = 0
_last_productive_class = ""


def _is_distraction(app, title):
    app_l = (app or "").lower()
    title_l = (title or "").lower()
    if app_l in DISTRACTION_APPS:
        return True
    return any(hint in title_l for hint in DISTRACTION_TITLE_HINTS)


def deep_work_guard():
    global _last_guard_nudge, _last_productive_class
    streak = 0
    while True:
        time.sleep(GUARD_POLL)
        ctx = load(CTX, {})
        focus = ctx.get("focus", {}) if isinstance(ctx, dict) else {}
        app, title = focus.get("app", ""), focus.get("title", "")
        if not app or app in ("Locked", "Desktop", "Unknown"):
            continue
        if _is_distraction(app, title):
            now = time.time()
            if streak >= GUARD_STREAK_SAMPLES and now - _last_guard_nudge >= GUARD_COOLDOWN:
                _last_guard_nudge = now
                mins = streak * GUARD_POLL // 60
                out = say(f"I was heads-down for about {mins} minutes and just switched to "
                          f"{app}. Give me ONE short, gentle nudge back to work — under 15 "
                          f"words, no guilt-tripping, warm and light.")
                msg = out.strip() if out else f"drifted into {app} after a good streak — back to it?"
                dispatch = (f"hyprctl dispatch focuswindow class:^{_last_productive_class}$"
                            if _last_productive_class else f"echo no-op")
                if resident_card is not None:
                    resident_card.emit("Claude", msg, "chronometer", "low", None,
                                       [{"label": "back to work", "cmd": dispatch}], "resident",
                                       "deep-work-guard-" + str(int(now)))
                else:
                    notify("Claude", msg, "low")
                save(SUGGEST, {"key": "deep_work_guard", "msg": msg, "urgency": "low",
                               "ts": int(now), "action_label": "back to work",
                               "action_cmd": dispatch, "label": "focus"})
            streak = 0
        else:
            streak += 1
            _last_productive_class = app


if __name__ == "__main__":
    threading.Thread(target=deep_work_guard, daemon=True).start()
    watch()
