#!/usr/bin/env python3
import os, sys, re, json, time, shlex, socket, select, subprocess, fcntl

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, ".config/hypr/smartws")
RULES = os.path.join(BASE, "rules.json")
OVERRIDES = os.path.join(BASE, "overrides.json")
LAYOUTS = os.path.join(BASE, "layouts")
RESTORE_LOG = os.path.join(BASE, "restore_log.json")
STATE = "/tmp/qs_smartws.json"
CMDFILE = "/tmp/qs_smartws_cmd"
LOCK = "/tmp/qs_smartws.lock"
IGNORE_CLASSES = {"", "quickshell", "kitty-scratchpad", "org.quickshell"}

DEFAULT_RULES = {
    "classes": {
        "vivaldi-stable": "web", "firefox": "web", "chromium": "web", "google-chrome": "web",
        "brave-browser": "web", "zen": "web", "librewolf": "web",
        "code": "code", "code-oss": "code", "cursor": "code", "jetbrains-idea": "code",
        "jetbrains-pycharm": "code", "nvim-qt": "code", "zed": "code", "dev.zed.zed": "code",
        "kitty": "term", "alacritty": "term", "foot": "term", "wezterm": "term",
        "org.wezfurlong.wezterm": "term", "ghostty": "term",
        "vesktop": "chat", "discord": "chat", "org.telegram.desktop": "chat",
        "telegramdesktop": "chat", "signal": "chat", "element": "chat", "slack": "chat",
        "spotify": "music", "com.spotify.client": "music", "rhythmbox": "music", "strawberry": "music",
        "steam": "play", "lutris": "play", "heroic": "play", "prismlauncher": "play",
        "obsidian": "notes", "logseq": "notes", "joplin": "notes",
        "org.pwmt.zathura": "read", "okular": "read", "evince": "read",
        "org.gnome.evince": "read", "calibre": "read",
        "mpv": "media", "vlc": "media", "org.jellyfin.jellyfinmediaplayer": "media",
        "obs": "media", "com.obsproject.studio": "media", "kdenlive": "media",
        "gimp": "art", "krita": "art", "inkscape": "art", "blender": "art",
        "thunar": "files", "nautilus": "files", "dolphin": "files", "org.gnome.nautilus": "files",
        "libreoffice-writer": "docs", "libreoffice-calc": "docs", "onlyoffice": "docs",
        "com.github.xournalpp.xournalpp": "notes",
    },
    "patterns": [
        ["^steam_app_", "play"], ["^jetbrains-", "code"], ["^libreoffice", "docs"],
        ["^org\\.telegram", "chat"], ["^(minecraft|net\\.minecraft)", "play"],
    ],
    "categories": {
        "web": {"name": "Web", "glyph": "󰖟", "color": "#89b4fa"},
        "code": {"name": "Code", "glyph": "󰅩", "color": "#a6e3a1"},
        "term": {"name": "Terminal", "glyph": "󰆍", "color": "#f9e2af"},
        "chat": {"name": "Chat", "glyph": "󰭹", "color": "#cba6f7"},
        "music": {"name": "Music", "glyph": "󰎆", "color": "#a6e3a1"},
        "play": {"name": "Play", "glyph": "󰊴", "color": "#f38ba8"},
        "notes": {"name": "Notes", "glyph": "󰠮", "color": "#fab387"},
        "read": {"name": "Read", "glyph": "󰂺", "color": "#94e2d5"},
        "media": {"name": "Media", "glyph": "󰎁", "color": "#f5c2e7"},
        "art": {"name": "Create", "glyph": "󰏘", "color": "#f5c2e7"},
        "files": {"name": "Files", "glyph": "󰉋", "color": "#f9e2af"},
        "docs": {"name": "Docs", "glyph": "󰈙", "color": "#89dceb"},
        "misc": {"name": "Mixed", "glyph": "󰘔", "color": "#bac2de"},
    },
}


