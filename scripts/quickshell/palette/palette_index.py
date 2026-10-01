#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import tempfile

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.abspath(__file__))
QS = os.path.dirname(HERE)
SCRIPTS = os.path.dirname(QS)
SETTINGS = os.path.join(HOME, ".config/hypr/settings.json")
CACHE_DIR = os.path.join(HOME, ".cache/quickshell/palette")
CACHE = os.path.join(CACHE_DIR, "index.json")
HISTORY = os.path.join(CACHE_DIR, "history.json")
SELF = os.path.abspath(__file__)

WIDGETS = {
    "battery": ("Battery", "Charge, health and power draw", 0xF0079, "Super B"),
    "volume": ("Volume mixer", "Outputs, inputs and per-app levels", 0xF057E, "Super Shift V"),
    "notifications": ("Notifications", "Everything that came in", 0xF009A, "Super Shift A"),
    "calendar": ("Calendar", "Agenda, weather and schedule", 0xF00ED, "Super Shift X"),
    "music": ("Music", "Now playing, lyrics and queue", 0xF075A, "Super M"),
    "network": ("Network", "Wi-Fi, Bluetooth and VPN", 0xF05A9, "Super N"),
    "quicksettings": ("Quick settings", "The bottom drawer of toggles", 0xF0493, "Super U"),
    "stewart": ("Stewart", "", 0xF06A9, ""),
    "monitors": ("Monitors", "Resolution, scale and layout", 0xF0379, "Super Shift M"),
    "focustime": ("Focus time", "Where your hours went today", 0xF0128, "Super Shift T"),
    "guide": ("Guide and settings", "Keybinds, settings, music stats", 0xF02D7, "Super Shift H"),
    "wallpaper": ("Wallpaper picker", "Browse and set wallpapers", 0xF02E9, "Super W"),
    "workspaces": ("Workspace overview", "Every workspace at a glance", 0xF0570, "Super Shift W"),
    "power": ("Power menu", "Lock, sleep, restart, shut down", 0xF0425, "Super Shift E"),
    "applauncher": ("App launcher", "The full app grid", 0xF003B, "Super A"),
    "clipboard": ("Clipboard history", "Everything you copied", 0xF014C, "Super V"),
    "claudeask": ("Claude chat", "The full chat window", 0xF06A9, "Super `"),
    "quicktell": ("Quick tell", "One line to Claude", 0xF0B7B, "Super G"),
    "people": ("People", "Who you talk to", 0xF0849, ""),
    "memory": ("Claude's memory", "What Claude remembers about you", 0xF09D1, ""),
    "netstatus": ("Network status", "Connection health at a glance", 0xF05A9, ""),
}
SKIP_WIDGETS = {"hidden", "palette", "stewart"}

