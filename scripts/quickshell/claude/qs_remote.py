#!/usr/bin/env python3
"""qs-remote: the phone's way into the laptop.

Listens on 127.0.0.1 only; `tailscale serve` puts HTTPS in front of it and
adds the caller's Tailscale identity. Every request needs the bearer token
AND a Tailscale identity header (tagged nodes like the VPS or the Windows box
get none), and the whole thing can be switched off live with the
`qsRemoteEnabled` setting. Only the allowlisted actions below exist; nothing
takes a free-form command.

  python3 qs_remote.py          run the server (exec.conf does this)
  python3 qs_remote.py pair     print the setup link for the Fleet app
"""
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
from collections import deque
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
ART_MAX = 5 * 1024 * 1024
MAX_BODY = 4096
ACT_PER_MIN = 30
READ_PER_MIN = 120
WALL_RE = re.compile(r"^(random|[A-Za-z0-9][A-Za-z0-9._ -]{0,120}\.(jpe?g|png|webp))$", re.I)
HEX_RE = re.compile(r"#[0-9a-fA-F]{6}")
COOKIE = "qsr"

spec = importlib.util.spec_from_file_location("qs_mcp", os.path.join(BASE, "qs_mcp.py"))
qs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qs)
import resident_card  # noqa: E402


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

def _music():
    try:
        m = qs.t_music({})
    except Exception:
        m = {}
    if not isinstance(m, dict):
        m = {}
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
        "art": hashlib.sha1(art.encode()).hexdigest()[:12] if _art_path(art) else "",
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
        if not os.path.isfile(real) or os.path.getsize(real) > ART_MAX:
            return None
    except OSError:
        return None
    return real


def snapshot():
    sysinfo = {}
    try:
        sysinfo = (qs.t_system({}) or {}).get("system") or {}
    except Exception:
        pass
    bat = sysinfo.get("battery") or {}
    wifi = sysinfo.get("wifi") or {}
    bright = _run(["brightnessctl", "-m"]).split(",")
    profile = _run(["powerprofilesctl", "get"])
    try:
        night = bool(qs.t_night_light({"action": "status"}).get("on"))
    except Exception:
        night = False
    return {
        "host": os.uname().nodename,
        "ts": int(time.time()),
        "audio": {
            "volume": _int(_run(["pamixer", "--get-volume"]), 0),
            "muted": _run(["pamixer", "--get-mute"]) == "true",
            "mic_muted": _run(["pamixer", "--default-source", "--get-mute"]) == "true",
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
        "music": _music(),
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


ACTIONS = {
    "media": a_media, "volume": a_volume, "mute": a_mute, "mic": a_mic, "brightness": a_brightness,
    "night_light": a_night_light, "power_profile": a_power_profile, "wallpaper": a_wallpaper,
    "lock": a_lock, "notify": a_notify, "show_card": a_show_card, "open_widget": a_open_widget,
}
# Names the first version of the API used.
LEGACY = {"media_control": "media", "set_volume": "volume", "toggle_mute": "mute", "set_wallpaper": "wallpaper"}
SILENT = {"notify", "show_card"}


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
    }.get(name, lambda: name.replace("_", " "))()


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


def audit(entry):
    entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), **entry}
    with _audit_mu:
        try:
            if os.path.exists(AUDIT) and os.path.getsize(AUDIT) > AUDIT_MAX:
                os.replace(AUDIT, AUDIT + ".1")
            with open(AUDIT, "a") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError:
            pass


def run_action(name, args, who):
    fn = ACTIONS.get(LEGACY.get(name, name))
    name = LEGACY.get(name, name)
    try:
        result = fn(args)
    except Exception as e:
        log(f"{name} failed: {type(e).__name__}: {e}")
        result = {"ok": False, "error": "action failed"}
    ok = bool(result.get("ok"))
    audit({"action": name, "args": args, "ok": ok, "user": who[0], "ip": who[1]})
    if ok and name not in SILENT:
        try:
            resident_card.emit("Phone", describe(name, args), icon="󰄜", urgency="low",
                               hold_secs=6, source="qs-remote")
        except Exception:
            pass
    return result


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
        return self.server.limiter.allow(key, ACT_PER_MIN if kind == "act" else READ_PER_MIN)

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
        return self._json(404, {"ok": False, "error": "not found"})

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
        if not self._limit("act"):
            return self._json(429, {"ok": False, "error": "rate limited"})
        result = run_action(m.group(1), args, self._who())
        if path.startswith("/api/v1/"):
            try:
                result = {**result, "state": snapshot()}
            except Exception:
                pass
        return self._json(200 if result.get("ok") else 422, result)

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
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    srv.daemon_threads = True
    srv.token = load_token()
    srv.limiter = Limiter()
    log(f"listening on {HOST}:{PORT}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