def jload(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def jsave(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


MAILBOX = "/tmp/qs_claude_mailbox.json"


def mailbox_post(to, msg, frm="smartws"):
    # Minimal local mirror of qs_mcp.py's mailbox_post — same file/schema so
    # any mailbox_read (resident, a live Claude Code session) sees it too.
    try:
        try:
            with open(MAILBOX) as f:
                msgs = json.load(f)
        except Exception:
            msgs = []
        msgs.append({"id": int(time.time() * 1000), "from": frm, "to": to, "msg": msg,
                     "ts": int(time.time()), "read": False})
        tmp = MAILBOX + ".tmp"
        with open(tmp, "w") as f:
            json.dump(msgs[-100:], f)
        os.replace(tmp, MAILBOX)
    except OSError:
        pass


def ensure_files():
    os.makedirs(LAYOUTS, exist_ok=True)
    if not os.path.exists(RULES):
        jsave(RULES, DEFAULT_RULES)
    if not os.path.exists(OVERRIDES):
        jsave(OVERRIDES, {})


def hypr(*args):
    try:
        r = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=4)
        return r.stdout
    except Exception:
        return ""


def clients():
    try:
        return json.loads(hypr("clients", "-j") or "[]")
    except Exception:
        return []


def safe_name(n):
    n = re.sub(r"[^A-Za-z0-9 _-]", "", n or "").strip()
    return n[:32]


def list_layouts():
    try:
        files = [f for f in os.listdir(LAYOUTS) if f.endswith(".json")]
    except OSError:
        return []
    files.sort(key=lambda f: os.path.getmtime(os.path.join(LAYOUTS, f)), reverse=True)
    return [f[:-5] for f in files]


def classify(cls, rules):
    c = (cls or "").lower()
    m = rules.get("classes", {})
    if c in m:
        return m[c]
    for pat, cat in rules.get("patterns", []):
        try:
            if re.search(pat, c):
                return cat
        except re.error:
            continue
    return None


def compute_state():
    ensure_files()
    rules = jload(RULES, DEFAULT_RULES)
    over = jload(OVERRIDES, {})
    cats = rules.get("categories", {})
    per = {}
    for c in clients():
        if not c.get("mapped", True) or c.get("hidden"):
            continue
        ws = c.get("workspace", {}).get("id")
        if ws is None or ws < 0:
            continue
        cls = c.get("class", "")
        if cls in IGNORE_CLASSES:
            continue
        cat = classify(cls, rules)
        if cat is None:
            continue
        d = per.setdefault(str(ws), {})
        e = d.setdefault(cat, [0, 9999])
        e[0] += 1
        e[1] = min(e[1], c.get("focusHistoryID", 9999))
    out = {}
    for ws, d in per.items():
        ranked = sorted(d.items(), key=lambda kv: (-kv[1][0], kv[1][1]))
        top = ranked[0][0]
        if len(ranked) > 1 and ranked[0][1][0] == ranked[1][1][0] and False:
            top = "misc"
        meta = cats.get(top, cats.get("misc", {"name": top.title(), "glyph": "", "color": "#bac2de"}))
        out[ws] = {"category": top, "name": meta.get("name", top), "glyph": meta.get("glyph", ""), "color": meta.get("color", "#bac2de"), "custom": False}
    for ws, o in over.items():
        cat = o.get("category")
        meta = cats.get(cat, {}) if cat else {}
        base = out.get(ws, {"category": cat or "misc", "name": "", "glyph": "", "color": "#bac2de"})
        base = dict(base)
        if meta:
            base.update({"category": cat, "name": meta.get("name", base["name"]), "glyph": meta.get("glyph", base["glyph"]), "color": meta.get("color", base["color"])})
        if o.get("name"):
            base["name"] = o["name"]
        if o.get("glyph"):
            base["glyph"] = o["glyph"]
        base["custom"] = True
        out[ws] = base
    return {"ws": out, "layouts": list_layouts(), "categories": list(cats.keys()), "ts": int(time.time())}


_last = None


def write_state(force=False):
    global _last
    st = compute_state()
    body = json.dumps({k: v for k, v in st.items() if k != "ts"}, sort_keys=True)
    if not force and body == _last:
        return
    _last = body
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, ensure_ascii=False)
    os.replace(tmp, STATE)