SETTING_LABELS = {
    "ecoModeEnabled": ("Eco mode", "Throttle and freeze background apps", "eco throttle freeze battery cpu background spotify", 0xF032A),
    "ambientGlowEnabled": ("Ambient glow", "Screen-edge glow from the album art", "glow edges album light", 0xF0335),
    "ambientGlowBeatReactive": ("Ambient glow follows the beat", "Pulse the edge glow with the music", "glow beat bpm pulse", 0xF0335),
    "mediaVisualizerEnabled": ("Media visualiser", "Live spectrum in the bar", "visualizer fft spectrum bars music", 0xF075A),
    "topBarHoverCardsEnabled": ("Bar hover cards", "Rich cards when hovering pills", "hover cards tooltips bar", 0xF0570),
    "hyprlandBorderPulseEnabled": ("Border pulse", "Window border pulses with the music", "border pulse music beat", 0xF0570),
    "lockStyleEnabled": ("New lock screen", "The redesigned lock, or the legacy one", "lock style legacy redesign", 0xF033E),
    "topBarTimerEnabled": ("Timer pill", "Countdown pill in the bar", "timer pill bar", 0xF13AB),
    "residentCardsEnabled": ("Resident cards", "Cards that drop from the clock pill", "claude cards popups", 0xF06A9),
    "residentCatchUp": ("While-you-were-away card", "Catch-up after you step away", "claude catch up away idle", 0xF06A9),
    "residentVoiceNudges": ("Spoken nudges", "Let Claude talk out loud", "claude voice speak tts", 0xF06A9),
    "residentClipboardAware": ("Clipboard awareness", "Claude reacts to what you copy", "claude clipboard", 0xF014C),
    "smartWsLayoutsEnabled": ("Saved layouts", "Workspace layout save and restore", "smart workspaces layouts", 0xF056E),
    "topBarAccentLine": ("Bar accent line", "The thin animated line on the bar", "accent line bar", 0xF0570),
    "topBarShowGpu": ("GPU chip", "GPU load in the bar", "gpu stats chip bar", 0xF04C5),
    "topBarShowNet": ("Network chip", "Up and down speed in the bar", "net stats chip bar", 0xF05A9),
    "topBarShowUptime": ("Uptime chip", "Uptime in the bar", "uptime stats chip bar", 0xF04C5),
    "topBarShowQuickshellCpu": ("Shell CPU chip", "Quickshell's own CPU use", "quickshell cpu perf chip", 0xF04C5),
    "topBarFlourishesEnabled": ("Bar flourishes", "Little celebrations on the bar", "flourish celebrate bar", 0xF0570),
    "topBarWorkspaceIconsEnabled": ("Workspace icons", "App icons in workspace pills", "workspace icons pills", 0xF0570),
    "cardAnimations": ("Card animations", "Motion on pinned cards", "cards motion", 0xF0570),
    "openGuideAtStartup": ("Guide at startup", "Open the guide on login", "guide startup login", 0xF02D7),
}
SETTING_PREFIXES = [
    ("topBarFlourish", "Bar flourish: "), ("topBar", "Bar: "), ("lock", "Lock screen: "),
    ("resident", "Claude: "), ("ambientGlow", "Ambient glow: "), ("mediaVisualizer", "Visualiser: "),
    ("pin", "Pinned cards: "), ("smartWs", "Smart workspaces: "), ("hyprPolish", "Hyprland: "),
    ("card", "Cards: "), ("eco", "Eco: "),
]
SETTING_SKIP = {"claudeDebug", "discordProfiler"}
ENUMS = {
    "hyprPolishAnimations": ("Hyprland animations", ["off", "subtle", "juicy"], "animations motion"),
    "hyprPolishDimInactive": ("Dim inactive windows", ["off", "subtle", "strong"], "dim inactive focus"),
    "hyprPolishWsAccent": ("Workspace border accent", ["off", "palette", "smartws"], "accent border workspace colour"),
    "topBarPillBgMaster": ("Pill backgrounds", ["always", "occasional", "never"], "pill effects backgrounds"),
    "residentMorningBrief": ("Morning brief", ["off", "text", "spoken"], "claude brief morning"),
    "smartWsAutoNames": ("Smart workspace names", ["off", "hover", "always"], "smart workspaces names"),
    "screenshotAnswerOutput": ("Screenshot answers go to", ["card", "notification", "both"], "screenshot answer output"),
}


def humanize(key):
    for pre, lab in SETTING_PREFIXES:
        if key.startswith(pre) and len(key) > len(pre):
            rest = key[len(pre):]
            break
    else:
        pre, lab, rest = "", "", key
    words = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", rest).replace("Enabled", "").strip().lower().split()
    text = " ".join(words) or rest.lower()
    return lab + text, (pre + " " + " ".join(words)).lower()


