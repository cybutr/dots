#!/usr/bin/env python3
import os, sys, json, time, signal, socket, subprocess, threading, atexit, glob

import psutil

HOME = os.path.expanduser("~")
UID = os.getuid()
ECO_DIR = os.path.join(HOME, ".config/hypr/eco")
RULES_FILE = os.path.join(ECO_DIR, "rules.json")
SETTINGS_FILE = os.path.join(HOME, ".config/hypr/settings.json")
STATE_FILE = "/tmp/qs_eco_state.json"
ANR_MARKER = "/tmp/qs_eco_anr"
LOG_FILE = "/tmp/qs_eco.log"
PID_FILE = "/tmp/qs_eco.pid"
MANAGER_PREFIX = f"/user.slice/user-{UID}.slice/user@{UID}.service/app.slice/"
PROTECTED_COMMS = {"hyprland", "quickshell", "systemd", "dbus-daemon", "dbus-broker", "pipewire",
                   "wireplumber", "pipewire-pulse", "hypridle", "hyprlock", "kitty", "foot",
                   "alacritty", "wezterm", "sshd", "ananicy-cpp", "swayosd-server", "awww-daemon"}
LADDER = {"never": 0, "throttle": 1, "freeze": 2}
GENERIC_AUDIO = ("chromium", "webrtc", "voiceengine", "electron", "chrome")

DEFAULT_RULES = {
    "_comment": "class (lowercase) -> {level: never|throttle|freeze, cpuQuota: '20%', throttleSecs, freezeSecs}. Unlisted classes are never touched. freeze needs the window on a hidden workspace; audio/mic/screen-capture always exempts.",
    "rules": {
        "spotify": {"level": "throttle", "cpuQuota": "20%"},
        "vesktop": {"level": "throttle", "cpuQuota": "25%"},
        "discord": {"level": "throttle", "cpuQuota": "25%"},
        "org.telegram.desktop": {"level": "freeze"},
        "telegram-desktop": {"level": "freeze"},
        "telegramdesktop": {"level": "freeze"},
        "vivaldi-stable": {"level": "freeze"},
        "firefox": {"level": "freeze"},
        "chromium": {"level": "freeze"},
        "google-chrome": {"level": "freeze"},
        "steam": {"level": "throttle", "cpuQuota": "25%"},
        "steamwebhelper": {"level": "freeze"},
        "kitty": {"level": "never"},
        "foot": {"level": "never"},
        "alacritty": {"level": "never"},
        "com.obsproject.studio": {"level": "never"},
        "obs": {"level": "never"},
    },
}

_log_lock = threading.Lock()


def log(msg):
    line = time.strftime("%H:%M:%S ") + msg + "\n"
    with _log_lock:
        try:
            with open(LOG_FILE, "a") as f:
                f.write(line)
        except OSError:
            pass


