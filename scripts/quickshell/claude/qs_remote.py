#!/usr/bin/env python3
"""qs-remote: the phone's way into the laptop.

Listens on 127.0.0.1 only; `tailscale serve` puts HTTPS in front of it and
adds the caller's Tailscale identity. Every request needs the bearer token
AND a Tailscale identity header (tagged nodes like the VPS or the Windows box
get none), and the whole thing can be switched off live with the
`qsRemoteEnabled` setting. Only the allowlisted actions below exist; nothing
takes a free-form command.

The touchpad and keyboard (qs_remote_input.py, a WebSocket at /api/v1/input)
are the one exception by nature: typing is typing. They have their own switch,
`qsRemoteInputEnabled`, and keybinds run only by id from the laptop's own list.

  python3 qs_remote.py          run the server (exec.conf does this)
  python3 qs_remote.py pair     print the setup link for the Fleet app
"""
import base64
import fcntl
import hashlib
import hmac
import importlib.util
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.request
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from html import escape as _esc
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, urlsplit

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)

HOME = os.path.expanduser("~")
HOST = "127.0.0.1"
PORT = 8790
LOCK = "/tmp/qs_remote.lock"
STATE_DIR = os.path.join(HOME, ".local/state/qs-remote")
TOKEN_FILE = os.path.join(STATE_DIR, "token")
AUDIT = os.path.join(STATE_DIR, "audit.jsonl")
AUDIT_MAX = 2 * 1024 * 1024
SETTINGS = os.path.join(HOME, ".config/hypr/settings.json")
FLEET_TOKENS = os.path.join(HOME, ".local/state/fleet/tokens.env")
LOCK_SH = os.path.join(HOME, ".config/hypr/scripts/lock.sh")
ART_ROOTS = (os.path.join(HOME, ".cache"), "/tmp")
ART_SETTLE = 1.5  # music_info.sh curls the cover straight into place
ART_MAX = 5 * 1024 * 1024
MAX_BODY = 4096
ANSWER_MAX = 8 * 1024 * 1024
# Requests per minute per tailnet login. Sliders stream while dragging (about
# one request per round trip), so they get their own, much larger bucket.
LIMITS = {"read": 240, "act": 60, "live": 900, "answer": 20}
LIVE = {"volume", "brightness"}
WALL_RE = re.compile(r"^(random|[A-Za-z0-9][A-Za-z0-9._ -]{0,120}\.(jpe?g|png|webp))$", re.I)
HEX_RE = re.compile(r"#[0-9a-fA-F]{6}")
COOKIE = "qsr"

spec = importlib.util.spec_from_file_location("qs_mcp", os.path.join(BASE, "qs_mcp.py"))
qs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qs)
import resident_card  # noqa: E402
import qs_remote_input as remote_input  # noqa: E402


def log(*a):
    print("[qs-remote]", *a, file=sys.stderr, flush=True)


def load_token():
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    if not os.path.exists(TOKEN_FILE):
        fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(secrets.token_urlsafe(32) + "\n")
    with open(TOKEN_FILE) as f:
        return f.read().strip()


_settings_cache = {"mtime": None, "data": {}}


def settings():
    try:
        m = os.path.getmtime(SETTINGS)
        if m != _settings_cache["mtime"]:
            with open(SETTINGS) as f:
                _settings_cache["data"] = json.load(f)
            _settings_cache["mtime"] = m
    except (OSError, ValueError):
        pass
    return _settings_cache["data"]


def _run(cmd, timeout=3):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _int(v, default=None):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


# ---------------------------------------------------------------- state

MUSIC_HOLD = 60
MUSIC_STOP_GRACE = 5
_music_last = {"track": None, "ts": 0.0}
_music_mu = threading.Lock()


def _music():
    try:
        m = qs.t_music({})
    except Exception:
        m = None
    fresh = _music_read(m) if isinstance(m, dict) and m.get("status") else None
    now = time.time()
    with _music_mu:
        last, age = _music_last["track"], now - _music_last["ts"]
        if fresh and fresh["status"] != "stopped":
            _music_last.update(track=fresh, ts=now)
            return fresh
        held = last is not None and age < (MUSIC_STOP_GRACE if fresh else MUSIC_HOLD)
        if held:
            return dict(last)
        _music_last.update(track=None, ts=now)
    return fresh or _music_read({})


def _music_read(m):
    art = m.get("artUrl") or ""
    status = (m.get("status") or "Stopped").lower()
    return {
        "title": m.get("title") or "",
        "artist": m.get("artist") or "",
        "status": status if status in ("playing", "paused") else "stopped",
        "position": _int(m.get("position"), 0),
        "length": _int(m.get("length"), 0),
        "source": m.get("source") or "",
        "colors": HEX_RE.findall(m.get("vibrantGrad") or m.get("grad") or "")[:3],
        "art": _art_id(art),
        "bpm": _int(m.get("bpm"), 0),
    }


def _art_path(path):
    """The current cover, only if it is a small image file under a cache dir."""
    if not path:
        return None
    path = path[7:] if path.startswith("file://") else path
    real = os.path.realpath(path)
    if not any(real.startswith(os.path.realpath(r) + os.sep) for r in ART_ROOTS):
        return None
    if not re.search(r"\.(jpe?g|png|webp)$", real, re.I):
        return None
    try:
        st = os.stat(real)
        if not os.path.isfile(real) or not 0 < st.st_size <= ART_MAX or time.time() - st.st_mtime < ART_SETTLE:
            return None
        with open(real, "rb") as f:
            head = f.read(12)
            f.seek(-2, os.SEEK_END)
            tail = f.read(2)
    except OSError:
        return None
    # Only a whole file: a JPEG that ends in EOI, a PNG or WebP with its header.
    if head[:2] == b"\xff\xd8" and tail != b"\xff\xd9":
        return None
    if head[:2] != b"\xff\xd8" and not head.startswith(b"\x89PNG") and head[8:12] != b"WEBP":
        return None
    return real


def _art_id(path):
    """Changes whenever the file does, so the app refetches a re-downloaded cover."""
    real = _art_path(path)
    if not real:
        return ""
    st = os.stat(real)
    return hashlib.sha1(f"{real}:{st.st_size}:{int(st.st_mtime)}".encode()).hexdigest()[:12]


def _sysinfo():
    try:
        return (qs.t_system({}) or {}).get("system") or {}
    except Exception:
        return {}


def _night():
    try:
        return bool(qs.t_night_light({"action": "status"}).get("on"))
    except Exception:
        return False


def _json_run(cmd):
    try:
        return json.loads(_run(cmd) or "null")
    except ValueError:
        return None


def _workspaces():
    active = _json_run(["hyprctl", "activeworkspace", "-j"]) or {}
    spaces = _json_run(["hyprctl", "workspaces", "-j"]) or []
    ids = sorted({w.get("id") for w in spaces if isinstance(w, dict) and isinstance(w.get("id"), int) and w.get("id") > 0})
    return {"active": _int(active.get("id"), 0) if isinstance(active, dict) else 0, "occupied": ids}


def _kb_layout():
    d = _json_run(["hyprctl", "devices", "-j"]) or {}
    kbs = d.get("keyboards", []) if isinstance(d, dict) else []
    main = next((k for k in kbs if k.get("main")), kbs[0] if kbs else {})
    return str(main.get("active_keymap") or "")


def _bluetooth_on():
    return "Powered: yes" in _run(["bluetoothctl", "show"])


# Every probe is a subprocess; run them side by side so a poll costs the
# slowest one, not the sum (sequentially it ran long enough for the phone
# to give up on the request).
_POOL = ThreadPoolExecutor(max_workers=8, thread_name_prefix="snap")


def snapshot():
    jobs = {
        "sys": _POOL.submit(_sysinfo),
        "bright": _POOL.submit(_run, ["brightnessctl", "-m"]),
        "profile": _POOL.submit(_run, ["powerprofilesctl", "get"]),
        "night": _POOL.submit(_night),
        "vol": _POOL.submit(_run, ["pamixer", "--get-volume"]),
        "mute": _POOL.submit(_run, ["pamixer", "--get-mute"]),
        "mic": _POOL.submit(_run, ["pamixer", "--default-source", "--get-mute"]),
        "music": _POOL.submit(_music),
        "wifi_radio": _POOL.submit(_run, ["nmcli", "radio", "wifi"]),
        "bt": _POOL.submit(_bluetooth_on),
        "dnd": _POOL.submit(_run, ["swaync-client", "-D"]),
        "idle": _POOL.submit(_run, ["pgrep", "-x", "hypridle"]),
        "ws": _POOL.submit(_workspaces),
        "kb": _POOL.submit(_kb_layout),
    }
    r = {k: f.result() for k, f in jobs.items()}
    sysinfo = r["sys"]
    bat = sysinfo.get("battery") or {}
    wifi = sysinfo.get("wifi") or {}
    bright = r["bright"].split(",")
    profile = r["profile"]
    night = r["night"]
    return {
        "host": os.uname().nodename,
        "ts": int(time.time()),
        "audio": {
            "volume": _int(r["vol"], 0),
            "muted": r["mute"] == "true",
            "mic_muted": r["mic"] == "true",
        },
        "screen": {
            "brightness": _int(bright[3].rstrip("%"), None) if len(bright) > 3 else None,
            "night_light": night,
        },
        "power": {
            "profile": {"power-saver": "saver"}.get(profile, profile or "balanced"),
            "battery": _int(bat.get("percent")),
            "charging": str(bat.get("status", "")).lower() in ("charging", "full"),
        },
        "network": {"ssid": wifi.get("ssid") or "", "online": str(wifi.get("status", "")).lower() not in ("off", "disconnected", "")},
        "music": r["music"],
        "toggles": {
            "wifi": r["wifi_radio"] == "enabled",
            "bluetooth": r["bt"],
            "dnd": r["dnd"] == "true",
            # hypridle not running = the laptop stays awake.
            "caffeine": not r["idle"],
        },
        "workspace": r["ws"],
        "keyboard": {"layout": r["kb"]},
        "input": settings().get("qsRemoteInputEnabled", True) is not False,
    }


# ---------------------------------------------------------------- actions
# Each takes the parsed JSON body and returns {"ok": bool, ...}. Output from
# the underlying commands is never sent back; only ok/error.

def _ok(r):
    return {"ok": bool(r.get("ok", True)) if isinstance(r, dict) else True}


def a_media(args):
    action = str(args.get("action", "play-pause"))
    if action not in ("play-pause", "next", "previous"):
        return {"ok": False, "error": "action must be play-pause, next or previous"}
    return _ok(qs.t_media_control({"action": action}))