def sh(cmd, timeout=1.5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def pid_alive(path):
    try:
        os.kill(int(open(path).read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def live_states():
    return {
        "mute": "on" if sh(["pamixer", "--get-mute"]) == "true" else "off",
        "mic": "on" if sh(["pamixer", "--default-source", "--get-mute"]) == "true" else "off",
        "nightlight": "on" if sh(["pgrep", "-x", "wlsunset"]) else "off",
        "idle": "on" if sh(["pgrep", "-x", "hypridle"]) else "off",
        "wakelock": "on" if pid_alive("/tmp/qs_wakelock.pid") else "off",
        "dnd": "on" if sh(["swaync-client", "-D"]) == "true" else "off",
    }


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def widget_actions():
    try:
        src = open(os.path.join(QS, "WindowRegistry.js")).read()
    except OSError:
        return []
    names = re.findall(r'^\s*"(\w+)"\s*:\s*\{\s*w:', src, re.M)
    out = []
    for n in names:
        if n in SKIP_WIDGETS:
            continue
        label, hint, icon, keys = WIDGETS.get(n, (n.capitalize(), "", 0xF0570, ""))
        out.append({
            "id": "widget." + n, "label": label, "hint": hint or "Open the " + n + " popup",
            "cat": "widget", "icon": chr(icon), "keywords": "open show widget popup " + n,
            "cmd": 'bash "$HOME/.config/hypr/scripts/qs_manager.sh" open ' + n,
            "keys": keys, "close": False, "verb": "Open",
        })
    return out


def setting_actions(settings):
    out = []
    for k, v in settings.items():
        if isinstance(v, bool) and k not in SETTING_SKIP:
            if k in SETTING_LABELS:
                label, hint, kw, icon = SETTING_LABELS[k]
            else:
                label, kw = humanize(k)
                label = label[0].upper() + label[1:]
                hint, icon = "Setting " + k, 0xF0521
            out.append({
                "id": "setting." + k, "label": label, "hint": hint, "cat": "setting", "icon": chr(icon),
                "keywords": kw + " toggle switch turn enable disable on off setting",
                "cmd": "python3 " + json.dumps(SELF) + ' set ' + k + ' "$1"',
                "arg": "false" if v else "true", "state": "on" if v else "off",
                "verb": "Turn off" if v else "Turn on",
            })
    for k, (label, opts, kw) in ENUMS.items():
        cur = settings.get(k)
        for o in opts:
            if o == cur:
                continue
            out.append({
                "id": "setting." + k + "." + o, "label": label + ": " + o,
                "hint": "Currently " + str(cur) if cur is not None else "Setting " + k,
                "cat": "setting", "icon": chr(0xF0521), "keywords": kw + " " + o + " set setting mode",
                "cmd": "python3 " + json.dumps(SELF) + ' set ' + k + ' "$1"',
                "arg": json.dumps(o), "from": str(cur), "to": o, "verb": "Switch",
            })
    return out


def layout_actions():
    base = os.path.join(HOME, ".config/hypr/smartws/layouts")
    try:
        files = sorted((f for f in os.listdir(base) if f.endswith(".json")),
                       key=lambda f: os.path.getmtime(os.path.join(base, f)), reverse=True)
    except OSError:
        return []
    out = []
    for f in files:
        name = f[:-5]
        n = len(load_json(os.path.join(base, f), {}).get("windows") or [])
        out.append({
            "id": "layout.restore." + name, "label": "Restore " + name, "hint": f"{n} windows, saved layout",
            "cat": "layout", "icon": chr(0xF056E), "keywords": "restore layout smart workspaces load " + name,
            "cmd": 'bash "$HOME/.config/hypr/scripts/smartws.sh" restore "$1" >/dev/null', "arg": name,
            "verb": "Restore",
        })
        out.append({
            "id": "layout.delete." + name, "label": "Delete layout " + name, "hint": f"{n} windows, can't be undone",
            "cat": "layout", "icon": chr(0xF01B4), "keywords": "delete remove forget layout smart workspaces " + name,
            "cmd": 'bash "$HOME/.config/hypr/scripts/smartws.sh" delete "$1" >/dev/null', "arg": name,
            "danger": True, "verb": "Delete",
        })
    return out


def window_actions():
    try:
        clients = json.loads(sh(["hyprctl", "clients", "-j"]) or "[]")
    except ValueError:
        return []
    out = []
    for c in sorted(clients, key=lambda c: c.get("focusHistoryID", 99)):
        cls, title = c.get("class") or "", c.get("title") or ""
        if not cls or c.get("focusHistoryID") == 0 or title == "qs-master" or not c.get("mapped", True):
            continue
        ws = (c.get("workspace") or {}).get("name") or ""
        ws = "scratch" if ws.startswith("special") else "workspace " + ws
        out.append({
            "id": "window." + c["address"], "label": title[:80] or cls, "hint": f"{cls} · {ws}",
            "cat": "window", "icon": chr(0xF05AF),
            "keywords": "go to switch focus window jump " + cls.lower() + " " + ws,
            "cmd": 'hyprctl dispatch focuswindow "address:$1" >/dev/null', "arg": c["address"], "verb": "Go to",
        })
    return out


def sink_actions():
    try:
        sinks = json.loads(sh(["pactl", "-f", "json", "list", "sinks"]) or "[]")
    except ValueError:
        return []
    default = sh(["pactl", "get-default-sink"])
    out = []
    for k in sinks:
        name = k.get("name", "")
        if not name or name == default:
            continue
        desc = k.get("description") or name
        out.append({
            "id": "sink." + name, "label": "Output to " + desc, "hint": "Make this the default speaker",
            "cat": "audio", "icon": chr(0xF04C3), "keywords": "audio output speaker headphones sink switch device " + desc.lower(),
            "cmd": 'pactl set-default-sink "$1"', "arg": name, "verb": "Switch",
        })
    return out


def bluetooth_actions():
    def devices(which):
        res = {}
        for line in sh(["bluetoothctl", "devices", which]).splitlines():
            parts = line.split(" ", 2)
            if len(parts) == 3 and parts[0] == "Device":
                res[parts[1]] = parts[2]
        return res
    paired = devices("Paired")
    if not paired:
        return []
    connected = devices("Connected")
    out = []
    for mac, name in paired.items():
        on = mac in connected
        out.append({
            "id": "bt." + mac, "label": ("Disconnect " if on else "Connect ") + name,
            "hint": "Bluetooth, connected" if on else "Bluetooth, paired",
            "cat": "device", "icon": chr(0xF00B2 if on else 0xF00AF),
            "keywords": "bluetooth headphones earbuds speaker pair device " + name.lower(),
            "cmd": 'bluetoothctl ' + ("disconnect" if on else "connect") + ' "$1" >/dev/null', "arg": mac,
            "close": True, "verb": "Disconnect" if on else "Connect",
        })
    return out


APP_DIRS = [
    "/usr/share/applications", "/usr/local/share/applications",
    os.path.join(HOME, ".local/share/applications"), "/var/lib/flatpak/exports/share/applications",
    os.path.join(HOME, ".local/share/flatpak/exports/share/applications"),
]


def read_desktop(path):
    d, inside = {}, False
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    inside = line == "[Desktop Entry]"
                elif inside and "=" in line:
                    k, v = line.split("=", 1)
                    d.setdefault(k, v)
    except (OSError, UnicodeDecodeError):
        return None
    if d.get("Type", "Application") != "Application" or d.get("NoDisplay") in ("true", "1") or d.get("Hidden") == "true":
        return None
    if not d.get("Name") or not d.get("Exec"):
        return None
    return d


def app_actions():
    apps = {}
    for base in APP_DIRS:
        for root_, _, files in os.walk(base):
            for fn in files:
                if fn.endswith(".desktop"):
                    d = read_desktop(os.path.join(root_, fn))
                    if d and d["Name"] not in apps:
                        apps[d["Name"]] = d
    res = []
    for name, d in sorted(apps.items(), key=lambda x: x[0].lower()):
        exe = re.sub(r"\s+%[a-zA-Z]", "", d["Exec"]).split(" @@")[0].strip()
        hint = d.get("GenericName") or d.get("Comment") or "Application"
        res.append({
            "id": "app." + name, "label": name, "hint": hint[:90], "cat": "app", "icon": "",
            "image": d.get("Icon", ""),
            "keywords": "launch run start open app " + (d.get("GenericName", "") + " " + d.get("Keywords", "").replace(";", " ")).lower(),
            "cmd": 'hyprctl dispatch exec -- "$1" >/dev/null', "arg": exe, "verb": "Launch",
        })
    return res


def build():
    settings = load_json(SETTINGS, {})
    static = load_json(os.path.join(HERE, "actions.json"), {}).get("actions", [])
    states = live_states()
    for a in static:
        if a.get("state") in states:
            a["state"] = states[a["state"]]
        elif "state" in a:
            del a["state"]
    actions = (static + window_actions() + widget_actions() + setting_actions(settings) + layout_actions()
               + sink_actions() + bluetooth_actions() + app_actions())
    return {"actions": actions, "history": load_json(HISTORY, {})}


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2 if path == SETTINGS else None)
        if path == SETTINGS:
            f.write("\n")
    os.replace(tmp, path)


ECO_RULES = os.path.join(HOME, ".config/hypr/eco/rules.json")


def set_eco(level):
    """Write an eco rule for the focused window's class; 'auto' drops the override."""
    try:
        cls = (json.loads(sh(["hyprctl", "activewindow", "-j"]) or "{}").get("class") or "").lower()
    except ValueError:
        cls = ""
    if not cls or level not in ("never", "throttle", "freeze", "auto"):
        return 1
    data = load_json(ECO_RULES, None)
    if not isinstance(data, dict):
        return 1
    rules = data.setdefault("rules", {})
    if level == "auto":
        rules.pop(cls, None)
    else:
        rules[cls] = {**rules.get(cls, {}), "level": level}
    write_atomic(ECO_RULES, data)
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "set" and len(argv) >= 4:
        s = load_json(SETTINGS, None)
        if s is None:
            return 1
        try:
            s[argv[2]] = json.loads(argv[3])
        except ValueError:
            s[argv[2]] = argv[3]
        write_atomic(SETTINGS, s)
        return 0
    if len(argv) >= 3 and argv[1] == "eco":
        return set_eco(argv[2])
    if len(argv) >= 3 and argv[1] == "used":
        h = load_json(HISTORY, {})
        e = h.get(argv[2], {"n": 0, "t": 0})
        import time
        h[argv[2]] = {"n": e["n"] + 1, "t": int(time.time())}
        write_atomic(HISTORY, h)
        return 0
    data = build()
    write_atomic(CACHE, data)
    print(json.dumps(data, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
