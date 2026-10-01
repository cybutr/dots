#!/usr/bin/env python3
import base64
import concurrent.futures
import hashlib
import importlib.util
import json
import os
import re
import shlex
import shutil
import sqlite3
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.abspath(__file__))
QS = os.path.dirname(HERE)
SELF = os.path.abspath(__file__)
CACHE_DIR = os.path.join(HOME, ".cache/quickshell/palette")
FAV_DIR = os.path.join(CACHE_DIR, "favicons")
SPOTIFY_PLAYLISTS = os.path.join(CACHE_DIR, "spotify_playlists.json")
OPEN_ON_WS = os.path.join(HOME, ".config/hypr/scripts/open_on_workspace.sh")
SEARCH_URL = "https://www.google.com/search?q="
CMD = "python3 " + json.dumps(SELF)

WEB_SCHEMES = ("http://", "https://", "file://", "ftp://")
VSCODES = [
    (os.path.join(HOME, ".var/app/com.visualstudio.code/config/Code"), "/var/lib/flatpak/exports/bin/com.visualstudio.code",
     "flatpak run --command=code com.visualstudio.code --force-renderer-accessibility", "com.visualstudio.code", "VS Code"),
    (os.path.join(HOME, ".config/Code"), "code", "code", "visual-studio-code", "VS Code"),
    (os.path.join(HOME, ".config/Code - OSS"), "code-oss", "code-oss", "code-oss", "Code OSS"),
    (os.path.join(HOME, ".config/VSCodium"), "codium", "codium", "vscodium", "VSCodium"),
]
DO_HOME = os.path.join(HOME, ".config/do")
DO_SCRIPT = os.path.join(DO_HOME, "do.py")
DO_PY = os.path.join(DO_HOME, ".venv/bin/python") if os.access(os.path.join(DO_HOME, ".venv/bin/python"), os.X_OK) else "python3"
LANG_GLYPH = {"rust": 0xF1617, "csharp": 0xF031B, "fsharp": 0xF031B, "python": 0xF0320, "go": 0xF07D3, "node": 0xF0399,
              "javascript": 0xF031E, "typescript": 0xF06E6, "react": 0xF0708, "web": 0xF031D, "c": 0xF0671, "cpp": 0xF0672,
              "make": 0xF1322}
EXT_LANG = {".py": "python", ".rs": "rust", ".cs": "csharp", ".fs": "fsharp", ".go": "go", ".js": "javascript", ".mjs": "javascript",
            ".jsx": "react", ".tsx": "react", ".ts": "typescript", ".html": "web", ".c": "c", ".h": "c", ".cpp": "cpp", ".hpp": "cpp"}
RUN_HOW = {"rust": "cargo run", "csharp": "dotnet run", "fsharp": "dotnet run", "python": "uv run", "go": "go run .",
           "c": "make && ./app", "cpp": "cmake build and run", "node": "node / npm run dev", "web": "index.html in the browser"}
CODE_CLASSES = {"code", "code-oss", "code-url-handler", "vscodium", "com.visualstudio.code"}
NUM_WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}
NEW_WORDS = ("new", "empty", "fresh", "free", "blank", "next", "another", "clean")

_mcp = None


def mcp():
    global _mcp
    if _mcp is None:
        path = os.path.join(QS, "claude/qs_mcp.py")
        spec = importlib.util.spec_from_file_location("qs_mcp", path)
        _mcp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_mcp)
    return _mcp


def sh(cmd, timeout=2):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def hypr_clients():
    try:
        return json.loads(sh(["hyprctl", "clients", "-j"]) or "[]")
    except ValueError:
        return []


def focus(addr):
    sh(["hyprctl", "dispatch", "focuswindow", "address:" + addr])


def latest(clients, pred):
    hits = sorted((c for c in clients if pred(c)), key=lambda c: c.get("focusHistoryID", 99))
    return hits[0] if hits else None


def host_of(url):
    h = urllib.parse.urlparse(url).hostname or ""
    return h[4:] if h.startswith("www.") else h


def url_words(url):
    u = urllib.parse.urlparse(url)
    return " ".join(w for w in re.split(r"[^a-z0-9]+", ((u.hostname or "") + " " + u.path[:80]).lower()) if len(w) > 1)


def fav_path(url):
    key = hashlib.sha1(url.encode()).hexdigest()[:16]
    for ext in (".png", ".ico", ".svg", ".jpg", ".gif", ".webp"):
        p = os.path.join(FAV_DIR, key + ext)
        if os.path.exists(p):
            return p, key
    return "", key


def favicon(url, pending):
    if not url:
        return ""
    path, key = fav_path(url)
    if path:
        return path
    if url.startswith("data:"):
        m = re.match(r"data:image/([a-z0-9.+-]+);base64,(.*)", url, re.S)
        if not m:
            return ""
        ext = {"svg+xml": ".svg", "x-icon": ".ico", "vnd.microsoft.icon": ".ico", "jpeg": ".jpg"}.get(m.group(1), "." + m.group(1))
        try:
            data = base64.b64decode(m.group(2))
        except ValueError:
            return ""
        return write_fav(key, ext, data)
    if url.startswith(("http://", "https://")):
        pending.append(url)
    return ""


