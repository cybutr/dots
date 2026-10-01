#!/usr/bin/env python3
import os, sys, json, time, re, hmac, fcntl, secrets, subprocess, threading, importlib.util
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs
from html import escape as _esc

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)

HOST = "127.0.0.1"
PORT = 8790
LOCK = "/tmp/qs_remote.lock"
STATE_DIR = os.path.expanduser("~/.local/state/qs-remote")
TOKEN_FILE = os.path.join(STATE_DIR, "token")
AUDIT = os.path.join(STATE_DIR, "audit.jsonl")
LOCK_SH = os.path.expanduser("~/.config/hypr/scripts/lock.sh")
MAX_BODY = 4096
ACT_PER_MIN = 10
READ_PER_MIN = 60
WALL_RE = re.compile(r"^(random|[A-Za-z0-9][A-Za-z0-9._ -]{0,120}\.(jpe?g|png|webp))$", re.I)

spec = importlib.util.spec_from_file_location("qs_mcp", os.path.join(BASE, "qs_mcp.py"))
qs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qs)
import resident_card


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


def _s(args, key, default="", cap=200):
    v = args.get(key, default)
    return str(v)[:cap] if v is not None else default


def a_get_system_state(_):
    return qs.t_system({})


def a_get_music(_):
    return qs.t_music({})


def a_media_control(args):
    return qs.t_media_control({"action": _s(args, "action", "play-pause", 20)})


def a_set_volume(args):
    try:
        pct = int(args.get("percent"))
    except (TypeError, ValueError):
        return {"ok": False, "error": "percent (0-100) required"}
    return qs.t_set_volume({"percent": max(0, min(100, pct))})


def a_toggle_mute(_):
    return qs.t_toggle_mute({})


def a_notify(args):
    urg = _s(args, "urgency", "normal", 10)
    return qs.t_notify({"title": _s(args, "title", "Remote", 80), "body": _s(args, "body", "", 500),
                        "urgency": urg if urg in ("low", "normal") else "normal"})


def a_show_card(args):
    title = _s(args, "title", "", 80).strip()
    if not title:
        return {"ok": False, "error": "title required"}
    urg = _s(args, "urgency", "normal", 10)
    resident_card.emit(title, _s(args, "body", "", 1000), icon="󰄜",
                       urgency=urg if urg in ("low", "normal") else "normal", source="qs-remote")
    return {"ok": True}


def a_open_widget(args):
    return qs.t_open_widget({"name": _s(args, "name", "", 40), "toggle": bool(args.get("toggle"))})


def a_set_wallpaper(args):
    name = _s(args, "name", "random", 130)
    if not WALL_RE.match(name) or ".." in name:
        return {"ok": False, "error": "name must be 'random' or a plain image filename"}
    return qs.t_set_wallpaper({"name": name})