def a_volume(args):
    pct = _int(args.get("percent"))
    if pct is None:
        return {"ok": False, "error": "percent (0-100) required"}
    return _ok(qs.t_set_volume({"percent": max(0, min(100, pct))}))


def a_mute(args):
    if "muted" not in args:
        return _ok(qs.t_toggle_mute({}))
    r = qs._sh(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if args.get("muted") else "0"])
    qs._volume_osd_sync()
    return _ok(r)


def a_mic(args):
    return _ok(qs.t_mic_mute({"muted": bool(args.get("muted", True))}))


def a_brightness(args):
    pct = _int(args.get("percent"))
    if pct is None:
        return {"ok": False, "error": "percent (1-100) required"}
    return _ok(qs.t_set_brightness({"value": f"{max(1, min(100, pct))}%"}))


def a_night_light(args):
    return _ok(qs.t_night_light({"action": "on" if args.get("on") else "off"}))


def a_power_profile(args):
    p = {"saver": "power-saver", "performance": "performance", "balanced": "balanced",
         "power-saver": "power-saver"}.get(str(args.get("profile", "")))
    if not p:
        return {"ok": False, "error": "profile must be saver, balanced or performance"}
    return _ok(qs.t_power_profile({"profile": p}))


def a_wallpaper(args):
    name = str(args.get("name", "random"))[:130]
    if not WALL_RE.match(name) or ".." in name:
        return {"ok": False, "error": "name must be 'random' or a plain image filename"}
    return _ok(qs.t_set_wallpaper({"name": name}))


def a_lock(_):
    subprocess.Popen(["bash", LOCK_SH], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    return {"ok": True}


def a_notify(args):
    urg = str(args.get("urgency", "normal"))
    return _ok(qs.t_notify({"title": str(args.get("title", "Phone"))[:80], "body": str(args.get("body", ""))[:500],
                            "urgency": urg if urg in ("low", "normal") else "normal"}))


def a_show_card(args):
    title = str(args.get("title", "")).strip()[:80]
    if not title:
        return {"ok": False, "error": "title required"}
    urg = str(args.get("urgency", "normal"))
    resident_card.emit(title, str(args.get("body", ""))[:1000], icon="󰄜",
                       urgency=urg if urg in ("low", "normal") else "normal", source="qs-remote")
    return {"ok": True}


def a_open_widget(args):
    return _ok(qs.t_open_widget({"name": str(args.get("name", ""))[:40], "toggle": bool(args.get("toggle"))}))


def a_wifi(args):
    # Every call here came in over the tailnet; if Wi-Fi carries the only
    # route out, switching it off strands the phone with no way to undo it.
    if not args.get("on") and _run(["nmcli", "radio", "wifi"]) != "disabled" and not _other_uplink():
        return {"ok": False, "error": "refusing: Wi-Fi is your only path back to this laptop"}
    return _ok(qs._sh(["nmcli", "radio", "wifi", "on" if args.get("on") else "off"]))


def _other_uplink():
    wifi = {ln.split(":")[0] for ln in _run(["nmcli", "-t", "-f", "DEVICE,TYPE", "device"]).splitlines()
            if ln.split(":")[-1] in ("wifi", "wifi-p2p")}
    for fam in ("-4", "-6"):
        try:
            routes = json.loads(_run(["ip", "-j", fam, "route", "show", "default"]) or "[]")
        except ValueError:
            routes = []
        for r in routes:
            dev = r.get("dev") or ""
            if dev and dev not in wifi and not dev.startswith(("tailscale", "lo")):
                return True
    return False


def a_bluetooth(args):
    return _ok(qs._sh(["bluetoothctl", "power", "on" if args.get("on") else "off"]))


def a_dnd(args):
    return _ok(qs._sh(["swaync-client", "-dn" if args.get("on") else "-df"]))


def a_caffeine(args):
    """On = keep the laptop awake, by pausing hypridle (the bar's idle toggle does the same)."""
    running = bool(_run(["pgrep", "-x", "hypridle"]))
    if bool(args.get("on")) == running:
        subprocess.Popen(["bash", os.path.join(HOME, ".config/hypr/scripts/toggle_hypridle.sh")],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def a_kb_layout(_):
    return _ok(qs._sh(["bash", os.path.join(HOME, ".config/hypr/scripts/switch_kb_layout.sh")]))


def a_workspace(args):
    target = args.get("id")
    if target in ("next", "prev"):
        arg = "e+1" if target == "next" else "e-1"
    else:
        n = _int(target)
        if n is None or not 1 <= n <= 20:
            return {"ok": False, "error": "id must be 1-20, next or prev"}
        arg = str(n)
    return _ok(qs._sh(["hyprctl", "dispatch", "workspace", arg]))


def a_screen(args):
    return _ok(qs._sh(["hyprctl", "dispatch", "dpms", "on" if args.get("on", True) else "off"]))


def a_screenshot(_):
    """Full screenshot, sent to the phone through the hub."""
    path = f"/tmp/fleet-shot-{time.strftime('%Y%m%d-%H%M%S')}.png"
    r = qs._sh(["grim", path], timeout=10)
    if not r.get("ok") or not os.path.exists(path):
        return {"ok": False, "error": "couldn't take the screenshot"}
    subprocess.Popen([sys.executable, os.path.join(BASE, "fleet_send.py"), path, "--to", "phone", "--quiet"],
                     start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def a_bind(args):
    """Runs one of the laptop's own keybinds, picked by its position in the
    laptop's list and checked against its combo, so the phone can never
    supply what gets run."""
    if settings().get("qsRemoteInputEnabled", True) is False:
        return {"ok": False, "error": "keyboard control is turned off on the laptop"}
    binds = keybinds()
    i = _int(args.get("id"))
    if i is None or not 0 <= i < len(binds) or binds[i]["combo"] != str(args.get("combo", "")):
        return {"ok": False, "error": "that keybind changed on the laptop; refresh the list"}
    return _ok(qs._run_keybind(binds[i]["raw"]))


def keybinds():
    out = []
    for b in qs._parse_keybinds():
        mods = [m for m in b.get("mods", []) if m]
        combo = "+".join(mods + [b.get("key", "")])
        desc = b["args"][:80] if b.get("dispatch") == "exec" else f"{b.get('dispatch', '')} {b.get('args', '')}".strip()
        out.append({"combo": combo, "desc": desc, "dispatch": b.get("dispatch", ""), "raw": b})
    return out


ACTIONS = {
    "media": a_media, "volume": a_volume, "mute": a_mute, "mic": a_mic, "brightness": a_brightness,
    "night_light": a_night_light, "power_profile": a_power_profile, "wallpaper": a_wallpaper,
    "lock": a_lock, "notify": a_notify, "show_card": a_show_card, "open_widget": a_open_widget,
    "wifi": a_wifi, "bluetooth": a_bluetooth, "dnd": a_dnd, "caffeine": a_caffeine, "kb_layout": a_kb_layout,
    "workspace": a_workspace, "screen": a_screen, "screenshot": a_screenshot, "bind": a_bind,
}
# Names the first version of the API used.
LEGACY = {"media_control": "media", "set_volume": "volume", "toggle_mute": "mute", "set_wallpaper": "wallpaper"}


def describe(name, args):
    on = lambda k: "on" if args.get(k) else "off"  # noqa: E731
    return {
        "media": lambda: {"play-pause": "play/pause", "next": "next track", "previous": "previous track"}.get(args.get("action"), "media"),
        "volume": lambda: f"volume → {args.get('percent')}%",
        "mute": lambda: "toggled mute" if "muted" not in args else ("muted" if args.get("muted") else "unmuted"),
        "mic": lambda: "mic muted" if args.get("muted", True) else "mic on",
        "brightness": lambda: f"brightness → {args.get('percent')}%",
        "night_light": lambda: "night light " + on("on"),
        "power_profile": lambda: f"power profile → {args.get('profile')}",
        "wallpaper": lambda: f"wallpaper → {args.get('name', 'random')}",
        "lock": lambda: "locked the screen",
        "open_widget": lambda: f"opened {args.get('name')}",
        "wifi": lambda: "Wi-Fi " + on("on"),
        "bluetooth": lambda: "Bluetooth " + on("on"),
        "dnd": lambda: "do not disturb " + on("on"),
        "caffeine": lambda: "stay awake " + on("on"),
        "kb_layout": lambda: "switched keyboard layout",
        "screen": lambda: "screen " + ("on" if args.get("on", True) else "off"),
        "screenshot": lambda: "screenshot sent to the phone",
        "notify": lambda: f"notification: {str(args.get('title', 'Phone'))[:60]}",
        "show_card": lambda: f"card: {str(args.get('title', ''))[:60]}",
        "bind": lambda: f"keybind {args.get('combo', '')}".strip(),
    }.get(name, lambda: name.replace("_", " "))()


# ---------------------------------------------------------------- photo answers

ANSWER_MODELS = {"fast": "claude-haiku-4-5-20251001", "accurate": "claude-sonnet-5"}
KAHOOT_COLORS = {1: "red", 2: "blue", 3: "yellow", 4: "green"}
ANSWER_PROMPT = (
    "This photo shows a quiz question, usually Kahoot: a question and up to four answer tiles "
    "(red triangle, blue diamond, yellow circle, green square, in that order). It may be taken "
    "at an angle, off a screen or a projector. Work out the correct answer.\n"
    "Reply with ONLY one JSON object, no prose, no code fence:\n"
    '{"question": "<the question, short>", "answer": "<the correct answer text>", '
    '"option": <1-4 for the tile, or null>, "confidence": "high" | "medium" | "low"}\n'
    "If it's true/false, option 1 is the first tile shown. If you can't read a question, "
    'set "answer" to "can\'t read the question" and "confidence" to "low".'
)


def answer_photo(data, media_type, mode="fast"):
    try:
        from claude_say import _PROVIDERS, _read_key
    except Exception:
        return {"ok": False, "error": "no Claude API key set up on the laptop"}
    body = {"model": ANSWER_MODELS[mode], "max_tokens": 300,
            "messages": [{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": media_type,
                                              "data": base64.b64encode(data).decode()}},
                {"type": "text", "text": ANSWER_PROMPT}]}]}
    text = ""
    for keyfile, url in _PROVIDERS:
        key = _read_key(keyfile)
        if not key:
            continue
        try:
            req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
                "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01"})
            with urllib.request.urlopen(req, timeout=30) as r:
                out = json.loads(r.read())
            text = "".join(b.get("text", "") for b in out.get("content", []) if b.get("type") == "text").strip()
            if text:
                break
        except Exception as e:
            log(f"answer call failed: {type(e).__name__}")
    if not text:
        return {"ok": False, "error": "Claude didn't answer; check the API key on the laptop"}
    parsed = None
    m = re.search(r"\{.*\}", text, re.S)
    if m:
        try:
            parsed = json.loads(m.group(0))
        except ValueError:
            parsed = None
    if not isinstance(parsed, dict):
        return {"ok": True, "answer": text[:300], "question": "", "option": None, "color": None, "confidence": "low"}
    opt = _int(parsed.get("option"))
    opt = opt if opt in KAHOOT_COLORS else None
    conf = str(parsed.get("confidence", "medium")).lower()
    return {"ok": True, "answer": str(parsed.get("answer", ""))[:300], "question": str(parsed.get("question", ""))[:300],
            "option": opt, "color": KAHOOT_COLORS.get(opt), "confidence": conf if conf in ("high", "medium", "low") else "medium"}