def write_fav(key, ext, data):
    os.makedirs(FAV_DIR, exist_ok=True)
    p = os.path.join(FAV_DIR, key + ext)
    with open(p + ".tmp", "wb") as f:
        f.write(data)
    os.replace(p + ".tmp", p)
    return p


def fetch_favs(urls):
    def one(url):
        _, key = fav_path(url)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=5) as r:
                data, ctype = r.read(200000), r.headers.get("Content-Type", "")
        except Exception:
            return
        if not data:
            return
        ext = ".svg" if "svg" in ctype or data.lstrip()[:5] in (b"<svg ", b"<?xml") else ".png" if data[:4] == b"\x89PNG" \
            else ".jpg" if data[:2] == b"\xff\xd8" else ".gif" if data[:3] == b"GIF" else ".webp" if data[8:12] == b"WEBP" else ".ico"
        write_fav(key, ext, data)
    with concurrent.futures.ThreadPoolExecutor(6) as ex:
        list(ex.map(one, urls[:40]))


def spawn_fav_fetch(pending):
    if pending:
        subprocess.Popen([sys.executable, SELF, "favicons", json.dumps(sorted(set(pending)))],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def bounded(fn, secs, default):
    box = []
    th = threading.Thread(target=lambda: box.append(fn()), daemon=True)
    th.start()
    th.join(secs)
    return box[0] if box else default


def cdp_pages():
    try:
        return [t for t in json.loads(mcp()._cdp("/json/list")) if t.get("type") == "page"]
    except Exception:
        return None


def vivaldi_tabs(pending):
    # t_browser_tabs blocks for its 5s urllib timeout when Vivaldi's CDP stalls; the index build can't wait that long
    pages = bounded(cdp_pages, 1.2, None)
    if not pages:
        return []
    favs = {t["id"]: t.get("faviconUrl", "") for t in pages}
    out = []
    for t in pages:
        url, title = t["url"], t["title"].strip()
        if not url.startswith(WEB_SCHEMES):
            continue
        host = host_of(url)
        out.append({
            "id": "tab.v." + t["id"], "label": (title or url)[:90], "hint": "Vivaldi · " + (host or url[:60]),
            "cat": "tab", "icon": chr(0xF059F), "image": favicon(favs.get(t["id"], ""), pending),
            "url": url, "browser": "Vivaldi",
            "keywords": "tab browser vivaldi switch web page site " + url_words(url),
            "cmd": CMD + ' tab "$1"', "arg": t["id"], "verb": "Switch to",
        })
    return out


def lz4_block(src):
    dst, i, n = bytearray(), 0, len(src)
    while i < n:
        tok = src[i]
        i += 1
        lit = tok >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        dst += src[i:i + lit]
        i += lit
        if i >= n:
            break
        off = src[i] | src[i + 1] << 8
        i += 2
        ml = tok & 15
        if ml == 15:
            while True:
                b = src[i]
                i += 1
                ml += b
                if b != 255:
                    break
        ml += 4
        st = len(dst) - off
        if off >= ml:
            dst += dst[st:st + ml]
        else:
            for k in range(ml):
                dst.append(dst[st + k])
    return bytes(dst)


def firefox_session():
    base = None
    for root in (os.path.join(HOME, ".config/mozilla/firefox"), os.path.join(HOME, ".mozilla/firefox")):
        ini = os.path.join(root, "installs.ini")
        try:
            m = re.search(r"^Default=(.+)$", open(ini).read(), re.M)
        except OSError:
            continue
        if m:
            base = os.path.join(root, m.group(1).strip())
            break
    if not base:
        return None
    for name in ("sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4"):
        try:
            raw = open(os.path.join(base, name), "rb").read()
        except OSError:
            continue
        if raw[:8] == b"mozLz40\0":
            try:
                return json.loads(lz4_block(raw[12:]))
            except (ValueError, IndexError):
                return None
    return None


def firefox_tabs(pending):
    if not sh(["pgrep", "-x", "firefox"]):
        return []
    d = firefox_session()
    if not d:
        return []
    out = []
    for wi, w in enumerate(d.get("windows") or []):
        sel = w.get("selected", 1)
        for ti, t in enumerate(w.get("tabs") or []):
            ents = t.get("entries") or []
            if not ents:
                continue
            e = ents[max(0, min(len(ents), t.get("index", len(ents))) - 1)]
            url, title = e.get("url", ""), (e.get("title") or "").strip()
            if not url.startswith(WEB_SCHEMES):
                continue
            active = ti + 1 == sel
            host = host_of(url)
            out.append({
                "id": "tab.f.%d.%d" % (wi, ti), "label": (title or url)[:90],
                "hint": "Firefox · " + (host or url[:60]) + ("" if active else " · opens a copy"),
                "cat": "tab", "icon": chr(0xF0239), "image": favicon(t.get("image") or "", pending),
                "url": url, "browser": "Firefox",
                "keywords": "tab browser firefox switch web page site " + url_words(url),
                "cmd": CMD + ' fftab "$1" "$2"', "args": [url, title if active else ""], "verb": "Switch to" if active else "Open",
            })
    return out


def tab_actions(excluded=lambda cat: False):
    if excluded("tab"):
        return []
    pending = []
    out = []
    for fn in (vivaldi_tabs, firefox_tabs):
        try:
            out += fn(pending)
        except Exception:
            pass
    spawn_fav_fetch(pending)
    return out


def vscode_actions():
    seen, rows = set(), []
    for base, probe, launch, icon, name in VSCODES:
        store = os.path.join(base, "User/workspaceStorage")
        if not os.path.isdir(store) or not (os.path.exists(probe) if probe.startswith("/") else shutil.which(probe)):
            continue
        for d in os.listdir(store):
            try:
                ws = json.load(open(os.path.join(store, d, "workspace.json")))
            except (OSError, ValueError):
                continue
            uri = ws.get("folder") or ws.get("workspace") or ""
            if not uri.startswith("file://"):
                continue
            path = urllib.parse.unquote(uri[7:])
            if path in seen or not os.path.exists(path):
                continue
            seen.add(path)
            db = os.path.join(store, d, "state.vscdb")
            t = os.path.getmtime(db if os.path.exists(db) else os.path.join(store, d))
            rows.append((t, path, launch, icon, name))
    rows.sort(key=lambda r: -r[0])
    out = []
    for t, path, launch, icon, name in rows[:40]:
        short = path.replace(HOME, "~", 1)
        label = os.path.basename(path.rstrip("/"))
        if label.endswith(".code-workspace"):
            label = label[:-15]
        out.append({
            "id": "code." + path, "label": label or short, "hint": name + " · " + short + " · " + ago(t),
            "cat": "code", "icon": chr(0xF0A1E), "image": icon, "path": short, "when": ago(t),
            "keywords": "vscode code editor project folder workspace recent open " + " ".join(re.split(r"[^a-z0-9]+", short.lower())),
            "cmd": 'hyprctl dispatch exec -- "' + launch + ' $(printf %q "$1")" >/dev/null', "arg": path, "verb": "Open",
        })
    return out


def ago(t):
    s = max(0, time.time() - t)
    if s < 3600:
        return "%dm ago" % max(1, s // 60)
    if s < 86400:
        return "%dh ago" % (s // 3600)
    return "%dd ago" % (s // 86400)


def dolib():
    if DO_HOME not in sys.path:
        sys.path.insert(0, DO_HOME)
    import dolib.ai
    import dolib.bus
    import dolib.config
    import dolib.detect
    import dolib.launcher
    import dolib.projects
    import dolib.store
    return dolib


def do_config():
    import tomllib
    d = dolib()
    with open(d.config.CONFIG_PATH, "rb") as f:
        return d.config.Config(tomllib.load(f))


def do_db(sql, params=()):
    path = dolib().config.STATE_PATH
    if not os.path.exists(path):
        return []
    # read-only: dolib.store's own connections run the schema script and commit on every call
    conn = sqlite3.connect("file:" + urllib.parse.quote(path) + "?mode=ro", uri=True, timeout=0.5)
    conn.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in conn.execute(sql, params)]
    finally:
        conn.close()


def guess_lang(path):
    counts = {}
    try:
        for e in os.listdir(path):
            lang = EXT_LANG.get(os.path.splitext(e)[1].lower())
            if lang:
                counts[lang] = counts.get(lang, 0) + 1
    except OSError:
        return ""
    return max(counts, key=counts.get) if counts else ""


def looks_like_project(path, t, d):
    return bool(d.detect.detect_lang(path) or (t.manifests and d.detect.matches_type(path, t.manifests)) or guess_lang(path))


def short_path(p):
    return p.replace(HOME, "~", 1)


def project_row(p, heat):
    d = dolib()
    ptype, name, path = p["type"], p["name"], p["path"]
    sc = ptype == "@"
    lang = p.get("lang") or d.detect.detect_lang(path) or ""
    show = (lang if lang != "make" else "") or guess_lang(path) or lang
    last, opens, fr = p.get("last_access") or 0, p.get("access_count") or 0, round(p.get("frecency") or 0, 1)
    tags = [t.strip() for t in (p.get("tags") or "").split(",") if t.strip()]
    desc = p.get("description") or ""
    runs = lang if lang in RUN_HOW and (lang != "python" or os.path.exists(os.path.join(path, "main.py"))) else ""
    stale = bool(p.get("stale"))
    pid = "project.sc." + name if sc else "project.%s.%s" % (ptype, os.path.basename(os.path.dirname(path)) + "/" + name if stale else name)
    words = " ".join(w for w in re.split(r"[^a-z0-9]+", short_path(path).lower()) if len(w) > 1)
    row = {
        "id": pid, "label": name,
        "hint": " · ".join(x for x in ("shortcut" if sc else ptype, short_path(path), ago(last) if last else "never opened") if x),
        "cat": "project", "icon": chr(LANG_GLYPH.get(show, 0xF0770)),
        "keywords": " ".join(x for x in ("project projects code work do editor folder", "shortcut" if sc else ptype, show, " ".join(tags), desc.lower(),
                                         words, "run" if runs else "", "recent working on" if last else "") if x),
        "cmd": CMD + ' project open "$1" "$2" "$3"', "args": [ptype, name, path], "verb": "Open",
        "bias": round(min(4.0, fr * 0.5), 2),
        "project": {"type": "" if sc else ptype, "name": name, "path": path, "short": short_path(path), "lang": show, "runs": runs,
                    "tags": tags, "desc": desc, "opens": opens, "last": int(last), "frecency": fr, "heat": heat, "shortcut": sc, "stale": stale},
    }
    if runs:
        row["alt"] = {"verb": "Open in browser" if runs == "web" else "Run", "how": RUN_HOW[runs],
                      "cmd": CMD + ' project run "$1" "$2" "$3"', "args": [ptype, name, path]}
    return row


def project_actions():
    d = dolib()
    cfg = do_config()
    roots = {n: t.resolve_root() for n, t in cfg.types.items()}
    found, seen = [], set()
    for r in do_db(d.store._FRECENCY_SQL, {"now": time.time()}):
        t = cfg.type(r["type"])
        if not t or r["path"] in seen or not os.path.isdir(r["path"]):
            continue
        if not r.get("access_count") and not looks_like_project(r["path"], t, d):
            continue
        r["stale"] = r["path"] != os.path.join(roots[r["type"]], r["name"])
        seen.add(r["path"])
        found.append(r)
    for n, t in cfg.types.items():
        for name in d.projects.list_names(t):
            path = os.path.join(roots[n], name)
            if path not in seen and looks_like_project(path, t, d):
                seen.add(path)
                found.append({"type": n, "name": name, "path": path})
    real = {os.path.realpath(p) for p in seen}
    for s in do_db("SELECT name, path FROM shortcuts ORDER BY name"):
        path = os.path.expanduser(s["path"])
        if os.path.isdir(path) and os.path.realpath(path) not in real:
            real.add(os.path.realpath(path))
            found.append({"type": "@", "name": s["name"], "path": path})
    top = max([p.get("frecency") or 0 for p in found] + [1])
    out = [project_row(p, round((p.get("frecency") or 0) / top, 3)) for p in found]

    for n, t in cfg.types.items():
        root = roots[n]
        flang = EXT_LANG.get(os.path.splitext(t.focus or "")[1].lower(), "")
        kw = "new create scaffold start init make project do " + n + " " + flang
        if t.supports_naming:
            out.append({
                "id": "project.new." + n, "label": "New %s project" % n, "hint": "In %s, name it or describe the idea" % short_path(root),
                "cat": "project", "icon": chr(0xF0257), "keywords": kw, "bias": -2, "cmd": CMD + ' project new %s "$1"' % n,
                "param": {"kind": "text", "required": False, "hint": "a name, or the idea in a few words"}, "verb": "Create",
                "project": {"type": n, "new": True, "root": short_path(root), "lang": flang, "naming": True},
            })
        else:
            nxt = t.prefix + str(d.projects._next_number(root, t.prefix))
            out.append({
                "id": "project.new." + n, "label": "New %s project" % n, "hint": "Creates %s in %s" % (nxt, short_path(root)),
                "cat": "project", "icon": chr(0xF0257), "keywords": kw + " next " + t.prefix.lower(), "bias": -2, "cmd": CMD + " project new " + n,
                "verb": "Create " + nxt, "project": {"type": n, "new": True, "root": short_path(root), "lang": flang, "next": nxt},
            })
            latest = d.projects.latest(t)
            if latest:
                ln = os.path.basename(latest)
                out.append({
                    "id": "project.last." + n, "label": "Latest %s project" % n, "hint": "%s in %s" % (ln, short_path(root)),
                    "cat": "project", "icon": chr(LANG_GLYPH.get(flang, 0xF0770)), "keywords": "latest last newest current recent open " + n + " " + flang,
                    "cmd": CMD + ' project open "$1" "$2" "$3"', "args": [n, ln, latest], "verb": "Open " + ln, "bias": 1,
                    "project": {"type": n, "name": ln, "path": latest, "short": short_path(latest), "lang": flang, "latest": True},
                })
    out.append({
        "id": "project.scan", "label": "Rescan projects", "hint": "Index every folder under the do type roots",
        "cat": "project", "icon": chr(0xF0450), "keywords": "scan rescan index refresh reindex projects do", "bias": -10,
        "cmd": json.dumps(DO_PY) + " " + json.dumps(DO_SCRIPT) + " scan >/dev/null 2>&1", "verb": "Scan",
    })
    return out


def notify(title, body="", urgent=False):
    subprocess.Popen(["notify-send", "-a", "do", "-i", "folder-development"] + (["-u", "critical"] if urgent else []) + [title, body],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def do_cli(*args, timeout=90):
    try:
        r = subprocess.run([DO_PY, DO_SCRIPT] + list(args), capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 0, ""
    lines = (r.stderr.strip() or r.stdout.strip()).splitlines()
    return r.returncode, lines[-1] if lines else ""


def editor_window(path):
    base = os.path.basename(path.rstrip("/"))
    return latest(hypr_clients(), lambda c: (c.get("class") or "").lower() in CODE_CLASSES
                  and base in [s.strip() for s in (c.get("title") or "").split(" - ")])


def log_access(ptype, name, path):
    d = dolib()
    try:
        d.store.log_access(ptype, name, path)
        d.bus.publish(do_config())
    except Exception:
        pass


def project_open(ptype, name, path):
    win = editor_window(path)
    if win:
        focus(win["address"])
        if ptype != "@":
            log_access(ptype, name, path)
        return 0
    cfg = do_config()
    t = cfg.type(ptype)
    if ptype == "@" or (t and os.path.join(t.resolve_root(), name) == path):
        rc, err = do_cli("open", name) if ptype == "@" else do_cli("open", ptype, name)
        if rc:
            notify("Couldn't open " + name, err, True)
        return rc
    if not os.path.isdir(path):
        notify("Couldn't open " + name, short_path(path) + " is gone", True)
        return 1
    # an older academic-year folder: `do open <type> <name>` only resolves against the current root
    log_access(ptype, name, path)
    dolib().launcher.open_editor(path, cfg.launcher, t.focus if t else None)
    return 0


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40] or "project"


def project_new(ptype, text=""):
    d = dolib()
    cfg = do_config()
    t = cfg.type(ptype)
    if not t:
        return 2
    text, name, by = text.strip(), "", ""
    if text and t.supports_naming:
        if re.search(r"\s", text):
            # named here rather than by `do new -m`, whose AI path crashes on an empty reply and falls back to a name with spaces
            try:
                name = d.ai.name_for(cfg.ai, text, ptype) if d.ai.available(cfg.ai) else ""
            except Exception:
                name = ""
            by = "Claude named it " if name else ""
            name = name or slug(text)
        else:
            name = text
    before = set(d.projects.list_names(t))
    rc, err = do_cli("new", ptype, *(["-m", name] if name else []), timeout=300)
    made = sorted(set(d.projects.list_names(t)) - before)
    if made:
        notify("Created " + made[0], (by + "· " if by else "") + short_path(os.path.join(t.resolve_root(), made[0])))
        return 0
    notify("Couldn't create the %s project" % ptype, err, True)
    return rc or 1


def project_run(ptype, name, path):
    d = dolib()
    rows = do_db("SELECT lang FROM projects WHERE path = ?", (path,))
    lang = (rows[0]["lang"] if rows else "") or d.detect.detect_lang(path) or ""
    if lang not in RUN_HOW:
        notify("Don't know how to run " + name, "no runnable project detected in " + short_path(path), True)
        return 1
    t = do_config().type(ptype)
    cli = bool(t) and os.path.join(t.resolve_root(), name) == path
    if lang == "web":
        index = os.path.join(path, "index.html")
        if not os.path.exists(index):
            notify("Nothing to open in " + name, "no index.html", True)
            return 1
        if ptype != "@":
            log_access(ptype, name, path)
        subprocess.Popen(["xdg-open", index], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return 0
    if cli:
        inner = [DO_PY, DO_SCRIPT, "run", ptype, name]
    else:
        if ptype != "@":
            log_access(ptype, name, path)
        inner = [DO_PY, "-c", "import sys;sys.path.insert(0,sys.argv[1]);from dolib.launcher import run_project;run_project(sys.argv[2],sys.argv[3])",
                 DO_HOME, path, lang]
    subprocess.Popen(["kitty", "--hold", "--title", "do run · " + name, "--directory", path] + inner,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return 0


def readme_line(path):
    for f in sorted(os.listdir(path)):
        if not f.lower().startswith("readme"):
            continue
        try:
            with open(os.path.join(path, f), errors="replace") as fh:
                for line in fh.read(8000).splitlines():
                    line = re.sub(r"[*_`>#]|!?\[([^\]]*)\]\([^)]*\)", r"\1", line).strip()
                    if len(line) > 3 and not line.startswith(("<", "=", "-", "|")):
                        return line[:160]
        except OSError:
            pass
    return ""


def project_peek(path):
    out = {"path": path}
    try:
        entries = [e for e in os.listdir(path) if not e.startswith(".")]
    except OSError:
        out["gone"] = True
        return out
    out["files"] = len(entries)
    try:
        out["modified"] = ago(max(os.path.getmtime(os.path.join(path, e)) for e in entries + ["."]))
    except (OSError, ValueError):
        pass
    out["readme"] = readme_line(path)
    top = sh(["git", "-C", path, "rev-parse", "--show-toplevel"], 1)
    if top and top != HOME:
        out["git"] = True
        out["repoRoot"] = short_path(top) if top != path else ""
        out["branch"] = sh(["git", "-C", path, "branch", "--show-current"], 1) or sh(["git", "-C", path, "rev-parse", "--short", "HEAD"], 1)
        st = sh(["git", "-C", path, "status", "--porcelain", "--untracked-files=normal", "."], 1.5)
        out["dirty"] = len(st.splitlines()) if st else 0
        log = sh(["git", "-C", path, "log", "-1", "--format=%s%x1f%ct", "--", "."], 1)
        if "\x1f" in log:
            msg, ct = log.split("\x1f", 1)
            out["commit"] = msg[:100]
            out["commitAgo"] = ago(int(ct)) if ct.isdigit() else ""
    return out


def spotify():
    sys.path.insert(0, HERE)
    import spotify_peek
    return spotify_peek


def sp_request(method, path, body=None, params=None):
    sp = spotify()
    url = sp.spotify_fetch.API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + sp.token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


def pick_image(imgs, want=300):
    imgs = [i for i in imgs or [] if i and i.get("url")]
    if not imgs:
        return ""
    sized = [i for i in imgs if (i.get("width") or 0) >= want]
    return (min(sized, key=lambda i: i["width"]) if sized else imgs[0])["url"]


def my_playlists():
    try:
        c = json.load(open(SPOTIFY_PLAYLISTS))
        if time.time() - c.get("ts", 0) < 600:
            return c["items"]
    except (OSError, ValueError, KeyError):
        pass
    items, path = [], "/me/playlists"
    params = {"limit": 50}
    for _ in range(4):
        d = sp_request("GET", path, params=params)
        items += [p for p in d.get("items") or [] if p]
        nxt = d.get("next")
        if not nxt:
            break
        params = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(nxt).query))
    slim = [{"name": p.get("name", ""), "uri": p.get("uri", ""), "id": p.get("id", ""),
             "owner": (p.get("owner") or {}).get("display_name", ""), "tracks": (p.get("tracks") or {}).get("total", 0),
             "img": pick_image(p.get("images"))} for p in items]
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(SPOTIFY_PLAYLISTS + ".tmp", "w") as f:
        json.dump({"ts": int(time.time()), "items": slim}, f)
    os.replace(SPOTIFY_PLAYLISTS + ".tmp", SPOTIFY_PLAYLISTS)
    return slim


SP_GLYPH = {"track": 0xF075A, "album": 0xF0025, "artist": 0xF0803, "playlist": 0xF0CB8}


def sp_hit(kind, name, sub, uri, img, mine=False):
    return {
        "id": "spotifyhit." + uri, "label": name or "(untitled)", "hint": kind.capitalize() + (" · " + sub if sub else ""),
        "cat": "spotify", "icon": chr(SP_GLYPH.get(kind, 0xF04C7)), "image": img, "kind": kind, "sub": sub,
        "mine": mine, "keywords": "", "verb": "Play", "cmd": CMD + ' play "$1"', "args": [uri],
    }


def spotify_search(q, limit=10):
    q = q.strip()
    out = []
    ql = q.lower()
    try:
        for p in my_playlists():
            if ql in p["name"].lower():
                out.append(sp_hit("playlist", p["name"], "yours, %d tracks" % p["tracks"], p["uri"], p["img"], True))
    except Exception:
        pass
    out = out[:3]
    d = sp_request("GET", "/search", params={"q": q, "type": "track,artist,album,playlist", "limit": 5})
    tracks = [t for t in (d.get("tracks") or {}).get("items") or [] if t]
    artists = [a for a in (d.get("artists") or {}).get("items") or [] if a]
    albums = [a for a in (d.get("albums") or {}).get("items") or [] if a]
    lists = [p for p in (d.get("playlists") or {}).get("items") or [] if p]
    for a in artists[:1]:
        fol = (a.get("followers") or {}).get("total") or 0
        out.append(sp_hit("artist", a.get("name", ""), f"{fol:,} followers" if fol else "", a["uri"], pick_image(a.get("images"))))
    dup = set()
    for t in tracks[:5]:
        alb = t.get("album") or {}
        sig = (t.get("name", "").lower(), tuple(x["name"] for x in t.get("artists", [])))
        if sig in dup:
            continue
        dup.add(sig)
        out.append(sp_hit("track", t.get("name", ""), ", ".join(x["name"] for x in t.get("artists", [])) + " · " + alb.get("name", ""),
                          t["uri"], pick_image(alb.get("images"))))
    for a in albums[:2]:
        out.append(sp_hit("album", a.get("name", ""), ", ".join(x["name"] for x in a.get("artists", [])) + " · " + (a.get("release_date") or "")[:4],
                          a["uri"], pick_image(a.get("images"))))
    seen = {h["id"] for h in out}
    for p in lists[:2]:
        if "spotifyhit." + p["uri"] not in seen:
            out.append(sp_hit("playlist", p.get("name", ""), "by " + (p.get("owner") or {}).get("display_name", ""), p["uri"], pick_image(p.get("images"))))
    out = out[:limit]
    sp = spotify()

    def local(h):
        if h["image"]:
            key = h["id"].split(":")[-1] + "_l"
            h["image"] = sp.spotify_fetch.cache_art(h["image"], key)
            if h["image"].startswith("file://"):
                h["image"] = h["image"][7:]
        return h
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        return list(ex.map(local, out))


def spotify_play(uri):
    kind = uri.split(":")[1] if uri.count(":") >= 2 else ""
    if sh(["playerctl", "-p", "spotify", "status"]) == "":
        subprocess.Popen(["xdg-open", uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return 0
    body = {"uris": [uri]} if kind == "track" else {"context_uri": uri}
    try:
        sp_request("PUT", "/me/player/play", body)
        return 0
    except Exception:
        pass
    return subprocess.call(["playerctl", "-p", "spotify", "open", uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def is_vivaldi(c):
    return (c.get("class") or "").lower().startswith("vivaldi")


def switch_tab(tid):
    tabs = mcp().t_browser_tabs({})
    title = next((t["title"] for t in tabs.get("tabs", []) if t["id"] == tid), "") if tabs.get("ok") else ""
    if not mcp().t_browser_switch_tab({"id": tid}).get("ok"):
        return 1
    win = None
    for _ in range(8):
        cl = hypr_clients()
        win = latest(cl, lambda c: is_vivaldi(c) and title and (c.get("title") or "").startswith(title[:40]))
        if win:
            break
        time.sleep(0.08)
    win = win or latest(hypr_clients(), is_vivaldi)
    if win:
        focus(win["address"])
    return 0


def normalize_url(text):
    t = text.strip()
    if re.match(r"^[a-z][a-z0-9+.-]*://", t, re.I):
        return t
    if " " not in t and (re.search(r"\.[a-z]{2,}(?:[/:?#]|$)", t, re.I) or re.match(r"^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(/|$)", t)):
        return "https://" + t if not t.startswith(("localhost", "127.")) else "http://" + t
    return SEARCH_URL + urllib.parse.quote_plus(t)


def open_url(text):
    url = normalize_url(text)
    if not url:
        return 1
    r = mcp().t_browser_open({"url": url})
    if not r.get("ok"):
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return 0
    time.sleep(0.15)
    win = latest(hypr_clients(), is_vivaldi)
    if win:
        focus(win["address"])
    return 0


def firefox_tab(url, title):
    cl = hypr_clients()
    if title:
        win = latest(cl, lambda c: (c.get("class") or "").lower() == "firefox" and (c.get("title") or "").startswith(title[:40]))
        if win:
            focus(win["address"])
            return 0
    subprocess.Popen(["hyprctl", "dispatch", "exec", "--", "firefox --new-tab " + shlex.quote(url)],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(0.4)
    win = latest(hypr_clients(), lambda c: (c.get("class") or "").lower() == "firefox")
    if win:
        focus(win["address"])
    return 0


def parse_ws_spec(text):
    t = " ".join(text.lower().replace("@", " @ ").split())
    if " @ " in t:
        app, ws = t.split(" @ ", 1)
    else:
        m = re.match(r"^(?:(?:open|launch|start|run|put|spawn|fire up)\s+)?(?:up\s+)?(.+?)\s+(?:on|in|to|at|onto|into)\s+(.+)$", t)
        if not m:
            m = re.match(r"^(.+?)\s+((?:\d+|" + "|".join(NUM_WORDS) + "|" + "|".join(NEW_WORDS) + r")\b.*)$", t)
            if not m:
                return None
        app, ws = m.group(1), m.group(2)
    app = re.sub(r"^(?:(?:open|launch|start|run|a|an|the|my)(?:\s+|$))+", "", app.strip()).strip()
    ws = re.sub(r"\b(a|an|the|workspace|ws|desktop|space|number|no\.?|please)\b", " ", ws.strip())
    ws = " ".join(ws.split())
    if not app or not ws:
        return None
    if ws.split()[0] in NEW_WORDS:
        return app, "new"
    tok = ws.split()[0]
    n = NUM_WORDS.get(tok) or (int(tok) if tok.isdigit() else None)
    if not n or not 1 <= n <= 99:
        return None
    return app, n


def find_app(name, apps, strict=False):
    name = name.strip().lower()
    if name.startswith("app."):
        hit = next((a for a in apps if a["id"].lower() == name), None)
        if hit:
            return hit
        name = name[4:]
    best, score = None, 0
    for a in apps:
        lab = a["label"].lower()
        exe = os.path.basename(a.get("arg", "").split()[0]).lower() if a.get("arg") else ""
        s = 0
        if lab == name or exe == name:
            s = 100
        elif lab.startswith(name) or exe.startswith(name):
            s = 60 - len(lab) * 0.1
        elif re.search(r"\b" + re.escape(name), lab):
            s = 40 - len(lab) * 0.1
        elif len(name) >= 4 and name in (a.get("keywords") or ""):
            s = 10
        if s > score:
            best, score = a, s
    return best if score >= (30 if strict else 1) else None


def first_empty_ws():
    try:
        used = {w["id"] for w in json.loads(sh(["hyprctl", "workspaces", "-j"]) or "[]") if w.get("windows", 0) > 0}
    except ValueError:
        used = set()
    n = 1
    while n in used:
        n += 1
    return n


def wm_classes(app):
    out = []
    if app.get("wmclass"):
        out.append(app["wmclass"])
    if app.get("desktop"):
        out.append(app["desktop"])
    if app.get("arg"):
        out.append(os.path.basename(app["arg"].split()[0]))
    out.append(app["label"])
    return [c.lower() for c in out if c]


def open_on_ws(spec, apps):
    parsed = parse_ws_spec(spec)
    if not parsed:
        return 1
    app = find_app(parsed[0], apps)
    if not app:
        return 1
    ws = first_empty_ws() if parsed[1] == "new" else parsed[1]
    cands = wm_classes(app)
    running = latest(hypr_clients(), lambda c: (c.get("class") or "").lower() in cands)
    if not running:
        sh(["hyprctl", "dispatch", "exec", "[workspace %d] %s" % (ws, app["arg"])])
        sh(["hyprctl", "dispatch", "workspace", str(ws)])
        return 0
    cls = running["class"]
    rc = subprocess.call(["bash", OPEN_ON_WS, str(ws), cls, app["arg"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if rc != 0:
        win = latest(hypr_clients(), lambda c: c.get("class") == cls)
        if win:
            sh(["hyprctl", "dispatch", "movetoworkspace", "%d,address:%s" % (ws, win["address"])])
    return 0


def describe_ws_spec(spec, apps, strict=False):
    parsed = parse_ws_spec(spec)
    if not parsed:
        return None
    app = find_app(parsed[0], apps, strict)
    if not app:
        return None
    return {"app": app, "ws": parsed[1],
            "show": app["label"] + " → " + ("a new workspace" if parsed[1] == "new" else "workspace %d" % parsed[1])}


def main(argv):
    if len(argv) < 2:
        return 2
    cmd, rest = argv[1], argv[2:]
    if cmd == "tabs":
        print(json.dumps(tab_actions(), ensure_ascii=False))
    elif cmd == "vscode":
        print(json.dumps(vscode_actions(), ensure_ascii=False))
    elif cmd == "spotify" and rest:
        q = " ".join(rest)
        try:
            print(json.dumps({"query": q, "results": spotify_search(q)}, ensure_ascii=False))
        except Exception as e:
            print(json.dumps({"query": q, "results": [], "error": str(e)[:200]}))
    elif cmd == "play" and rest:
        return spotify_play(rest[0])
    elif cmd == "playtop" and rest:
        try:
            hits = spotify_search(" ".join(rest), 4)
        except Exception:
            return 1
        return spotify_play(hits[0]["args"][0]) if hits else 1
    elif cmd == "tab" and rest:
        return switch_tab(rest[0])
    elif cmd == "fftab" and rest:
        return firefox_tab(rest[0], rest[1] if len(rest) > 1 else "")
    elif cmd == "open" and rest:
        return open_url(" ".join(rest))
    elif cmd == "openws" and rest:
        sys.path.insert(0, HERE)
        import palette_index
        apps = [a for a in palette_index.index_actions() if a.get("cat") == "app"]
        return open_on_ws(" ".join(rest), apps)
    elif cmd == "projects":
        print(json.dumps(project_actions(), ensure_ascii=False))
    elif cmd == "project" and rest:
        sub, a = rest[0], rest[1:]
        try:
            if sub == "open" and len(a) >= 3:
                return project_open(*a[:3])
            if sub == "run" and len(a) >= 3:
                return project_run(*a[:3])
            if sub == "new" and a:
                return project_new(a[0], " ".join(a[1:]))
            if sub == "peek" and a:
                print(json.dumps(project_peek(a[0]), ensure_ascii=False))
                return 0
        except Exception as e:
            notify("do: " + sub + " failed", str(e)[:200], True)
            return 1
        return 2
    elif cmd == "favicons" and rest:
        fetch_favs(json.loads(rest[0]))
    else:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