def proc_cmd(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            parts = [p.decode(errors="replace") for p in f.read().split(b"\0") if p]
        return shlex.join(parts) if parts else ""
    except OSError:
        return ""


def cmd_save(name):
    ensure_files()
    name = safe_name(name)
    if not name or name.lower() == "auto":
        name = "layout-" + time.strftime("%H%M%S")
    wins = []
    seen = set()
    for c in clients():
        ws = c.get("workspace", {}).get("id", -1)
        cls = c.get("class", "")
        if ws < 0 or cls in IGNORE_CLASSES or not c.get("mapped", True):
            continue
        cmd = proc_cmd(c.get("pid", 0))
        if not cmd:
            continue
        key = (cls, ws, cmd, tuple(c.get("at", [0, 0])))
        if key in seen:
            continue
        seen.add(key)
        wins.append({
            "class": cls, "title": c.get("title", ""), "cmd": cmd, "workspace": ws,
            "floating": bool(c.get("floating")), "at": c.get("at", [0, 0]), "size": c.get("size", [0, 0]),
            "monitor": c.get("monitor", 0),
        })
    if not wins:
        print("nothing to save")
        return 1
    jsave(os.path.join(LAYOUTS, name + ".json"), {"name": name, "saved": int(time.time()), "windows": wins})
    write_state(True)
    print(f"saved {name}: {len(wins)} windows")
    return 0


def cmd_delete(name):
    p = os.path.join(LAYOUTS, safe_name(name) + ".json")
    if os.path.exists(p):
        os.remove(p)
    write_state(True)
    print("deleted", name)
    return 0


def cmd_restore(name, dry=False):
    p = os.path.join(LAYOUTS, safe_name(name) + ".json")
    lay = jload(p, None)
    if not lay:
        print("no such layout")
        return 1
    live = clients()
    claimed = set()
    plan = []
    for w in lay.get("windows", []):
        match = None
        for c in live:
            if c.get("address") in claimed or c.get("class") != w["class"] or not c.get("mapped", True):
                continue
            match = c
            break
        wsn = w["workspace"]
        if match:
            claimed.add(match["address"])
            addr = match["address"]
            if match.get("workspace", {}).get("id") != wsn:
                plan.append(["dispatch", "movetoworkspacesilent", f"{wsn},address:{addr}"])
            if w["floating"]:
                if not match.get("floating"):
                    plan.append(["dispatch", "togglefloating", f"address:{addr}"])
                plan.append(["dispatch", "resizewindowpixel", f"exact {w['size'][0]} {w['size'][1]},address:{addr}"])
                plan.append(["dispatch", "movewindowpixel", f"exact {w['at'][0]} {w['at'][1]},address:{addr}"])
        else:
            rule = f"workspace {wsn} silent"
            if w["floating"]:
                rule += f"; float; size {w['size'][0]} {w['size'][1]}; move {w['at'][0]} {w['at'][1]}"
            plan.append(["dispatch", "exec", f"[{rule}] {w['cmd']}"])
    for step in plan:
        if dry:
            print("hyprctl " + " ".join(shlex.quote(s) for s in step))
        else:
            subprocess.run(["hyprctl", *step], capture_output=True, timeout=6)
            time.sleep(0.15)
    if not dry:
        log_restore(name)
        mailbox_post("user", f"Restored layout '{name}' ({len(plan)} actions)", frm="smartws")
    print(f"{'planned' if dry else 'restored'} {len(plan)} actions for {name}")
    return 0


def log_restore(name):
    # Feeds the resident's layout-suggestion heuristic (resident_extras.py's
    # tick_layout_suggest) — a simple time-of-day/recency log of manual
    # restores, kept small and append-only.
    lt = time.localtime()
    log = jload(RESTORE_LOG, [])
    log.append({"name": name, "ts": int(time.time()), "hour": lt.tm_hour + lt.tm_min / 60.0})
    jsave(RESTORE_LOG, log[-300:])


def cmd_rename(ws, name):
    ensure_files()
    over = jload(OVERRIDES, {})
    if not name or name in ("-", "auto"):
        over.pop(str(ws), None)
    else:
        o = over.get(str(ws), {})
        o["name"] = safe_name(name)
        over[str(ws)] = o
    jsave(OVERRIDES, over)
    write_state(True)
    return 0


def cmd_cycle(ws):
    ensure_files()
    rules = jload(RULES, DEFAULT_RULES)
    cats = list(rules.get("categories", {}).keys())
    over = jload(OVERRIDES, {})
    cur = over.get(str(ws), {}).get("category")
    if cur is None:
        idx = 0
    elif cur in cats and cats.index(cur) + 1 < len(cats):
        idx = cats.index(cur) + 1
    else:
        over.pop(str(ws), None)
        jsave(OVERRIDES, over)
        write_state(True)
        return 0
    over[str(ws)] = {"category": cats[idx]}
    jsave(OVERRIDES, over)
    write_state(True)
    return 0


def run_command(line):
    parts = shlex.split(line) if line.strip() else []
    if not parts:
        return
    op, args = parts[0], parts[1:]
    try:
        if op == "save":
            cmd_save(" ".join(args))
        elif op == "restore" and args:
            cmd_restore(" ".join(args))
        elif op == "delete" and args:
            cmd_delete(" ".join(args))
        elif op == "rename" and len(args) >= 2:
            cmd_rename(args[0], " ".join(args[1:]))
        elif op == "cycle" and args:
            cmd_cycle(args[0])
        elif op == "refresh":
            write_state(True)
    except Exception:
        pass


def drain_cmdfile():
    try:
        with open(CMDFILE) as f:
            lines = f.read().splitlines()
        open(CMDFILE, "w").close()
    except OSError:
        return
    for l in lines:
        run_command(l)


def daemon():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0
    ensure_files()
    open(CMDFILE, "a").close()
    write_state(True)
    sock_path = f"{os.environ.get('XDG_RUNTIME_DIR', '/run/user/1000')}/hypr/{os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')}/.socket2.sock"
    sock = None
    dirty = False
    last_change = 0.0
    last_rules = 0.0
    last_cmd_check = 0.0
    while True:
        if sock is None:
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(sock_path)
                sock.setblocking(False)
            except OSError:
                sock = None
                time.sleep(2)
                continue
        r, _, _ = select.select([sock], [], [], 0.4)
        if r:
            try:
                data = sock.recv(65536)
            except BlockingIOError:
                data = b"x"
            except OSError:
                data = b""
            if not data:
                sock.close()
                sock = None
                continue
            if re.search(rb"(openwindow|closewindow|movewindow|windowtitle|activewindow|workspace|destroyworkspace)", data):
                dirty = True
                last_change = time.time()
        now = time.time()
        if dirty and now - last_change > 0.35:
            dirty = False
            write_state()
        if now - last_cmd_check > 0.5:
            last_cmd_check = now
            drain_cmdfile()
        if now - last_rules > 3:
            last_rules = now
            try:
                m = max(os.path.getmtime(RULES), os.path.getmtime(OVERRIDES))
                if m > getattr(daemon, "m", 0):
                    daemon.m = m
                    write_state(True)
            except OSError:
                pass


def main():
    a = sys.argv[1:]
    if not a:
        print("usage: smartws.py daemon|save [name]|restore <name> [--dry-run]|delete <name>|list|rename <ws> <name|->|cycle <ws>|refresh")
        return 1
    op = a[0]
    if op == "daemon":
        return daemon()
    ensure_files()
    if op == "save":
        return cmd_save(" ".join(a[1:]))
    if op == "restore" and len(a) > 1:
        dry = "--dry-run" in a
        return cmd_restore(" ".join(x for x in a[1:] if x != "--dry-run"), dry)
    if op == "delete" and len(a) > 1:
        return cmd_delete(" ".join(a[1:]))
    if op == "list":
        print("\n".join(list_layouts()))
        return 0
    if op == "rename" and len(a) > 2:
        return cmd_rename(a[1], " ".join(a[2:]))
    if op == "cycle" and len(a) > 1:
        return cmd_cycle(a[1])
    if op == "refresh":
        write_state(True)
        return 0
    print("bad args")
    return 1


if __name__ == "__main__":
    sys.exit(main())