def run(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


MAILBOX = "/tmp/qs_claude_mailbox.json"


def mailbox_post(to, msg, frm="eco"):
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


def jload(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def jsave(path, obj):
    try:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except OSError:
        pass


def cgroup_path(pid):
    try:
        with open(f"/proc/{pid}/cgroup") as f:
            for line in f:
                if line.startswith("0::"):
                    return line[3:].strip()
    except OSError:
        pass
    return ""


def is_managed(cg):
    return cg.startswith(MANAGER_PREFIX) and cg.rsplit("/", 1)[-1].endswith((".scope", ".service"))


def cg_dir(cg):
    return "/sys/fs/cgroup" + cg


def cg_pids(cg):
    try:
        with open(cg_dir(cg) + "/cgroup.procs") as f:
            return [int(x) for x in f.read().split()]
    except (OSError, ValueError):
        return []


def comm_of(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip().lower()
    except OSError:
        return ""


_ppid_cache = None


def ppid_children():
    global _ppid_cache
    if _ppid_cache is None:
        m = {}
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open(f"/proc/{name}/stat", "rb") as f:
                    data = f.read()
                ppid = int(data[data.rindex(b")") + 2:].split()[1])
            except (OSError, ValueError):
                continue
            m.setdefault(ppid, []).append(int(name))
        _ppid_cache = m
    return _ppid_cache


def reset_ppid_cache():
    global _ppid_cache
    _ppid_cache = None


def tree_pids(pid):
    m = ppid_children()
    out, stack = [], [pid]
    while stack:
        p = stack.pop()
        out.append(p)
        stack.extend(m.get(p, []))
    return out


def unit_of(cg):
    return cg.rsplit("/", 1)[-1]


def protected_unit(cg):
    return any(comm_of(p) in PROTECTED_COMMS for p in cg_pids(cg))


def set_quota(cg, quota):
    val = quota if quota else ""
    r = subprocess.run(["systemctl", "--user", "set-property", "--runtime", unit_of(cg), f"CPUQuota={val}"],
                       capture_output=True, text=True, timeout=8)
    return r.returncode == 0


def cg_freeze(cg, on):
    try:
        with open(cg_dir(cg) + "/cgroup.freeze", "w") as f:
            f.write("1" if on else "0")
        return True
    except OSError:
        return False


def sigstop_tree(pid):
    out = {}
    for _ in range(2):
        reset_ppid_cache()
        for p in tree_pids(pid):
            if p in out:
                continue
            try:
                ct = psutil.Process(p).create_time()
                os.kill(p, signal.SIGSTOP)
                out[p] = ct
            except (psutil.Error, OSError):
                pass
    return out


def sigcont_pids(pmap):
    for p, ct in pmap.items():
        try:
            if abs(psutil.Process(p).create_time() - ct) < 1:
                os.kill(p, signal.SIGCONT)
        except (psutil.Error, OSError):
            pass


def anr_set(disabled):
    if disabled:
        if not os.path.exists(ANR_MARKER):
            open(ANR_MARKER, "w").close()
            run(["hyprctl", "keyword", "misc:enable_anr_dialog", "false"])
    else:
        if os.path.exists(ANR_MARKER):
            run(["hyprctl", "keyword", "misc:enable_anr_dialog", "true"])
            try:
                os.remove(ANR_MARKER)
            except OSError:
                pass


class Eco:
    def __init__(self):
        self.wake = threading.Event()
        self.dirty_audio = True
        self.focus_addr = ""
        self.urgent = set()
        self.unfocus_since = {}
        self.hidden_since = {}
        self.applied = {}
        self.last_groups = {}
        self.last_dump = ""
        self.last_reason = {}
        self.audio = {"tokens": set(), "pids": set(), "generic": False, "capture": False, "ts": 0}
        self.rules = {}
        self.rules_mtime = 0
        self.cfg = {"enabled": True, "throttle": 20, "freeze": 300}
        self.settings_mtime = 0
        self.stop = False
        self.capture_ts = 0
        self.capture_cache = False

    def load_config(self):
        try:
            m = os.stat(RULES_FILE).st_mtime
        except OSError:
            m = 0
        if m != self.rules_mtime:
            self.rules_mtime = m
            data = jload(RULES_FILE, DEFAULT_RULES)
            self.rules = {k.lower(): v for k, v in data.get("rules", {}).items()}
            log(f"rules loaded ({len(self.rules)} classes)")
        try:
            m = os.stat(SETTINGS_FILE).st_mtime
        except OSError:
            m = 0
        if m != self.settings_mtime:
            self.settings_mtime = m
            s = jload(SETTINGS_FILE, {})
            self.cfg = {
                "enabled": s.get("ecoModeEnabled", True) is not False,
                "throttle": float(s.get("ecoThrottleSecs", 20) or 20),
                "freeze": float(s.get("ecoFreezeSecs", 300) or 300),
            }
            log(f"settings: {self.cfg}")

    def poke(self, win=False, audio=False):
        if audio:
            self.dirty_audio = True
        self.wake.set()

    def hypr_socket(self):
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        base = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{UID}") + "/hypr"
        cand = [f"{base}/{sig}/.socket2.sock"] if sig else []
        cand += sorted(glob.glob(f"{base}/*/.socket2.sock"), key=os.path.getmtime, reverse=True)
        for c in cand:
            if os.path.exists(c):
                return c
        return None

    def event_thread(self):
        while not self.stop:
            path = self.hypr_socket()
            if not path:
                time.sleep(3)
                continue
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(path)
                buf = b""
                while not self.stop:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        self.on_event(line.decode(errors="replace"))
            except OSError:
                pass
            time.sleep(2)

    def on_event(self, line):
        name, _, data = line.partition(">>")
        if name == "activewindowv2":
            self.focus_addr = data.strip().lower().replace("0x", "")
            self.urgent.discard(self.focus_addr)
            self.poke(win=True)
        elif name == "urgent":
            self.urgent.add(data.strip().lower().replace("0x", ""))
            self.poke(win=True)
        elif name in ("workspacev2", "openwindow", "closewindow", "movewindowv2", "focusedmonv2",
                      "activespecialv2", "fullscreen", "monitoraddedv2", "monitorremovedv2"):
            self.poke(win=True)

    def audio_thread(self):
        while not self.stop:
            try:
                p = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE, text=True)
                for line in (p.stdout or []):
                    if "sink-input" in line or "source-output" in line:
                        self.poke(audio=True)
                    if self.stop:
                        break
                p.kill()
            except Exception:
                pass
            time.sleep(3)

    def refresh_audio(self):
        tokens, pids, generic, capture = set(), set(), False, False

        def eat(items):
            nonlocal generic
            for it in items:
                if it.get("corked"):
                    continue
                pr = it.get("properties", {})
                for k in ("application.name", "application.process.binary", "application.id",
                          "pipewire.access.portal.app_id", "media.name"):
                    v = pr.get(k)
                    if v:
                        t = v.lower()
                        tokens.add(t)
                        if any(g in t for g in GENERIC_AUDIO):
                            generic = True
                pid = pr.get("application.process.id")
                if pid and str(pid).isdigit():
                    pids.add(int(pid))

        for kind in ("sink-inputs", "source-outputs"):
            try:
                eat(json.loads(run(["pactl", "-f", "json", "list", kind]) or "[]"))
            except ValueError:
                pass
        if time.time() - self.capture_ts > 10:
            self.capture_ts = time.time()
            self.capture_cache = False
            try:
                for n in json.loads(run(["pw-dump"], 8) or "[]"):
                    info = n.get("info", {})
                    pr = info.get("props", {})
                    if pr.get("media.class") == "Stream/Input/Video" and info.get("state") == "running":
                        self.capture_cache = True
            except ValueError:
                pass
        capture = self.capture_cache
        self.audio = {"tokens": tokens, "pids": pids, "generic": generic, "capture": capture, "ts": time.time()}

    def snapshot(self):
        try:
            clients = json.loads(run(["hyprctl", "-j", "clients"]) or "[]")
            mons = json.loads(run(["hyprctl", "-j", "monitors"]) or "[]")
            act = json.loads(run(["hyprctl", "-j", "activewindow"]) or "{}")
        except ValueError:
            return None
        if isinstance(act, dict):
            self.focus_addr = (act.get("address") or "").lower().replace("0x", "")
        visible = set()
        for m in mons:
            visible.add(m.get("activeWorkspace", {}).get("id"))
            sp = m.get("specialWorkspace", {})
            if sp and sp.get("id"):
                visible.add(sp["id"])
        return clients, visible

    def build_groups(self, clients, visible, now):
        seen = set()
        groups = {}
        for c in clients:
            if not c.get("mapped", True):
                continue
            addr = c.get("address", "").lower().replace("0x", "")
            seen.add(addr)
            pid = c.get("pid", 0)
            if pid <= 1:
                continue
            focused = addr == self.focus_addr
            is_vis = c.get("workspace", {}).get("id") in visible and not c.get("hidden", False)
            if focused:
                self.unfocus_since.pop(addr, None)
            else:
                self.unfocus_since.setdefault(addr, now)
            if is_vis:
                self.hidden_since.pop(addr, None)
            else:
                self.hidden_since.setdefault(addr, now)
            cg = cgroup_path(pid)
            key = ("cg", cg) if is_managed(cg) else ("pid", pid)
            g = groups.setdefault(key, {"key": key, "cg": cg if key[0] == "cg" else "", "pid": pid,
                                        "windows": []})
            cls = (c.get("class") or "").lower()
            g["windows"].append({
                "addr": addr, "class": cls, "initial": (c.get("initialClass") or "").lower(), "pid": pid,
                "title": c.get("title") or "", "ws": c.get("workspace", {}).get("id"),
                "focused": focused, "fullscreen": bool(c.get("fullscreen")),
                "urgent": addr in self.urgent, "visible": is_vis,
                "unfocus": now - self.unfocus_since.get(addr, now),
                "hidden": now - self.hidden_since.get(addr, now) if not is_vis else 0,
            })
        for d in (self.unfocus_since, self.hidden_since):
            for a in [a for a in d if a not in seen]:
                d.pop(a, None)
        return groups

    def group_tokens(self, g):
        toks, pids = set(), set()
        for w in g["windows"]:
            toks.add(w["class"])
            if w["initial"]:
                toks.add(w["initial"])
            pids.update(tree_pids(w["pid"]))
        if g["cg"]:
            pids.update(cg_pids(g["cg"]))
        for p in list(pids)[:64]:
            c = comm_of(p)
            if c:
                toks.add(c)
        return {t for t in toks if len(t) >= 3}, pids

    def audio_hit(self, toks, pids, audio):
        if audio["pids"] & pids:
            return True
        for at in audio["tokens"]:
            for t in toks:
                if t in at or at in t:
                    return True
        return False

    def decide(self, g, now, cfg, audio, rules):
        ws = g["windows"]
        allowed = 3
        quota = "20%"
        thr_s, frz_s = cfg["throttle"], cfg["freeze"]
        vis_ok = True
        for w in ws:
            r = rules.get(w["class"]) or rules.get(w["initial"]) or {}
            lvl = LADDER.get(r.get("level", "never"), 0)
            allowed = min(allowed, lvl)
            if r.get("cpuQuota"):
                quota = r["cpuQuota"]
            thr_s = max(thr_s, float(r.get("throttleSecs", 0) or 0))
            frz_s = max(frz_s, float(r.get("freezeSecs", 0) or 0))
            vis_ok = vis_ok and r.get("throttleVisible", lvl == 1)
        if allowed == 0:
            return 0, "rule:never", quota, None
        for w in ws:
            if w["focused"]:
                return 0, "focused", quota, None
            if w["fullscreen"]:
                return 0, "fullscreen", quota, None
            if w["urgent"]:
                return 0, "urgent", quota, None
        unf = min(w["unfocus"] for w in ws)
        hid = min(w["hidden"] for w in ws)
        all_hidden = all(not w["visible"] for w in ws)
        target, hints = 0, []
        thr_ok = all_hidden or vis_ok
        if unf >= thr_s and thr_ok:
            target = 1
        elif thr_ok:
            hints.append(thr_s - unf)
        if allowed >= 2 and all_hidden:
            if hid >= frz_s and unf >= thr_s:
                target = 2
            else:
                hints.append(max(frz_s - hid, thr_s - unf))
        hint = min(hints) if hints else None
        if target == 0:
            return 0, "waiting", quota, hint
        if audio["capture"]:
            return 0, "capture-active", quota, hint
        toks, pids = self.group_tokens(g)
        if audio["generic"] and any(c in t for t in toks for c in ("vesktop", "discord", "chrom", "vivaldi", "electron", "spotify", "telegram", "firefox", "steam")):
            return 0, "generic-stream-active", quota, hint
        if self.audio_hit(toks, pids, audio):
            return 0, "audio-active", quota, hint
        if g["cg"] and protected_unit(g["cg"]):
            return 0, "protected-unit", quota, hint
        if os.getpid() in pids:
            return 0, "self", quota, hint
        return target, "eligible", quota, hint

    def apply(self, g, target, quota, cls):
        key = g["key"]
        cur = self.applied.get(key)
        cur_level = cur["level"] if cur else 0
        if cur_level == target:
            return
        cg = g["cg"]
        if target < cur_level:
            self.restore(key, keep_level=target, cls=cls, quota=quota, g=g)
            if target == 0:
                return
            cur = self.applied.get(key)
            cur_level = cur["level"] if cur else 0
        if target >= 1 and cur_level < 1:
            if cg:
                if set_quota(cg, quota):
                    self.applied[key] = {"class": cls, "pid": g["pid"], "level": 1, "since": int(time.time()),
                                         "method": "quota", "cg": cg, "quota": quota, "sigpids": {}}
                    log(f"THROTTLE {cls} pid={g['pid']} unit={unit_of(cg)} quota={quota}")
            elif target == 1:
                if self.last_reason.get(("nothrottle", key)) is None:
                    self.last_reason[("nothrottle", key)] = 1
                    log(f"skip throttle {cls}: not in a user scope (nice/sched cannot be undone unprivileged)")
        if target >= 2:
            ent = self.applied.get(key) or {"class": cls, "pid": g["pid"], "level": 1, "since": int(time.time()),
                                            "method": "none", "cg": cg, "quota": None, "sigpids": {}}
            anr_set(True)
            if cg and cg_freeze(cg, True):
                ent.update(level=2, method="cgfreeze", since=int(time.time()))
                log(f"FREEZE {cls} pid={g['pid']} unit={unit_of(cg)} (cgroup.freeze)")
            else:
                sp = sigstop_tree(g["pid"])
                ent.update(level=2, method="sigstop", sigpids=sp, since=int(time.time()))
                log(f"FREEZE {cls} pid={g['pid']} SIGSTOP x{len(sp)}")
            if cur_level < 2:
                mailbox_post("user", f"Eco mode froze {cls} (unfocused/hidden a while)", frm="eco")
            self.applied[key] = ent
        self.write_state()

    def restore(self, key, keep_level=0, cls="", quota=None, g=None):
        ent = self.applied.get(key)
        if not ent:
            return
        if ent["level"] >= 2 and keep_level < 2:
            if ent["method"] == "cgfreeze":
                cg_freeze(ent["cg"], False)
            else:
                sigcont_pids({int(p): ct for p, ct in ent["sigpids"].items()})
            log(f"THAW {ent['class']} pid={ent['pid']}")
            ent["level"] = 1 if ent.get("method") != "sigstop" and ent.get("quota") else 0
            ent["sigpids"] = {}
        if keep_level < 1 and ent.get("quota") is not None and ent.get("cg"):
            set_quota(ent["cg"], "")
            log(f"UNTHROTTLE {ent['class']} pid={ent['pid']}")
            ent["level"] = 0
        if ent["level"] == 0 or keep_level == 0:
            self.applied.pop(key, None)
        if not any(e["level"] >= 2 for e in self.applied.values()):
            anr_set(False)
        self.write_state()

    def restore_all(self):
        for key in list(self.applied):
            try:
                self.restore(key)
            except Exception as e:
                log(f"restore error {e}")
        anr_set(False)
        self.write_state()

    def write_state(self):
        out = []
        for key, e in self.applied.items():
            wins = [{"addr": w["addr"], "class": w["class"], "title": w.get("title", ""), "ws": w.get("ws")}
                    for w in self.last_groups.get(key, {}).get("windows", [])]
            out.append({"class": e["class"], "pid": e["pid"], "level": "freeze" if e["level"] >= 2 else "throttle",
                        "since": e["since"], "method": e["method"], "cg": e.get("cg", ""),
                        "quota": e.get("quota"), "sigpids": e.get("sigpids", {}), "wins": wins})
        dumped = json.dumps(out, sort_keys=True)
        if dumped == self.last_dump:
            return
        self.last_dump = dumped
        jsave(STATE_FILE, out)

    def evaluate(self):
        self.load_config()
        if not self.cfg["enabled"]:
            if self.applied:
                log("eco disabled -> restoring all")
                self.restore_all()
            return 30
        now = time.time()
        reset_ppid_cache()
        if self.dirty_audio or now - self.audio["ts"] > 5:
            self.dirty_audio = False
            self.refresh_audio()
        snap = self.snapshot()
        if snap is None:
            return 5
        clients, visible = snap
        groups = self.build_groups(clients, visible, now)
        self.last_groups = groups
        next_wait = 30.0
        for key in [k for k in self.applied if k not in groups]:
            self.restore(key)
        for key, g in groups.items():
            cls = g["windows"][0]["class"]
            target, reason, quota, hint = self.decide(g, now, self.cfg, self.audio, self.rules)
            if reason != self.last_reason.get(key):
                self.last_reason[key] = reason
                if target == 0 and reason != "rule:never":
                    log(f"{cls}: exempt ({reason})")
            self.apply(g, target, quota, cls)
            if hint is not None and hint > 0:
                next_wait = min(next_wait, hint + 0.2)
        if self.applied:
            next_wait = min(next_wait, 5.0)
            self.write_state()
        return max(0.3, next_wait)

    def sweep(self):
        state = jload(STATE_FILE, [])
        for e in state:
            try:
                if e.get("method") == "cgfreeze" and e.get("cg"):
                    cg_freeze(e["cg"], False)
                if e.get("method") == "sigstop":
                    sigcont_pids({int(p): ct for p, ct in (e.get("sigpids") or {}).items()})
                if e.get("cg") and e.get("quota") is not None:
                    set_quota(e["cg"], "")
                log(f"sweep restored {e.get('class')} pid={e.get('pid')}")
            except Exception as ex:
                log(f"sweep error {ex}")
        jsave(STATE_FILE, [])
        anr_set(False)

    def run(self):
        self.sweep()
        threading.Thread(target=self.event_thread, daemon=True).start()
        threading.Thread(target=self.audio_thread, daemon=True).start()
        log("eco daemon started")
        wait = 1.0
        while not self.stop:
            self.wake.wait(wait)
            woke = self.wake.is_set()
            self.wake.clear()
            try:
                wait = self.evaluate()
                if woke and self.applied:
                    wait = min(wait, 2.0)
            except Exception as ex:
                log(f"evaluate error: {ex!r}")
                wait = 3.0
        self.restore_all()


def single_instance():
    try:
        old = int(open(PID_FILE).read().strip())
        if old != os.getpid() and os.path.exists(f"/proc/{old}"):
            with open(f"/proc/{old}/cmdline") as f:
                if "eco_daemon" in f.read():
                    return False
    except (OSError, ValueError):
        pass
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    return True


def ensure_rules():
    os.makedirs(ECO_DIR, exist_ok=True)
    if not os.path.exists(RULES_FILE):
        jsave(RULES_FILE, DEFAULT_RULES)


def main():
    if "--thaw" in sys.argv:
        Eco().sweep()
        print("thawed")
        return
    if "--selftest" in sys.argv:
        import eco_selftest
        return eco_selftest.main(Eco)
    if not single_instance():
        return
    ensure_rules()
    if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 1_000_000:
        os.remove(LOG_FILE)
    eco = Eco()

    def bye(*_):
        eco.stop = True
        eco.wake.set()

    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(s, bye)
    atexit.register(eco.restore_all)
    atexit.register(lambda: os.path.exists(PID_FILE) and os.remove(PID_FILE))
    eco.run()


if __name__ == "__main__":
    main()