KAHOOT_HOSTS = ("kahoot.it",)
KAHOOT_TILES = {4: ["red triangle", "blue diamond", "yellow circle", "green square"],
                2: ["blue diamond", "red triangle"]}
KAHOOT_FIND = """(() => {
  const want = 'answer-' + %d, text = %s;
  const norm = s => (s || '').toLowerCase().replace(/\\s+/g, ' ').trim();
  const tiles = [...document.querySelectorAll('[data-functional-selector^="answer-"]')]
    .filter(e => /^answer-[0-9]$/.test(e.getAttribute('data-functional-selector')));
  if (!tiles.length) return {error: 'no answer buttons on the page'};
  if (tiles.some(e => e.tagName !== 'BUTTON')) return {error: 'multi-select question, not clicking'};
  let pick = tiles.find(e => e.getAttribute('data-functional-selector') === want);
  const byText = text ? tiles.filter(e => norm(e.innerText) === text) : [];
  if (byText.length === 1) pick = byText[0];
  if (!pick) return {error: 'no tile for that answer on the page'};
  if (pick.disabled) return {error: 'the question already closed'};
  const r = pick.getBoundingClientRect();
  if (r.width < 4 || r.height < 4) return {error: 'the answer button is hidden'};
  const x = r.left + r.width / 2, y = r.top + r.height / 2;
  const hit = document.elementFromPoint(x, y);
  if (!hit || !pick.contains(hit)) return {error: 'something is covering the answer button'};
  return {x, y, count: tiles.length, tile: tiles.indexOf(pick),
          sel: pick.getAttribute('data-functional-selector'), label: (pick.innerText || '').trim().slice(0, 120)};
})()"""


def _cdp_value(resp):
    res = (resp or {}).get("result") or {}
    return None if res.get("exceptionDetails") else (res.get("result") or {}).get("value")


def kahoot_click(option, answer="", hosts=KAHOOT_HOSTS):
    if option not in KAHOOT_COLORS:
        return {"ok": False, "error": "no tile to click"}
    try:
        tabs = json.loads(qs._cdp("/json/list"))
    except Exception:
        return {"ok": False, "error": "Vivaldi isn't reachable over CDP on :9222"}
    pages = [t for t in tabs if t.get("type") == "page" and t.get("webSocketDebuggerUrl")
             and (urlsplit(t.get("url", "")).hostname or "") in hosts]
    if not pages:
        return {"ok": False, "error": "no Kahoot tab open in Vivaldi"}
    text = " ".join(str(answer).lower().split())
    expr = KAHOOT_FIND % (option - 1, json.dumps(text))
    ready, errors = [], []
    for t in pages:
        try:
            v = _cdp_value(qs._cdp_ws_send(t["webSocketDebuggerUrl"], [
                {"method": "Runtime.evaluate", "params": {"expression": expr, "returnByValue": True}}], timeout=4)[0])
        except Exception:
            continue
        if isinstance(v, dict) and "x" in v:
            ready.append((t, v))
        elif isinstance(v, dict) and v.get("error"):
            errors.append(v["error"])
    if len(ready) > 1:
        return {"ok": False, "error": "more than one Kahoot question is open"}
    if not ready:
        return {"ok": False, "error": errors[0] if errors else "couldn't find the answer buttons"}
    tab, v = ready[0]
    at = {"x": v["x"], "y": v["y"]}
    press = {**at, "type": "mousePressed", "button": "left", "buttons": 1, "clickCount": 1}
    try:
        qs._cdp_ws_send(tab["webSocketDebuggerUrl"], [
            {"method": "Input.dispatchMouseEvent", "params": {**at, "type": "mouseMoved"}},
            {"method": "Input.dispatchMouseEvent", "params": press},
            {"method": "Input.dispatchMouseEvent", "params": {**press, "type": "mouseReleased", "buttons": 0}}], timeout=4)
    except Exception as e:
        return {"ok": False, "error": f"the click didn't go through ({type(e).__name__})"}
    names = KAHOOT_TILES.get(v.get("count"), KAHOOT_TILES[4])
    tile = v.get("tile", 0)
    return {"ok": True, "tile": tile + 1, "name": names[tile] if 0 <= tile < len(names) else "",
            "label": v.get("label", ""), "selector": v.get("sel", "")}


def kahoot_card(result, click):
    shown = click.get("label") or result.get("answer") or "?"
    if click.get("ok"):
        resident_card.emit(f"Kahoot: clicked '{shown[:60]}'", f"{click.get('name', '')} · {result.get('confidence', '')} confidence".strip(" ·"),
                           icon="󰄜", urgency="low", hold_secs=8, source="qs-remote", card_id="qs-remote-kahoot")
    else:
        resident_card.emit("Kahoot: didn't click", f"{click.get('error', '')}. Answer was '{str(result.get('answer', ''))[:60]}'.",
                           icon="󰄜", urgency="normal", hold_secs=10, source="qs-remote", card_id="qs-remote-kahoot")


# ---------------------------------------------------------------- plumbing

class Limiter:
    def __init__(self):
        self.hits = {}
        self.mu = threading.Lock()

    def allow(self, key, limit):
        now = time.time()
        with self.mu:
            q = self.hits.setdefault(key, deque())
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= limit:
                return False
            q.append(now)
            return True


_audit_mu = threading.Lock()


def audit(entry, extra=None):
    entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), **entry}
    with _audit_mu:
        try:
            if os.path.exists(AUDIT) and os.path.getsize(AUDIT) > AUDIT_MAX:
                os.replace(AUDIT, AUDIT + ".1")
            with open(AUDIT, "a") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError:
            pass
    history_note({**entry, **(extra or {})})


# ---------------------------------------------------------------- history
# What the phone did, display-ready for the Guide. The audit log stays the
# record; this is a small rolling view of it that also catches slider drags.

HISTORY = "/tmp/qs_remote_history.json"
HISTORY_MAX = 80
HISTORY_MERGE = 20
MERGE_ANY = LIVE | {"workspace"}
_hist = deque(maxlen=HISTORY_MAX)
_hist_mu = threading.Lock()
_peers = {"at": 0.0, "map": {}}


def _device(ip):
    now = time.time()
    if now - _peers["at"] > 300:
        try:
            st = json.loads(_run(["tailscale", "status", "--json"], timeout=5) or "{}")
        except ValueError:
            st = {}
        m = {}
        for p in [st.get("Self") or {}, *(st.get("Peer") or {}).values()]:
            for a in p.get("TailscaleIPs") or []:
                m[a] = p.get("HostName") or ""
        _peers.update(at=now, map=m)
    return _peers["map"].get(ip) or ""


def _span(secs):
    secs = int(secs or 0)
    return f"{secs // 60}m {secs % 60}s" if secs >= 60 else f"{secs}s"


def _history_desc(e):
    a = e.get("action") or ""
    if e.get("denied"):
        return f"blocked a request ({e['denied']})"
    if a == "input_session":
        return f"touchpad & keyboard · {_span(e.get('secs'))}"
    if a == "answer":
        return f"quiz answer ({e.get('mode', 'fast')})"
    try:
        return describe(a, e.get("args") or {})
    except Exception:
        return a.replace("_", " ")


def history_note(e, ts=None, write=True):
    ts = ts or time.time()
    row = {"ts": int(ts), "time": time.strftime("%H:%M", time.localtime(ts)),
           "day": time.strftime("%Y-%m-%d", time.localtime(ts)),
           "action": "denied" if e.get("denied") else (e.get("action") or ""),
           "desc": _history_desc(e), "ok": bool(e.get("ok", not e.get("denied"))),
           "error": str(e.get("error") or ""), "device": _device(e.get("ip", "")) or e.get("user") or e.get("ip", ""),
           "user": e.get("user", ""), "count": 1}
    with _hist_mu:
        last = _hist[-1] if _hist else None
        if (last and last["action"] == row["action"] and last["device"] == row["device"]
                and last["ok"] == row["ok"] and row["ts"] - last["ts"] <= HISTORY_MERGE
                and (row["action"] in MERGE_ANY or last["desc"] == row["desc"])):
            row["count"] = last["count"] + 1
            _hist.pop()
        _hist.append(row)
        if write:
            _history_write()


def _history_write():
    try:
        tmp = HISTORY + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"updated": int(time.time()), "entries": list(reversed(_hist))}, f, ensure_ascii=False)
        os.replace(tmp, HISTORY)
    except OSError:
        pass


def history_seed():
    lines = []
    for path in (AUDIT + ".1", AUDIT):
        try:
            with open(path) as f:
                lines += f.read().splitlines()
        except OSError:
            pass
    for ln in lines[-HISTORY_MAX * 3:]:
        try:
            e = json.loads(ln)
            ts = time.mktime(time.strptime(e["ts"], "%Y-%m-%dT%H:%M:%S"))
        except (ValueError, KeyError, TypeError):
            continue
        history_note(e, ts, write=False)
    with _hist_mu:
        _history_write()


def run_action(name, args, who):
    fn = ACTIONS.get(LEGACY.get(name, name))
    name = LEGACY.get(name, name)
    try:
        result = fn(args)
    except Exception as e:
        log(f"{name} failed: {type(e).__name__}: {e}")
        result = {"ok": False, "error": "action failed"}
    ok = bool(result.get("ok"))
    entry = {"action": name, "args": args, "ok": ok, "user": who[0], "ip": who[1]}
    if ok and name in LIVE:  # a dragged slider would flood the log
        history_note(entry)
    else:
        audit(entry, None if ok else {"error": result.get("error", "")})
    return result


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # A phone that gave up or switched networks mid-reply is routine.
        if isinstance(sys.exc_info()[1], (BrokenPipeError, ConnectionResetError, TimeoutError)):
            return
        super().handle_error(request, client_address)


