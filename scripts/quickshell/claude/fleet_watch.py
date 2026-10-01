#!/usr/bin/env python3
import os, sys, json, time, fcntl, shutil, socket, subprocess
import urllib.request, urllib.error
from datetime import datetime

INTERVAL = 15
BACKOFF_MAX = 120
PORT = 8780
HUB_NAME = "basecamp"
DEVICE = "laptop"
ONLINE_SECS = 90
STALE_SECS = 600
HYPRIDLE_IDLE_SECS = 500
OUT = "/tmp/qs_fleet.json"
LOCK = "/tmp/qs_fleet_watch.lock"
PC_IDLE = "/tmp/qs_pc_idle"
SETTINGS = os.path.expanduser("~/.config/hypr/settings.json")
STATE_DIR = os.path.expanduser("~/.local/state/fleet")
TOKENS_ENV = os.path.join(STATE_DIR, "tokens.env")
STAT_KEYS = ("data", "payload", "stats", "status", "snapshot", "latest", "last")
TS_KEYS = ("last_seen", "lastSeen", "received_at", "receivedAt", "ts", "updated_at", "updated", "seen", "agent_ts")


def log(*a):
    print("[fleet-watch]", *a, file=sys.stderr, flush=True)


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def _save(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def _run(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


def env():
    out = {}
    try:
        with open(TOKENS_ENV) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k and not k.startswith("#"):
                    out[k] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def tailnet():
    try:
        d = json.loads(_run(["tailscale", "status", "--json"]) or "{}")
    except ValueError:
        return False, None
    if d.get("BackendState") != "Running":
        return False, None
    for p in (d.get("Peer") or {}).values():
        name = (p.get("DNSName") or p.get("HostName") or "").split(".")[0].lower()
        if name == HUB_NAME and p.get("TailscaleIPs"):
            return True, {"ip": p["TailscaleIPs"][0], "online": bool(p.get("Online"))}
    return True, None


def hub_url(peer, cfg):
    override = (_load(SETTINGS, {}) or {}).get("fleetHubUrl") or ""
    if override:
        return override.rstrip("/")
    if peer:
        return f"http://{peer['ip']}:{PORT}"
    return (cfg.get("FLEET_URL") or "").rstrip("/")


def _http(method, url, token, body=None, timeout=6):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


_cpu_prev = None


def cpu_pct():
    global _cpu_prev
    try:
        with open("/proc/stat") as f:
            v = [int(x) for x in f.readline().split()[1:]]
    except OSError:
        return None
    idle, total = v[3] + v[4], sum(v)
    prev, _cpu_prev = _cpu_prev, (idle, total)
    if not prev or total <= prev[1]:
        return None
    return round(100 * (1 - (idle - prev[0]) / (total - prev[1])), 1)


def mem():
    m = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":", 1)
                m[k] = int(v.split()[0])
    except (OSError, ValueError):
        return None, None
    total, avail = m.get("MemTotal", 0), m.get("MemAvailable", 0)
    if not total:
        return None, None
    return round(total / 1048576, 1), round(100 * (1 - avail / total), 1)


def disks():
    out = []
    for mp in ("/", os.path.expanduser("~")):
        try:
            u = shutil.disk_usage(mp)
        except OSError:
            continue
        row = {"drive": mp, "total_gb": round(u.total / 1e9, 1), "free_gb": round(u.free / 1e9, 1),
               "used_pct": round(100 * u.used / u.total, 1) if u.total else 0}
        if not any(r["total_gb"] == row["total_gb"] and r["free_gb"] == row["free_gb"] for r in out):
            out.append(row)
    return out


def uptime_s():
    try:
        with open("/proc/uptime") as f:
            return int(float(f.read().split()[0]))
    except (OSError, ValueError):
        return None


def idle_s():
    try:
        return int(time.time() - os.path.getmtime(PC_IDLE)) + HYPRIDLE_IDLE_SECS
    except OSError:
        return 0


def foreground():
    try:
        return (json.loads(_run(["hyprctl", "activewindow", "-j"]) or "{}").get("class") or None)
    except ValueError:
        return None


def gpu():
    if not shutil.which("nvidia-smi"):
        return None
    line = _run(["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total",
                 "--format=csv,noheader,nounits"]).strip().splitlines()
    if not line:
        return None
    p = [x.strip() for x in line[0].split(",")]
    try:
        return {"name": p[0], "util_pct": int(p[1]), "temp_c": int(p[2]), "mem_used_mb": int(p[3]), "mem_total_mb": int(p[4])}
    except (IndexError, ValueError):
        return None


def os_name():
    try:
        with open("/etc/os-release") as f:
            kv = dict(l.rstrip().split("=", 1) for l in f if "=" in l)
        return kv.get("PRETTY_NAME", "Linux").strip('"') + " " + os.uname().release
    except OSError:
        return "Linux " + os.uname().release


def heartbeat():
    ram_total, ram_used = mem()
    return {
        "host": socket.gethostname(),
        "os": os_name(),
        "cpu_pct": cpu_pct(),
        "ram_total_gb": ram_total,
        "ram_used_pct": ram_used,
        "disks": disks(),
        "uptime_s": uptime_s(),
        "idle_s": idle_s(),
        "foreground": foreground(),
        "gpu": gpu(),
        "agent_ts": int(time.time()),
    }


def _ts(v):
    if isinstance(v, (int, float)):
        return v / 1000 if v > 1e11 else float(v)
    if isinstance(v, str) and v:
        try:
            return datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp()
        except ValueError:
            try:
                return float(v)
            except ValueError:
                return None
    return None


def _num(v):
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def _containers(st):
    raw = st.get("containers") or st.get("docker") or []
    if isinstance(raw, dict):
        raw = [dict(v, name=k) if isinstance(v, dict) else {"name": k, "state": v} for k, v in raw.items()]
    out = []
    for c in raw if isinstance(raw, list) else []:
        if not isinstance(c, dict):
            continue
        state = str(c.get("state") or c.get("status") or "").lower()
        up = c.get("up", c.get("running"))
        if up is None:
            up = state.startswith("running") or state.startswith("up")
        name = (c.get("name") or c.get("Names") or "?")
        if isinstance(name, list):
            name = name[0] if name else "?"
        out.append({"name": str(name).lstrip("/"), "up": bool(up), "status": state})
    return out


def _device(name, rec, now):
    if not isinstance(rec, dict):
        rec = {}
    st = rec
    for k in STAT_KEYS:
        if isinstance(rec.get(k), dict):
            st = dict(rec[k])
            break
    name = str(rec.get("device") or rec.get("name") or rec.get("id") or name or "?")
    seen = None
    for k in TS_KEYS:
        seen = _ts(rec.get(k)) if k in rec else _ts(st.get(k))
        if seen:
            break
    age = max(0, now - seen) if seen else None
    if age is not None:
        state = "online" if age < ONLINE_SECS else ("stale" if age < STALE_SECS else "offline")
    elif isinstance(rec.get("online"), bool):
        state = "online" if rec["online"] else "offline"
    else:
        state = "offline"
    dl = [d for d in (st.get("disks") or []) if isinstance(d, dict)]
    disk_pct = max((_num(d.get("used_pct")) or 0 for d in dl), default=None)
    if disk_pct is None:
        disk_pct = _num(st.get("disk_pct") or st.get("disk_used_pct"))
    g = st.get("gpu") if isinstance(st.get("gpu"), dict) else None
    return {
        "name": name,
        "state": state,
        "last_seen": seen,
        "age_s": int(age) if age is not None else None,
        "host": st.get("host") or "",
        "os": st.get("os") or "",
        "cpu_pct": _num(st.get("cpu_pct", st.get("cpu"))),
        "ram_used_pct": _num(st.get("ram_used_pct", st.get("mem_pct"))),
        "ram_total_gb": _num(st.get("ram_total_gb")),
        "disk_pct": disk_pct,
        "disks": dl,
        "uptime_s": _num(st.get("uptime_s")),
        "idle_s": _num(st.get("idle_s")),
        "foreground": st.get("foreground") or "",
        "gpu_pct": _num(g.get("util_pct")) if g else None,
        "containers": _containers(st),
    }


def normalize(raw, now):
    src = raw
    hub_ts = _ts(raw.get("ts")) if isinstance(raw, dict) else None
    skew = now - hub_ts if hub_ts else 0
    if isinstance(raw, dict):
        for k in ("devices", "fleet", "items", "nodes"):
            if k in raw:
                src = raw[k]
                break
    if isinstance(src, dict):
        items = list(src.items())
    elif isinstance(src, list):
        items = [(None, r) for r in src]
    else:
        items = []
    devs = [_device(n, r, now - skew) for n, r in items]
    for d in devs:
        if d["last_seen"]:
            d["last_seen"] += skew
    order = {"laptop": 0, "windows": 1, "vps": 2, "phone": 3}
    devs.sort(key=lambda d: (order.get(d["name"], 9), d["name"]))
    return devs


def refresh_ages(devs, now):
    for d in devs:
        if d.get("last_seen"):
            age = max(0, now - d["last_seen"])
            d["age_s"] = int(age)
            d["state"] = "online" if age < ONLINE_SECS else ("stale" if age < STALE_SECS else "offline")
    return devs


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("already running")
        return
    prev = _load(OUT, {})
    devices = prev.get("devices") if isinstance(prev.get("devices"), list) else []
    last_ok = prev.get("last_ok") or 0
    delay = INTERVAL
    cpu_pct()
    while True:
        now = time.time()
        up, peer = tailnet()
        cfg = env()
        url = hub_url(peer, cfg)
        out = {"ts": int(now), "tailnet": up, "hub": url, "ok": False, "error": "", "push": "", "last_ok": last_ok}
        if not up:
            out["error"] = "tailnet down"
        elif not url:
            out["error"] = "hub not on tailnet"
        elif not cfg.get("FLEET_TOKEN_LAPTOP"):
            out["error"] = "no laptop token"
        else:
            try:
                _http("POST", f"{url}/ingest/{DEVICE}", cfg["FLEET_TOKEN_LAPTOP"], heartbeat())
                out["push"] = "ok"
            except urllib.error.HTTPError as e:
                out["push"] = f"http {e.code}"
            except Exception as e:
                out["push"] = type(e).__name__
            try:
                raw = _http("GET", f"{url}/fleet", cfg.get("FLEET_READ_TOKEN", ""))
                devices = normalize(raw, time.time())
                out["ok"] = True
                last_ok = out["last_ok"] = int(time.time())
            except urllib.error.HTTPError as e:
                out["error"] = f"http {e.code}"
            except Exception as e:
                out["error"] = type(e).__name__
        out["devices"] = refresh_ages(devices, time.time())
        try:
            _save(OUT, out)
        except OSError:
            pass
        delay = INTERVAL if out["ok"] else min(BACKOFF_MAX, delay * 2)
        time.sleep(delay)


if __name__ == "__main__":
    if "--once" in sys.argv:
        print(json.dumps(heartbeat(), indent=1))
    else:
        main()