def a_lock(_):
    subprocess.Popen(["bash", LOCK_SH], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    return {"ok": True}


READS = {"get_system_state": a_get_system_state, "get_music": a_get_music}
ACTIONS = {"media_control": a_media_control, "set_volume": a_set_volume, "toggle_mute": a_toggle_mute,
           "notify": a_notify, "show_card": a_show_card, "open_widget": a_open_widget,
           "set_wallpaper": a_set_wallpaper, "lock": a_lock}
SILENT = {"notify", "show_card"}


def describe(name, args):
    if name == "set_volume": return f"volume → {args.get('percent')}"
    if name == "media_control": return f"media {args.get('action', 'play-pause')}"
    if name == "open_widget": return f"opened {args.get('name')}"
    if name == "set_wallpaper": return f"wallpaper → {args.get('name', 'random')}"
    if name == "lock": return "locked the screen"
    return name.replace("_", " ")


class Limiter:
    def __init__(self):
        self.hits = {"act": deque(), "read": deque()}
        self.mu = threading.Lock()

    def allow(self, kind, limit):
        now = time.time()
        with self.mu:
            q = self.hits[kind]
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= limit:
                return False
            q.append(now)
            return True


def audit(entry):
    try:
        with open(AUDIT, "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


class Handler(BaseHTTPRequestHandler):
    server_version = "qs-remote"
    sys_version = ""

    def log_message(self, *a):
        pass

    def _reply(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        h = self.headers.get("Authorization", "")
        given = h[7:].strip() if h.lower().startswith("bearer ") else ""
        return bool(given) and hmac.compare_digest(given.encode(), self.server.token.encode())

    def _who(self):
        return (self.headers.get("Tailscale-User-Login") or "-",
                (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip())

    def _mobile_authed(self, q):
        given = (q.get("t") or [""])[0]
        return bool(given) and hmac.compare_digest(given.encode(), self.server.token.encode())

    def _mobile_page(self, q, html_err=None):
        tok = (q.get("t") or [""])[0]
        try:
            sysinfo = a_get_system_state({})
        except Exception:
            sysinfo = {}
        try:
            music = a_get_music({})
        except Exception:
            music = {}
        bat = sysinfo.get("battery", {}) if isinstance(sysinfo, dict) else {}
        wifi = sysinfo.get("wifi", {}) if isinstance(sysinfo, dict) else {}
        title = _esc(str(music.get("title", "")))
        artist = _esc(str(music.get("artist", "")))
        status = _esc(str(music.get("status", "")))
        def btn(label, action):
            return f'<a class="b" href="/m?t={tok}&amp;do={action}">{label}</a>'
        body = f"""<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
<title>qs-remote</title><style>
body{{background:#1e1e2e;color:#cdd6f4;font:16px system-ui;margin:0;padding:24px}}
.card{{background:#313244;border-radius:14px;padding:16px;margin-bottom:14px}}
.row{{display:flex;justify-content:space-between;color:#a6adc8;font-size:14px}}
h1{{font-size:18px;margin:0 0 16px}}
.b{{display:inline-block;background:#45475a;color:#cdd6f4;text-decoration:none;
    padding:12px 16px;border-radius:10px;margin:4px 6px 0 0;font-size:15px}}
.msg{{color:#a6e3a1;margin-bottom:10px}}
</style><h1>cheddos</h1>
{f'<div class="msg">{_esc(html_err)}</div>' if html_err else ''}
<div class="card">
<div class="row"><span>battery</span><span>{_esc(str(bat.get('percent','?')))}% · {_esc(str(bat.get('status','')))}</span></div>
<div class="row"><span>wifi</span><span>{_esc(str(wifi.get('ssid','')))}</span></div>
</div>
<div class="card">
<div>{title or '(nothing playing)'}</div>
<div class="row"><span>{artist}</span><span>{status}</span></div>
{btn('⏯ play/pause','playpause')}
</div>
<div class="card">
{btn('🔇 toggle mute','mute')}
{btn('🔒 lock','lock')}
</div>"""
        return body.encode()

    def do_GET(self):
        parts = urlsplit(self.path)
        if parts.path == "/m":
            q = parse_qs(parts.query)
            if not self._mobile_authed(q):
                self.send_response(401)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"unauthorized")
                return
            if not self.server.limiter.allow("read", READ_PER_MIN):
                self.send_response(429)
                self.end_headers()
                return
            do = (q.get("do") or [None])[0]
            msg = None
            ok = True
            try:
                if do == "playpause":
                    a_media_control({"action": "play-pause"}); msg = "toggled playback"
                elif do == "mute":
                    a_toggle_mute({}); msg = "toggled mute"
                elif do == "lock":
                    a_lock({}); msg = "locking…"
            except Exception:
                ok = False
                msg = "that action failed, try again"
            if do:
                user, ip = self._who()
                audit({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "action": f"mobile:{do}", "ok": ok, "user": user, "ip": ip})
            body = self._mobile_page(q, msg)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        if not self._authed():
            return self._reply(401, {"ok": False, "error": "unauthorized"})
        if self.path == "/actions":
            return self._reply(200, {"reads": sorted(READS), "actions": sorted(ACTIONS)})
        if self.path == "/state":
            if not self.server.limiter.allow("read", READ_PER_MIN):
                return self._reply(429, {"ok": False, "error": "rate limited"})
            return self._reply(200, {"system": a_get_system_state({}), "music": a_get_music({})})
        return self._reply(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        if not self._authed():
            user, ip = self._who()
            audit({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "path": self.path[:80], "denied": "auth", "user": user, "ip": ip})
            return self._reply(401, {"ok": False, "error": "unauthorized"})
        if not self.path.startswith("/action/"):
            return self._reply(404, {"ok": False, "error": "not found"})
        name = self.path[len("/action/"):]
        fn = READS.get(name) or ACTIONS.get(name)
        if not fn:
            return self._reply(404, {"ok": False, "error": "action not allowed"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = -1
        if n < 0 or n > MAX_BODY:
            return self._reply(413, {"ok": False, "error": "body too large"})
        try:
            args = json.loads(self.rfile.read(n) or b"{}") if n else {}
        except ValueError:
            return self._reply(400, {"ok": False, "error": "invalid json"})
        if not isinstance(args, dict):
            return self._reply(400, {"ok": False, "error": "object expected"})
        is_act = name in ACTIONS
        if not self.server.limiter.allow("act" if is_act else "read", ACT_PER_MIN if is_act else READ_PER_MIN):
            return self._reply(429, {"ok": False, "error": "rate limited"})
        try:
            result = fn(args)
        except Exception as e:
            result = {"ok": False, "error": f"{type(e).__name__}: {e}"[:300]}
        if is_act:
            user, ip = self._who()
            ok = result.get("ok") if isinstance(result, dict) else None
            audit({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "action": name, "args": args, "ok": ok, "user": user, "ip": ip})
            if name not in SILENT and ok is not False:
                try:
                    resident_card.emit("Remote", describe(name, args), icon="󰄜", urgency="low",
                                       hold_secs=8, source="qs-remote")
                except Exception:
                    pass
        return self._reply(200, result if isinstance(result, dict) else {"result": result})


def main():
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