class Handler(BaseHTTPRequestHandler):
    server_version = "qs-remote"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    # -- responses
    def _send(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode(), "application/json")

    def _redirect(self, where, extra=None):
        self._send(303, b"", "text/plain", {"Location": where, **(extra or {})})

    # -- gates
    def _who(self):
        return (self.headers.get("Tailscale-User-Login") or "",
                (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip())

    def _gate(self):
        """Kill switch and Tailscale identity. Returns an error or None."""
        s = settings()
        if s.get("qsRemoteEnabled", True) is False:
            return 503, "remote control is turned off on the laptop"
        login = self._who()[0]
        if s.get("qsRemoteRequireIdentity", True) and not login:
            return 403, "not from a signed-in tailnet device"
        allowed = s.get("qsRemoteAllowedLogins") or []
        if allowed and login not in allowed:
            return 403, "this tailnet login isn't allowed"
        return None

    def _bearer_ok(self):
        h = self.headers.get("Authorization", "")
        given = h[7:].strip() if h.lower().startswith("bearer ") else ""
        return bool(given) and hmac.compare_digest(given.encode(), self.server.token.encode())

    def _session(self):
        return hmac.new(self.server.token.encode(), b"qs-remote mobile session", hashlib.sha256).hexdigest()

    def _cookie_ok(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == COOKIE and hmac.compare_digest(v.encode(), self._session().encode()):
                return True
        return False

    def _same_origin(self):
        origin = self.headers.get("Origin") or self.headers.get("Referer") or ""
        host = self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or ""
        return bool(origin) and bool(host) and urlsplit(origin).netloc == host

    def _limit(self, kind):
        who = self._who()
        key = (who[0] or who[1], kind)
        return self.server.limiter.allow(key, LIMITS[kind])

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = -1
        if n < 0 or n > MAX_BODY:
            return None, (413, "body too large")
        raw = self.rfile.read(n) if n else b""
        return raw, None

    # -- routes
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urlsplit(self.path).path
        err = self._gate()
        if err:
            return self._mobile_error(*err) if path == "/m" else self._json(err[0], {"ok": False, "error": err[1]})
        if path == "/m":
            return self._mobile_get()
        if not self._bearer_ok():
            return self._json(401, {"ok": False, "error": "unauthorized"})
        if not self._limit("read"):
            return self._json(429, {"ok": False, "error": "rate limited"})
        if path in ("/api/v1/state", "/state"):
            return self._json(200, {"ok": True, **snapshot()})
        if path == "/api/v1/art":
            return self._art()
        if path in ("/api/v1/actions", "/actions"):
            return self._json(200, {"ok": True, "actions": sorted(ACTIONS)})
        if path == "/api/v1/binds":
            if not self._input_on():
                return self._json(503, {"ok": False, "error": "keyboard control is turned off on the laptop"})
            binds = [{"id": i, "combo": b["combo"], "desc": b["desc"], "dispatch": b["dispatch"]}
                     for i, b in enumerate(keybinds())]
            return self._json(200, {"ok": True, "binds": binds})
        if path == "/api/v1/input":
            return self._input()
        return self._json(404, {"ok": False, "error": "not found"})

    def _input_on(self):
        s = settings()
        return s.get("qsRemoteEnabled", True) is not False and s.get("qsRemoteInputEnabled", True) is not False

    def _input(self):
        if not self._input_on():
            return self._json(503, {"ok": False, "error": "touchpad and keyboard are turned off on the laptop"})
        key = self.headers.get("Sec-WebSocket-Key", "")
        if "websocket" not in (self.headers.get("Upgrade") or "").lower() or not key:
            return self._json(400, {"ok": False, "error": "websocket upgrade expected"})
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", remote_input.accept_key(key))
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        who = self._who()
        started = time.time()
        counts = remote_input.serve(self, self._input_on)
        # One line per session; what was typed is never recorded.
        audit({"action": "input_session", "secs": int(time.time() - started), "events": counts,
               "user": who[0], "ip": who[1]})

    def do_POST(self):
        path = urlsplit(self.path).path
        err = self._gate()
        if err:
            return self._mobile_error(*err) if path == "/m" else self._json(err[0], {"ok": False, "error": err[1]})
        if path == "/m":
            return self._mobile_post()
        if not self._bearer_ok():
            audit({"path": path[:80], "denied": "auth", "user": self._who()[0], "ip": self._who()[1]})
            return self._json(401, {"ok": False, "error": "unauthorized"})
        if path == "/api/v1/answer":
            return self._answer()
        m = re.match(r"^/(?:api/v1/)?action/([a-z_]{1,32})$", path)
        if not m or LEGACY.get(m.group(1), m.group(1)) not in ACTIONS:
            return self._json(404, {"ok": False, "error": "action not allowed"})
        raw, berr = self._body()
        if berr:
            return self._json(*berr)
        try:
            args = json.loads(raw or b"{}")
        except ValueError:
            return self._json(400, {"ok": False, "error": "invalid json"})
        if not isinstance(args, dict):
            return self._json(400, {"ok": False, "error": "object expected"})
        name = LEGACY.get(m.group(1), m.group(1))
        if not self._limit("live" if name in LIVE else "act"):
            return self._json(429, {"ok": False, "error": "rate limited"})
        result = run_action(m.group(1), args, self._who())
        if path.startswith("/api/v1/"):
            try:
                result = {**result, "state": snapshot()}
            except Exception:
                pass
        return self._json(200 if result.get("ok") else 422, result)

    def _answer(self):
        """A photo of a quiz question in, the answer out (the Kahoot tab)."""
        if not self._limit("answer"):
            return self._json(429, {"ok": False, "error": "rate limited"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if not 0 < n <= ANSWER_MAX:
            return self._json(413, {"ok": False, "error": "send a photo up to 8 MB"})
        data = self.rfile.read(n)
        ctype = (self.headers.get("Content-Type") or "image/jpeg").split(";")[0].strip()
        if ctype not in ("image/jpeg", "image/png", "image/webp"):
            return self._json(415, {"ok": False, "error": "jpeg, png or webp only"})
        mode = "accurate" if self.headers.get("X-Answer-Mode") == "accurate" else "fast"
        started = time.time()
        result = answer_photo(data, ctype, mode)
        result["ms"] = int((time.time() - started) * 1000)
        if result.get("ok") and self.headers.get("X-Answer-Click") == "1":
            result["click"] = kahoot_click(result.get("option"), result.get("answer", ""))
            kahoot_card(result, result["click"])
        audit({"action": "answer", "mode": mode, "ok": result.get("ok"), "ms": result["ms"],
               "click": (result.get("click") or {}).get("ok"),
               "user": self._who()[0], "ip": self._who()[1]})
        return self._json(200 if result.get("ok") else 502, result)

    def _art(self):
        try:
            path = _art_path((qs.t_music({}) or {}).get("artUrl") or "")
        except Exception:
            path = None
        if not path:
            return self._json(404, {"ok": False, "error": "no cover"})
        with open(path, "rb") as f:
            data = f.read(ART_MAX + 1)
        ext = path.rsplit(".", 1)[-1].lower()
        ctype = {"png": "image/png", "webp": "image/webp"}.get(ext, "image/jpeg")
        return self._send(200, data, ctype)

    # -- the small browser page, for when the app isn't to hand
    def _mobile_get(self):
        q = parse_qs(urlsplit(self.path).query)
        given = (q.get("t") or [""])[0]
        if given:
            if not hmac.compare_digest(given.encode(), self.server.token.encode()):
                return self._mobile_error(401, "that link isn't valid any more")
            # Swap the token in the URL for a cookie and drop it from the address bar.
            cookie = f"{COOKIE}={self._session()}; Path=/m; Max-Age=2592000; HttpOnly; Secure; SameSite=Strict"
            return self._redirect("/m", {"Set-Cookie": cookie})
        if not self._cookie_ok():
            return self._mobile_error(401, "open the setup link from the laptop first")
        if not self._limit("read"):
            return self._mobile_error(429, "too many requests, wait a moment")
        msg = (q.get("ok") or [""])[0]
        return self._send(200, self._mobile_page(msg[:60]), "text/html; charset=utf-8",
                          {"Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'"})

    def _mobile_post(self):
        if not self._cookie_ok() or not self._same_origin():
            return self._mobile_error(401, "open the setup link from the laptop first")
        raw, berr = self._body()
        if berr:
            return self._mobile_error(*berr)
        do = (parse_qs(raw.decode(errors="replace")).get("do") or [""])[0]
        plan = {"playpause": ("media", {"action": "play-pause"}), "next": ("media", {"action": "next"}),
                "prev": ("media", {"action": "previous"}), "mute": ("mute", {}), "lock": ("lock", {})}.get(do)
        if not plan:
            return self._redirect("/m")
        if not self._limit("act"):
            return self._redirect("/m?ok=" + quote("slow down"))
        r = run_action(plan[0], plan[1], self._who())
        return self._redirect("/m?ok=" + quote(describe(*plan) if r.get("ok") else "that didn't work"))

    def _mobile_error(self, code, msg):
        body = (f"<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'>"
                f"<title>qs-remote</title><body style='background:#1e1e2e;color:#cdd6f4;font:16px system-ui;padding:24px'>"
                f"<p>{_esc(msg)}</p>").encode()
        return self._send(code, body, "text/html; charset=utf-8")

    def _mobile_page(self, msg):
        s = snapshot()
        m, bat = s["music"], s["power"]["battery"]
        btn = lambda do, label: f'<button name="do" value="{do}">{label}</button>'  # noqa: E731
        return f"""<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{_esc(s['host'])}</title>
<style>
body{{background:#1e1e2e;color:#cdd6f4;font:16px system-ui;margin:0;padding:24px;max-width:480px}}
h1{{font-size:20px;margin:0 0 16px}} .card{{background:#313244;border-radius:14px;padding:16px;margin-bottom:14px}}
.row{{display:flex;justify-content:space-between;color:#bac2de;font-size:15px}}
form{{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}}
button{{min-height:48px;padding:0 18px;border:0;border-radius:12px;background:#45475a;color:#cdd6f4;font:inherit}}
button:focus-visible{{outline:3px solid #89b4fa;outline-offset:2px}}
.msg{{color:#a6e3a1;margin-bottom:12px}}
</style>
<h1>{_esc(s['host'])}</h1>
{f'<p class="msg" role="status">{_esc(msg)}</p>' if msg else ''}
<div class="card"><div class="row"><span>Battery</span><span>{'?' if bat is None else bat}%{' · charging' if s['power']['charging'] else ''}</span></div>
<div class="row"><span>Wi-Fi</span><span>{_esc(s['network']['ssid']) or '—'}</span></div>
<div class="row"><span>Volume</span><span>{'muted' if s['audio']['muted'] else str(s['audio']['volume']) + '%'}</span></div></div>
<div class="card"><div>{_esc(m['title']) or 'Nothing playing'}</div><div class="row"><span>{_esc(m['artist'])}</span><span>{m['status']}</span></div>
<form method="post" action="/m">{btn('prev', 'Previous')}{btn('playpause', 'Play / pause')}{btn('next', 'Next')}</form></div>
<div class="card"><form method="post" action="/m">{btn('mute', 'Toggle mute')}{btn('lock', 'Lock screen')}</form></div>
</html>""".encode()


# ---------------------------------------------------------------- pairing

def _env(path):
    out = {}
    try:
        with open(path) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k and not k.startswith("#"):
                    out[k] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def pair():
    try:
        st = json.loads(_run(["tailscale", "status", "--json"], timeout=5) or "{}")
    except ValueError:
        st = {}
    me = (st.get("Self") or {}).get("DNSName", "").rstrip(".")
    if not me:
        print("tailscale isn't running here, so there's no address to pair with.", file=sys.stderr)
        return 1
    hub = ""
    for p in (st.get("Peer") or {}).values():
        if (p.get("DNSName") or "").split(".")[0].lower() == "basecamp":
            hub = "http://" + p["DNSName"].rstrip(".") + ":8780"
    toks = _env(FLEET_TOKENS)
    params = {"v": "1", "name": me.split(".")[0], "laptop": "https://" + me, "token": load_token(),
              "hub": toks.get("FLEET_URL_PHONE") or hub, "device": "phone",
              "hub_token": toks.get("FLEET_TOKEN_PHONE", ""), "read_token": toks.get("FLEET_READ_TOKEN", "")}
    link = "fleet://setup?" + "&".join(f"{k}={quote(v, safe='')}" for k, v in params.items())
    serve = _run(["tailscale", "serve", "status"], timeout=5)
    if str(PORT) not in serve:
        print(f"! tailscale serve isn't forwarding to qs-remote yet. Run:\n    tailscale serve --bg {PORT}\n")
    if not params["hub_token"] or not params["read_token"]:
        print(f"! {FLEET_TOKENS} has no FLEET_TOKEN_PHONE / FLEET_READ_TOKEN, so the app will only see this laptop.\n"
              "  Add a phone token to the hub's FLEET_DEVICE_TOKENS and put it here as FLEET_TOKEN_PHONE.\n")
    print("Open this on the phone (it holds secrets: don't paste it into chats):\n")
    print(link + "\n")
    if _run(["which", "qrencode"]):
        subprocess.run(["qrencode", "-t", "ansiutf8", link])
    return 0


def main():
    if sys.argv[1:2] == ["pair"]:
        sys.exit(pair())
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("already running")
        return
    history_seed()
    srv = Server((HOST, PORT), Handler)
    srv.daemon_threads = True
    srv.token = load_token()
    srv.limiter = Limiter()
    log(f"listening on {HOST}:{PORT}")
    srv.serve_forever()


# ---------------------------------------------------------------- control center extras

SPECIAL_WS = "magic"
QUIET_FILE = os.path.join(BASE, "resident_quiet.json")
KANDOR_PID = "/tmp/qs_wake_daemon.pid"
KANDOR_TOGGLE = os.path.join(BASE, "voice", "kandor_toggle.sh")
ECO_STATE = "/tmp/qs_eco_state.json"
PALETTE_PY = os.path.join(os.path.dirname(BASE), "palette", "palette_index.py")


def _read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _special_open():
    mons = _json_run(["hyprctl", "monitors", "-j"]) or []
    focused = next((m for m in mons if isinstance(m, dict) and m.get("focused")), {})
    return bool((focused.get("specialWorkspace") or {}).get("name"))


def _kandor_on():
    try:
        with open(KANDOR_PID) as f:
            os.kill(int(f.read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def _quiet_on():
    q = _read_json(QUIET_FILE, {})
    return isinstance(q, dict) and q.get("quiet") is True


def _eco_on():
    return settings().get("ecoModeEnabled", True) is not False


_snapshot_core = snapshot


def snapshot():
    s = _snapshot_core()
    eco = _read_json(ECO_STATE, [])
    s["toggles"].update(special=_special_open(), eco=_eco_on(), quiet=_quiet_on(), kandor=_kandor_on())
    s["eco_active"] = len(eco) if isinstance(eco, list) else 0
    return s


def a_toggle_special_workspace(args):
    if "on" in args and bool(args.get("on")) == _special_open():
        return {"ok": True}
    return _ok(qs._sh(["hyprctl", "dispatch", "togglespecialworkspace", SPECIAL_WS], timeout=5))


def a_eco(args):
    on = bool(args.get("on", not _eco_on()))
    return _ok(qs._sh([sys.executable, PALETTE_PY, "set", "ecoModeEnabled", "true" if on else "false"], timeout=5))


def a_quiet(args):
    on = bool(args.get("on", not _quiet_on()))
    if on != _quiet_on():
        tmp = QUIET_FILE + ".tmp"
        with open(tmp, "w") as f:
            f.write(json.dumps({"quiet": on}) + "\n")
        os.replace(tmp, QUIET_FILE)
    return {"ok": True}


def a_kandor(args):
    on = bool(args.get("on", not _kandor_on()))
    if on != _kandor_on():
        subprocess.Popen(["bash", KANDOR_TOGGLE], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    return {"ok": True}


for _name, _fn in (("toggle_special_workspace", a_toggle_special_workspace), ("eco", a_eco),
                   ("quiet", a_quiet), ("kandor", a_kandor)):
    ACTIONS.setdefault(_name, _fn)

_describe_core = describe


def describe(name, args):
    on = "on" if args.get("on") else "off"
    extra = {
        "toggle_special_workspace": ("scratchpad " + ("shown" if args.get("on") else "hidden")) if "on" in args else "toggled the scratchpad",
        "eco": "eco mode " + on,
        "quiet": "Claude quiet " + on,
        "kandor": "wake word " + on,
        "palette": f"palette: {str(args.get('label') or args.get('id') or '')[:60]}",
    }
    return extra.get(name) or _describe_core(name, args)


PHONE_TEXT_OK = {"claude.ask", "claude.note", "spotify.search", "spotify.mood", "web.open", "ws.openapp", "ws.rename", "mail.search"}
PHONE_BLOCKED = ("setting.qsRemote", "fleet.")
PAL_BIAS = {"power": 3, "system": 2, "audio": 2, "media": 2, "widget": 2, "mail": 2, "timer": 2, "claude": 1,
            "capture": 1, "wallpaper": 1, "layout": 1, "window": 2, "workspace": 1, "device": 2, "project": 2,
            "app": 0, "setting": -2}
PAL_TRANSIENT = ("mailhit.", "window.", "tab.", "spotifyhit.", "route.")
PAL_STALE = 300
ROUTE_ERRORS = {"short": "Type a few more words", "no-client": "No Claude key on the laptop",
                "no-reply": "Claude didn't answer", "no-match": "Claude couldn't map that to anything on the laptop"}
_pal = {"mod": None, "mtime": 0.0, "building": False}
_pal_mu = threading.Lock()


def _palette():
    m = os.path.getmtime(PALETTE_PY)
    with _pal_mu:
        if _pal["mod"] is None or m != _pal["mtime"]:
            spec = importlib.util.spec_from_file_location("palette_index", PALETTE_PY)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            _pal.update(mod=mod, mtime=m)
        return _pal["mod"]


def _pal_refresh(p):
    try:
        age = time.time() - os.path.getmtime(p.CACHE)
    except OSError:
        age = PAL_STALE + 1
    with _pal_mu:
        if age < PAL_STALE or _pal["building"]:
            return
        _pal["building"] = True

    def work():
        try:
            p.write_atomic(p.CACHE, p.build())
        except Exception as e:
            log(f"palette index rebuild failed: {type(e).__name__}: {e}")
        finally:
            _pal["building"] = False
    threading.Thread(target=work, daemon=True).start()


def _pal_phone_ok(a):
    if not a or a["id"].startswith(PHONE_BLOCKED):
        return False
    return (a.get("param") or {}).get("kind") != "text" or a["id"] in PHONE_TEXT_OK


def _pal_fresh(a, states):
    a = dict(a)
    key = a.get("stateKey")
    if key and key in states:
        a["state"] = states[key]
    sid = a["id"][8:] if a["id"].startswith("setting.") else ""
    if sid and "." not in sid and a.get("state") in ("on", "off"):
        v = settings().get(sid)
        if isinstance(v, bool):
            a.update(state="on" if v else "off", arg="false" if v else "true")
    return a


def _pal_needs(p, a):
    if not a.get("param"):
        return False
    r = p.resolve_step(a, {"arg": ""}, {})
    return r is None or r.get("args") == [""]


def _pal_score(a, toks):
    label = a["label"].lower()
    words = re.findall(r"[a-z0-9]+", label)
    kws = re.findall(r"[a-z0-9]+", (a.get("keywords") or "").lower() + " " + (a.get("cat") or ""))
    hint = (a.get("hint") or "").lower()
    total = 0
    for t in toks:
        if label.startswith(t):
            total += 12
        elif any(w.startswith(t) for w in words):
            total += 9
        elif t in label:
            total += 6
        elif any(w.startswith(t) for w in kws):
            total += 4
        elif len(t) > 3 and t in hint:
            total += 2
        else:
            return 0
    return total


def _pal_rank(actions, q, hist):
    raw = q.strip()
    toks = raw.lower().split()
    tail = toks[-1] if len(toks) > 1 and re.match(r"^[+-]?\d+(\.\d+)?%?$", toks[-1]) else ""
    scored = []
    for a in actions:
        p = a.get("param") or {}
        if p and raw.lower().startswith(a["label"].lower() + " "):
            arg = raw[len(a["label"]) + 1:].strip()
            if arg:
                scored.append((1000 + len(a["label"]), {**a, "_arg": arg}))
                continue
        if tail and p.get("kind") == "number":
            s = _pal_score(a, toks[:-1])
            if s:
                scored.append((500 + s + PAL_BIAS.get(a.get("cat"), 0), {**a, "_arg": tail}))
                continue
        s = _pal_score(a, toks)
        if s:
            use = min((hist.get(a["id"]) or {}).get("n", 0), 20)
            scored.append((s + PAL_BIAS.get(a.get("cat"), 0) + use * 0.4, a))
    scored.sort(key=lambda x: -x[0])
    return scored[:12]


PAL_WS_VERB = re.compile(r"^(open|launch|start|run|spawn|put|fire up)\s+\S.*\s(on|in|to|onto|into)\s+(a |an |the )?"
                         r"(new|empty|fresh|free|blank|next|another|clean|workspace|ws|desktop|\d+)\b")
PAL_WS_TAIL = re.compile(r"\S\s+(on|in|to)\s+(workspace|ws|desktop)\s*\d+$")
PAL_MULTI = re.compile(r" and |,| then ")
PAL_FILEISH = re.compile(r"\.(json|py|qml|js|md|txt|sh|conf|log|png|jpe?g|webp|gif|mp4|pdf)$", re.I)


def _pal_ws_intent(q):
    t = q.lower()
    return not PAL_MULTI.search(t) and bool(PAL_WS_VERB.search(t) or PAL_WS_TAIL.search(t))


def _pal_urlish(q):
    if re.match(r"^[a-z][a-z0-9+.-]*://\S+$", q, re.I):
        return True
    if re.search(r"\s", q) or PAL_FILEISH.search(q):
        return False
    return bool(re.match(r"^([\w-]+\.)+[a-z]{2,}(:\d+)?([/?#]\S*)?$", q, re.I) or re.match(r"^localhost(:\d+)?(/\S*)?$", q, re.I))


def _pal_auto(q, scored):
    if _pal_ws_intent(q):
        return "direct"
    if _pal_urlish(q):
        return None
    top = scored[0] if scored else None
    if top and top[1].get("live"):
        return None
    toks = q.split()
    weak = not top or (not top[1].get("_arg") and top[0] < 6 * len(toks))
    return "claude" if PAL_MULTI.search(q.lower()) or (weak and len(toks) >= (3 if top else 2)) else None


def _pal_item(p, a, states):
    a = _pal_fresh(a, states)
    item = {"id": a["id"], "label": a["label"], "hint": a.get("hint", ""), "cat": a.get("cat", ""),
            "danger": bool(a.get("danger")), "keys": a.get("keys", "")}
    if a.get("state") in ("on", "off"):
        item["state"] = a["state"]
    param = a.get("param")
    if param:
        item["param"] = {k: param[k] for k in ("kind", "min", "max", "unit", "required") if k in param}
        item["needs"] = _pal_needs(p, a)
    if a.get("_arg"):
        item["arg"] = a["_arg"]
    return item


def palette_query(q, ask):
    p = _palette()
    _pal_refresh(p)
    every = p.index_actions()
    actions = [a for a in every if _pal_phone_ok(a)]
    hist = p.load_json(p.HISTORY, {})
    out = {"ok": True, "items": [], "route": None, "recent": False, "auto": None}
    qt = q.strip()
    if not qt:
        by_id = {a["id"]: a for a in actions}
        recent = sorted((i for i in hist if i in by_id and not i.startswith(PAL_TRANSIENT)), key=lambda i: -hist[i].get("t", 0))[:8]
        suggest = [i for i in (p.load_json(p.CACHE, {}).get("suggest") or []) if i in by_id and i not in recent]
        ranked = [by_id[i] for i in (recent + suggest)[:10]]
        out["recent"] = True
    else:
        scored = _pal_rank(actions, q, hist)
        out["auto"] = _pal_auto(qt, scored)
        ranked = [a for _, a in scored]
        by_id = {a["id"]: a for a in actions}
        lead = by_id.get("ws.openapp" if _pal_ws_intent(qt) else "web.open" if _pal_urlish(qt) else "")
        if lead:
            ranked = [{**lead, "_arg": qt}] + [a for a in ranked if a["id"] != lead["id"]][:11]
    states = p.live_states() if any(a.get("stateKey") for a in ranked) else {}
    out["items"] = [_pal_item(p, a, states) for a in ranked]
    if ask and len(q.strip()) >= 3:
        r = p.route(q)
        if not r.get("ok"):
            out["error"] = ROUTE_ERRORS.get(r.get("error"), "Claude couldn't map that")
            return out
        by_id = {a["id"]: a for a in every}
        steps = r.get("steps") or []
        blocked = [s.get("label", s.get("id")) for s in steps if not _pal_phone_ok(by_id.get(s.get("id")))]
        if blocked:
            out["error"] = "Claude picked something the phone can't run: " + ", ".join(blocked)
            return out
        act = r["action"]
        out["route"] = {"id": act["id"], "label": act["label"], "hint": act.get("hint", ""), "cat": "claude",
                        "danger": bool(act.get("danger")),
                        "steps": [s["label"] + (" " + s["show"] if s.get("show") else "") + (" (already)" if s.get("skip") else "")
                                  for s in steps]}
    return out


def palette_run(body):
    p = _palette()
    aid = str(body.get("id") or "")[:200]
    arg = body.get("arg")
    arg = None if arg is None else str(arg)[:500]
    confirm = body.get("confirm") is True
    by_id = {a["id"]: a for a in p.index_actions()}
    quiet = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL, "stdin": subprocess.DEVNULL, "start_new_session": True}
    if aid.startswith("route."):
        d = p.load_json(p.ROUTES, {}).get(aid[6:])
        if not d or not d.get("steps"):
            return 422, {"ok": False, "error": "That suggestion expired. Ask again."}
        acts = [by_id.get(s.get("id")) for s in d["steps"] if isinstance(s, dict)]
        if not acts or not all(_pal_phone_ok(a) for a in acts):
            return 422, {"ok": False, "error": "That needs something the phone can't run"}
        if any(a.get("danger") for a in acts) and not confirm:
            return 409, {"ok": False, "confirm": True, "error": "confirm first"}
        subprocess.Popen([sys.executable, PALETTE_PY, "run", aid[6:]], **quiet)
        return 200, {"ok": True, "label": d.get("label") or "Done"}
    a = by_id.get(aid)
    if not _pal_phone_ok(a):
        return 422, {"ok": False, "error": "That isn't in the laptop's palette any more"}
    if a.get("danger") and not confirm:
        return 409, {"ok": False, "confirm": True, "error": "confirm first"}
    a = _pal_fresh(a, p.live_states() if a.get("stateKey") else {})
    shown = ""
    if a.get("param"):
        r = p.resolve_step(a, {"arg": arg or ""}, {}, live=True)
        if r is None or r.get("args") == [""]:
            return 422, {"ok": False, "error": a["label"] + " needs a value"}
        args, shown = r["args"], r.get("show") or ""
    else:
        args = [a.get("arg", "")]
    p.record_use(aid)
    subprocess.Popen(["bash", "-c", a["cmd"], "_"] + args, **quiet)
    return 200, {"ok": True, "label": (a["label"] + " " + shown).strip()}


_post_core = Handler.do_POST


def _do_post(self):
    path = urlsplit(self.path).path
    if path not in ("/api/v1/palette", "/api/v1/palette/run"):
        return _post_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    who = self._who()
    if not self._bearer_ok():
        audit({"path": path[:80], "denied": "auth", "user": who[0], "ip": who[1]})
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if not self._input_on():
        return self._json(503, {"ok": False, "error": "the palette is off: phone touchpad & keyboard is turned off on the laptop"})
    raw, berr = self._body()
    if berr:
        return self._json(*berr)
    try:
        body = json.loads(raw or b"{}")
    except ValueError:
        return self._json(400, {"ok": False, "error": "invalid json"})
    if not isinstance(body, dict):
        return self._json(400, {"ok": False, "error": "object expected"})
    if path == "/api/v1/palette":
        ask = body.get("ask") is True
        if not self._limit("answer" if ask else "read"):
            return self._json(429, {"ok": False, "error": "rate limited"})
        try:
            return self._json(200, palette_query(str(body.get("q") or "")[:200], ask))
        except Exception as e:
            log(f"palette query failed: {type(e).__name__}: {e}")
            return self._json(500, {"ok": False, "error": "the palette failed on the laptop"})
    if not self._limit("act"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    try:
        code, out = palette_run(body)
    except Exception as e:
        log(f"palette run failed: {type(e).__name__}: {e}")
        code, out = 500, {"ok": False, "error": "the palette failed on the laptop"}
    if code != 409:
        audit({"action": "palette", "args": {"id": str(body.get("id") or "")[:80], "label": out.get("label", "")},
               "ok": bool(out.get("ok")), "user": who[0], "ip": who[1]},
              None if out.get("ok") else {"error": out.get("error", "")})
    if out.get("ok"):
        try:
            out["state"] = snapshot()
        except Exception:
            pass
    return self._json(code, out)


Handler.do_POST = _do_post


import qs_stream  # noqa: E402

STREAM_ENCODERS = ("auto", "va", "x264", "nvenc")
_get_core = Handler.do_GET
_history_desc_core = _history_desc


def _stream_on():
    s = settings()
    return s.get("qsRemoteEnabled", True) is not False and s.get("qsRemoteStreamEnabled", True) is not False


def _history_desc(e):
    if e.get("action") == "stream_session" and not e.get("denied"):
        return f"watched the screen · {_span(e.get('secs'))}"
    return _history_desc_core(e)


def _do_get(self):
    if urlsplit(self.path).path != "/api/v1/stream":
        return _get_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    who = self._who()
    if not self._bearer_ok():
        audit({"path": "/api/v1/stream", "denied": "auth", "user": who[0], "ip": who[1]})
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if not self._limit("act"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    if not _stream_on():
        return self._json(503, {"ok": False, "error": "screen streaming is turned off on the laptop"})
    key = self.headers.get("Sec-WebSocket-Key", "")
    if "websocket" not in (self.headers.get("Upgrade") or "").lower() or not key:
        return self._json(400, {"ok": False, "error": "websocket upgrade expected"})
    self.send_response(101)
    self.send_header("Upgrade", "websocket")
    self.send_header("Connection", "Upgrade")
    self.send_header("Sec-WebSocket-Accept", remote_input.accept_key(key))
    self.end_headers()
    self.wfile.flush()
    self.close_connection = True
    enc = str(settings().get("qsRemoteStreamEncoder", "auto"))
    started = time.time()
    summary = qs_stream.serve(self, _stream_on, remote_input.read_frame, remote_input.write_frame,
                              enc if enc in STREAM_ENCODERS else "auto")
    audit({"action": "stream_session", "secs": int(time.time() - started), **summary, "user": who[0], "ip": who[1]})


Handler.do_GET = _do_get


# ---------------------------------------------------------------- controls: timer, clipboard, maintenance

SCRIPTS = os.path.join(HOME, ".config/hypr/scripts")
CURVE_OFF = "/tmp/qs_brightness_curve_disabled"
WAKELOCK_PID = "/tmp/qs_wakelock.pid"
TIMER_FILE = "/tmp/qs_timer.json"
TIMER_CMD = "/tmp/qs_timer_cmd"
PERF_FILE = "/tmp/qs_perf.json"
CLIP_MAX = 64 * 1024
MAINTENANCE = {
    "orphans": (["bash", os.path.join(SCRIPTS, "kill_orphans.sh")], False),
    "journal": (["bash", os.path.join(BASE, "resident_actions.sh"), "vacuum_user_journal"], False),
    "reload": (["hyprctl", "reload"], False),
    "restart_bar": (["bash", os.path.join(BASE, "qsdev.sh"), "bar"], True),
    "restart_shell": (["bash", os.path.join(BASE, "qsdev.sh"), "main"], True),
    "clip_wipe": (["cliphist", "wipe"], True),
}


def _detached(cmd):
    subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)


def _wakelock_on():
    try:
        with open(WAKELOCK_PID) as f:
            os.kill(int(f.read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def _timer():
    t = _read_json(TIMER_FILE, {})
    if not isinstance(t, dict) or t.get("state") not in ("running", "paused"):
        return {"state": "idle", "remaining": 0, "duration": int((t or {}).get("durationSecs") or 0) if isinstance(t, dict) else 0}
    rem = max(0, int((t.get("endTs") or 0) / 1000 - time.time())) if t["state"] == "running" else int(t.get("remainingSecs") or 0)
    return {"state": t["state"], "remaining": rem, "duration": int(t.get("durationSecs") or 0)}


def _perf():
    p = _read_json(PERF_FILE, {})
    if not isinstance(p, dict) or time.time() - (p.get("ts") or 0) > 60:
        return {}
    return {"cpu": round(float(p.get("cpu_pct") or 0)), "orphans": int(p.get("orphans") or 0)}


_snapshot_controls = snapshot


def snapshot():
    s = _snapshot_controls()
    s["toggles"].update(auto_brightness=not os.path.exists(CURVE_OFF), lid_awake=_wakelock_on())
    s["timer"] = _timer()
    s["perf"] = _perf()
    return s


def a_brightness_curve(args):
    on = bool(args.get("on", os.path.exists(CURVE_OFF)))
    if on == os.path.exists(CURVE_OFF):
        return _ok(qs._sh(["bash", os.path.join(SCRIPTS, "toggle_brightness_curve.sh")]))
    return {"ok": True}


def a_lid_awake(args):
    on = bool(args.get("on", not _wakelock_on()))
    if on != _wakelock_on():
        _detached(["bash", os.path.join(SCRIPTS, "toggle_wakelock.sh")])
    return {"ok": True}


def a_timer(args):
    cmd = str(args.get("cmd", ""))
    if cmd == "start":
        mins = _int(args.get("minutes"))
        if mins is None or not 1 <= mins <= 1439:
            return {"ok": False, "error": "minutes must be 1-1439"}
        _detached(["bash", "-c", 'echo stop > "$1"; sleep 0.35; echo "set $2" > "$1"; sleep 0.35; echo start > "$1"',
                   "_", TIMER_CMD, str(mins)])
        return {"ok": True}
    if cmd not in ("pause", "resume", "stop"):
        return {"ok": False, "error": "cmd must be start, pause, resume or stop"}
    with open(TIMER_CMD, "w") as f:
        f.write(cmd + "\n")
    return {"ok": True}


def a_clipboard(args):
    action = str(args.get("action", ""))
    if action == "get":
        r = subprocess.run(["wl-paste", "-n", "-t", "text"], capture_output=True, timeout=5)
        if r.returncode != 0 or not r.stdout:
            return {"ok": False, "error": "nothing to copy: the laptop's clipboard is empty or not text"}
        text = r.stdout[:CLIP_MAX].decode("utf-8", "replace")
        return {"ok": True, "text": text}
    if action == "set":
        text = str(args.get("text", ""))[:CLIP_MAX]
        args["text"] = f"<{len(text)} chars>"
        if not text:
            return {"ok": False, "error": "nothing to paste"}
        subprocess.run(["wl-copy"], input=text, text=True, timeout=5)
        return {"ok": True}
    return {"ok": False, "error": "action must be get or set"}


def a_maintenance(args):
    task = MAINTENANCE.get(str(args.get("task", "")))
    if not task:
        return {"ok": False, "error": "task must be " + ", ".join(MAINTENANCE)}
    cmd, risky = task
    if risky and args.get("confirm") is not True:
        return {"ok": False, "error": "confirm first"}
    _detached(cmd)
    return {"ok": True}


for _name, _fn in (("brightness_curve", a_brightness_curve), ("lid_awake", a_lid_awake), ("timer", a_timer),
                   ("clipboard", a_clipboard), ("maintenance", a_maintenance)):
    ACTIONS.setdefault(_name, _fn)

_describe_controls = describe


def describe(name, args):
    on = "on" if args.get("on") else "off"
    task = {"orphans": "cleaned up leaked processes", "journal": "vacuumed the journal", "reload": "reloaded Hyprland",
            "restart_bar": "restarted the bar", "restart_shell": "restarted the shell", "clip_wipe": "cleared clipboard history"}
    extra = {
        "brightness_curve": "auto brightness " + on,
        "lid_awake": "stay on with lid closed " + on,
        "timer": f"timer {args.get('minutes')} min" if args.get("cmd") == "start" else f"timer {args.get('cmd', '')}",
        "clipboard": "clipboard sent to the phone" if args.get("action") == "get" else "pasted to the clipboard",
        "maintenance": task.get(str(args.get("task", "")), "maintenance"),
    }
    return extra.get(name) or _describe_controls(name, args)


# ---------------------------------------------------------------- phone feed: resident cards, app updates

CARDS_MAX = 30
UPDATE_REPO = "cybutr/fleet-app"
UPDATE_DIR = os.path.join(HOME, ".cache/qs-remote/updates")
UPDATE_TTL = 600
SHA_RE = re.compile(r"SHA-256:\s*`?([0-9a-f]{64})")
_update_cache = {"ts": 0.0, "data": None}
_update_mu = threading.Lock()
_get_feed_core = Handler.do_GET


def _cards_on():
    s = settings()
    return s.get("qsRemoteEnabled", True) is not False and s.get("qsRemoteCardsEnabled", True) is not False


def phone_cards(since):
    out = []
    for _, c in resident_card._queue_cards():
        if not isinstance(c, dict) or not isinstance(c.get("ts"), (int, float)) or c["ts"] < since:
            continue
        out.append({"id": str(c.get("id") or ""), "ts": c["ts"], "title": str(c.get("title") or "")[:120],
                    "body": str(c.get("body") or "")[:600], "urgency": str(c.get("urgency") or "normal"),
                    "source": str(c.get("source") or ""), "kind": str(c.get("kind") or ""),
                    "data": c.get("data") if isinstance(c.get("data"), dict) else {}})
    return out[-CARDS_MAX:]


def _gh(args, timeout=30):
    r = subprocess.run(["gh"] + args, capture_output=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode("utf-8", "replace").strip()[:200] or "gh failed")
    return r.stdout


def _update_repo():
    return str(settings().get("qsRemoteUpdateRepo") or UPDATE_REPO)


def latest_release():
    with _update_mu:
        if _update_cache["data"] and time.time() - _update_cache["ts"] < UPDATE_TTL:
            return _update_cache["data"]
        rel = json.loads(_gh(["api", f"repos/{_update_repo()}/releases/latest"]))
        apk = next((a for a in rel.get("assets") or [] if str(a.get("name", "")).endswith(".apk")), {})
        notes = str(rel.get("body") or "")
        sha = SHA_RE.search(notes)
        tag = str(rel.get("tag_name") or "")
        data = {"tag": tag, "version": tag.lstrip("v"), "name": str(rel.get("name") or tag),
                "notes": notes[:4000], "published": str(rel.get("published_at") or ""),
                "asset": os.path.basename(str(apk.get("name") or "")), "size": int(apk.get("size") or 0),
                "sha256": sha.group(1) if sha else ""}
        _update_cache.update(ts=time.time(), data=data)
        return data


def release_apk():
    rel = latest_release()
    if not rel["asset"]:
        raise RuntimeError("no apk in the latest release")
    path = os.path.join(UPDATE_DIR, rel["asset"])
    with _update_mu:
        if not (os.path.exists(path) and os.path.getsize(path) == rel["size"]):
            os.makedirs(UPDATE_DIR, exist_ok=True)
            for f in os.listdir(UPDATE_DIR):
                try:
                    os.unlink(os.path.join(UPDATE_DIR, f))
                except OSError:
                    pass
            _gh(["release", "download", rel["tag"], "-R", _update_repo(), "-p", rel["asset"], "-D", UPDATE_DIR, "--clobber"],
                timeout=300)
    return path, rel


def _do_get_feed(self):
    split = urlsplit(self.path)
    if split.path not in ("/api/v1/cards", "/api/v1/update", "/api/v1/update/apk"):
        return _get_feed_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    who = self._who()
    if not self._bearer_ok():
        audit({"path": split.path, "denied": "auth", "user": who[0], "ip": who[1]})
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if split.path == "/api/v1/cards":
        if not self._limit("read"):
            return self._json(429, {"ok": False, "error": "rate limited"})
        if not _cards_on():
            return self._json(503, {"ok": False, "error": "the card feed is turned off on the laptop"})
        try:
            since = float((parse_qs(split.query).get("since") or ["0"])[0])
        except ValueError:
            since = 0.0
        return self._json(200, {"ok": True, "now": time.time(), "cards": phone_cards(since)})
    if not self._limit("answer"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    try:
        if split.path == "/api/v1/update":
            return self._json(200, {"ok": True, **latest_release()})
        apk, rel = release_apk()
    except Exception as e:
        log(f"update lookup failed: {type(e).__name__}: {e}")
        return self._json(502, {"ok": False, "error": "the laptop couldn't reach the release on GitHub"})
    self.send_response(200)
    self.send_header("Content-Type", "application/vnd.android.package-archive")
    self.send_header("Content-Length", str(os.path.getsize(apk)))
    self.send_header("X-Release-Version", rel["version"])
    self.end_headers()
    if self.command == "HEAD":
        return
    with open(apk, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            self.wfile.write(chunk)
    audit({"action": "app_update", "args": {"version": rel["version"]}, "ok": True, "user": who[0], "ip": who[1]})


Handler.do_GET = _do_get_feed


# ---------------------------------------------------------------- claude code sessions

import qs_claude_sessions  # noqa: E402

_get_claude_core = Handler.do_GET


def _claude_on():
    s = settings()
    return s.get("qsRemoteEnabled", True) is not False and s.get("qsRemoteClaudeSessions", True) is not False


def _claude_titles():
    return settings().get("qsRemoteClaudeTitles", True) is not False


def _do_get_claude(self):
    path = urlsplit(self.path).path
    if path != "/api/v1/claude/sessions":
        return _get_claude_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    who = self._who()
    if not self._bearer_ok():
        audit({"path": path, "denied": "auth", "user": who[0], "ip": who[1]})
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if not self._limit("read"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    if not _claude_on():
        return self._json(503, {"ok": False, "error": "Claude sessions are hidden on the laptop"})
    try:
        return self._json(200, {"ok": True, **qs_claude_sessions.sessions(_claude_titles())})
    except Exception as e:
        log(f"claude sessions failed: {type(e).__name__}: {e}")
        return self._json(500, {"ok": False, "error": "couldn't read Claude sessions on the laptop"})


Handler.do_GET = _do_get_claude


def a_claude_focus(args):
    if not _claude_on():
        return {"ok": False, "error": "Claude sessions are hidden on the laptop"}
    pid = _int(args.get("pid"))
    if pid is None or pid <= 1:
        return {"ok": False, "error": "pid expected"}
    ok, why = qs_claude_sessions.focus(pid)
    return {"ok": True} if ok else {"ok": False, "error": why}


ACTIONS.setdefault("claude_focus", a_claude_focus)


def a_claude_send(args):
    if not _claude_on():
        return {"ok": False, "error": "Claude sessions are hidden on the laptop"}
    pid = _int(args.get("pid"))
    text = str(args.get("text") or "")
    submit = args.get("submit", True) is not False
    if pid is None or pid <= 1:
        return {"ok": False, "error": "pid expected"}
    if not text.strip():
        return {"ok": False, "error": "nothing to send"}
    if not remote_input.INJECTOR.available():
        return {"ok": False, "error": "ydotoold isn't running on the laptop"}
    ok, why = qs_claude_sessions.focus(pid)
    if not ok:
        return {"ok": False, "error": why}

    def go():
        time.sleep(0.15)
        remote_input.INJECTOR.type_text(text[:2000])
        if submit:
            time.sleep(0.08)
            remote_input.INJECTOR.key("enter")

    remote_input.INJECTOR.later(go)
    return {"ok": True}


ACTIONS.setdefault("claude_send", a_claude_send)

PRESENTER_FILE = "/tmp/qs_presenter_mode"


PRESENTER_COLORS = {"cyan", "peach", "pink", "green", "lavender", "yellow"}


def a_presenter_mode(args):
    on = bool(args.get("on"))
    mode = str(args.get("mode") or "border")
    if mode not in ("border", "spotlight", "both"):
        return {"ok": False, "error": "mode must be border, spotlight or both"}
    color = str(args.get("color") or "cyan")
    if color not in PRESENTER_COLORS:
        color = "cyan"
    size = _int(args.get("size")) or 180
    size = max(80, min(360, size))
    tmp = PRESENTER_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write(json.dumps({"on": on, "mode": mode, "color": color, "size": size}) + "\n")
    os.replace(tmp, PRESENTER_FILE)
    return {"ok": True, "on": on, "mode": mode, "color": color, "size": size}


ACTIONS.setdefault("presenter_mode", a_presenter_mode)

_describe_claude = describe


def describe(name, args):
    if name == "claude_focus":
        return "focused a Claude session"
    if name == "claude_send":
        return "sent text to a Claude session"
    if name == "presenter_mode":
        return ("turned on presenter mode" if args.get("on") else "turned off presenter mode")
    return _describe_claude(name, args)


# ---------------------------------------------------------------- claude code: chat history + diff

_get_claude2_core = Handler.do_GET


def _do_get_claude2(self):
    path = urlsplit(self.path).path
    if path not in ("/api/v1/claude/history", "/api/v1/claude/diff"):
        return _get_claude2_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    who = self._who()
    if not self._bearer_ok():
        audit({"path": path, "denied": "auth", "user": who[0], "ip": who[1]})
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if not self._limit("read"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    if not _claude_on():
        return self._json(503, {"ok": False, "error": "Claude sessions are hidden on the laptop"})
    q = parse_qs(urlsplit(self.path).query)
    pid = _int((q.get("pid") or [""])[0])
    if pid is None or pid <= 1:
        return self._json(400, {"ok": False, "error": "pid expected"})
    if path == "/api/v1/claude/history":
        limit = _int((q.get("limit") or ["40"])[0]) or 40
        try:
            turns, error = qs_claude_sessions.history_for_pid(pid, limit)
        except Exception as e:
            log(f"claude history failed: {type(e).__name__}: {e}")
            return self._json(500, {"ok": False, "error": "couldn't read that session's history on the laptop"})
        if error:
            return self._json(404, {"ok": False, "error": error})
        return self._json(200, {"ok": True, "turns": turns})
    try:
        return self._json(200, qs_claude_sessions.diff(pid))
    except Exception as e:
        log(f"claude diff failed: {type(e).__name__}: {e}")
        return self._json(500, {"ok": False, "error": "couldn't diff that session's working directory"})


Handler.do_GET = _do_get_claude2


# ---------------------------------------------------------------- phone-initiated push: clipboard, geo, sms, call

import resident_extras  # noqa: E402

PHONE_PUSH_KINDS = ("clipboard", "geo", "sms", "call", "notif")
_post_push_core = Handler.do_POST


def _push_clipboard(body):
    text = str(body.get("text") or "")[:CLIP_MAX]
    if not text:
        return {"ok": False, "error": "nothing to paste"}
    subprocess.run(["wl-copy"], input=text, text=True, timeout=5)
    return {"ok": True}


def _push_geo(body):
    state = str(body.get("state") or "")
    if state not in ("left", "returned"):
        return {"ok": False, "error": "state must be left or returned"}
    resident_extras.handle_geo_event(state)
    return {"ok": True}


def _push_sms(body):
    frm = str(body.get("from") or "unknown")[:80]
    preview = str(body.get("preview") or "")[:300]
    resident_card.emit(f"SMS from {frm}", preview, icon="󰍫", urgency="normal", source="phone_sms")
    return {"ok": True}


def _push_call(body):
    frm = str(body.get("from") or "unknown")[:80]
    kind = str(body.get("type") or "incoming")
    kind = kind if kind in ("missed", "incoming") else "incoming"
    title = f"Missed call: {frm}" if kind == "missed" else f"Incoming call: {frm}"
    resident_card.emit(title, "", icon="󰞋", urgency="normal", source="phone_call")
    return {"ok": True}


def _push_notif(body):
    nid = str(body.get("id") or "")[:120]
    if not nid:
        return {"ok": False, "error": "id required"}
    card_id = "phone-notif-" + hashlib.sha1(nid.encode()).hexdigest()[:12]
    if body.get("removed"):
        resident_card.dismiss(card_id)
        return {"ok": True}
    app = str(body.get("app") or "Phone")[:60]
    title = str(body.get("title") or "")[:140]
    text = str(body.get("text") or "")[:400]
    resident_card.emit(f"{app}: {title}" if title else app, text, icon="phone", urgency="low",
                        source="phone_notif", card_id=card_id)
    return {"ok": True}


PHONE_PUSH = {"clipboard": _push_clipboard, "geo": _push_geo, "sms": _push_sms, "call": _push_call, "notif": _push_notif}


def _do_post_push(self):
    path = urlsplit(self.path).path
    if path != "/api/v1/phone/push":
        return _post_push_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    who = self._who()
    if not self._bearer_ok():
        audit({"path": path, "denied": "auth", "user": who[0], "ip": who[1]})
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if not self._limit("act"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    raw, berr = self._body()
    if berr:
        return self._json(*berr)
    try:
        body = json.loads(raw or b"{}")
    except ValueError:
        return self._json(400, {"ok": False, "error": "invalid json"})
    if not isinstance(body, dict):
        return self._json(400, {"ok": False, "error": "object expected"})
    kind = str(body.get("kind") or "")
    fn = PHONE_PUSH.get(kind)
    if not fn:
        return self._json(400, {"ok": False, "error": "kind must be " + ", ".join(PHONE_PUSH_KINDS)})
    try:
        result = fn(body)
    except Exception as e:
        log(f"phone push ({kind}) failed: {type(e).__name__}: {e}")
        result = {"ok": False, "error": "the laptop failed to handle that"}
    audit({"action": "phone_push", "args": {"kind": kind}, "ok": bool(result.get("ok")), "user": who[0], "ip": who[1]},
          None if result.get("ok") else {"error": result.get("error", "")})
    return self._json(200 if result.get("ok") else 422, result)


Handler.do_POST = _do_post_push


# ---------------------------------------------------------------- live theme sync

COLORS_FILE = os.path.join(os.path.dirname(BASE), "qs_colors.json")
_get_theme_core = Handler.do_GET


def _theme_rev():
    try:
        return int(os.stat(COLORS_FILE).st_mtime)
    except OSError:
        return 0


def _do_get_theme(self):
    path = urlsplit(self.path).path
    if path != "/api/v1/theme":
        return _get_theme_core(self)
    err = self._gate()
    if err:
        return self._json(err[0], {"ok": False, "error": err[1]})
    if not self._bearer_ok():
        return self._json(401, {"ok": False, "error": "unauthorized"})
    if not self._limit("read"):
        return self._json(429, {"ok": False, "error": "rate limited"})
    try:
        with open(COLORS_FILE) as f:
            colors = json.load(f)
    except (OSError, ValueError):
        return self._json(503, {"ok": False, "error": "no matugen colors on the laptop yet"})
    return self._json(200, {"ok": True, "rev": _theme_rev(), "colors": colors})


Handler.do_GET = _do_get_theme

_snapshot_before_theme = snapshot


def snapshot():
    s = _snapshot_before_theme()
    s["themeRev"] = _theme_rev()
    return s


if __name__ == "__main__":
    main()
