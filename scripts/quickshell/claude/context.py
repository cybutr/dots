#!/usr/bin/env python3
import os, sys, json, subprocess, time, re

HOME = os.path.expanduser("~")
QS = os.path.join(HOME, ".config/hypr/scripts/quickshell")
OUT = "/tmp/qs_context.json"


def run(cmd, timeout=2):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def sys_info():
    out = run(["bash", os.path.join(QS, "sys_info.sh")])
    try:
        return json.loads(out)
    except Exception:
        return {}


def mic_state():
    # `short` is a single tiny query (id name driver format state) — far lighter
    # on pipewire-pulse than the verbose `list sources`.
    out = run(["pactl", "list", "sources", "short"])
    active = []
    for line in out.splitlines():
        cols = line.split("\t")
        if len(cols) < 2:
            continue
        name = cols[1]
        if "input" in name.lower() and "RUNNING" in line:
            active.append(name)
    return {"on": bool(active), "sources": active}


def cpu_percent():
    def snap():
        with open("/proc/stat") as f:
            parts = f.readline().split()[1:]
        vals = list(map(int, parts))
        idle = vals[3] + vals[4]
        return sum(vals), idle
    t1, i1 = snap()
    time.sleep(0.15)
    t2, i2 = snap()
    dt, di = t2 - t1, i2 - i1
    return round(100 * (dt - di) / dt, 1) if dt > 0 else 0.0


def mem():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            info[k] = int(v.strip().split()[0])
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", 0)
    used_pct = round(100 * (total - avail) / total, 1) if total else 0
    return {"total_mb": total // 1024, "used_pct": used_pct}


def temp():
    out = run(["sensors", "-j"], timeout=2)
    try:
        data = json.loads(out)
    except Exception:
        return None
    best = None
    for fields in data.values():
        for fname, fvals in fields.items():
            if not isinstance(fvals, dict):
                continue
            for k, v in fvals.items():
                if "_input" in k and ("temp" in fname.lower() or "Tctl" in fname or "Package" in fname or "Core" in fname):
                    if best is None or v > best:
                        best = v
    return round(best, 1) if best is not None else None


def top_proc():
    out = run(["ps", "-eo", "comm,%cpu", "--sort=-%cpu", "--no-headers"], timeout=2)
    line = out.splitlines()[0] if out else ""
    m = re.match(r"(\S+)\s+([\d.]+)", line)
    return {"name": m.group(1), "cpu": float(m.group(2))} if m else None


def uptime():
    try:
        with open("/proc/uptime") as f:
            secs = int(float(f.read().split()[0]))
        h, rem = divmod(secs, 3600)
        return f"{h}h {rem // 60}m"
    except Exception:
        return ""


def proc_stats():
    try:
        load = open("/proc/loadavg").read().split()[:3]
    except Exception:
        load = []
    return {
        "cpu_pct": cpu_percent(),
        "load": [float(x) for x in load],
        "cores": os.cpu_count(),
        "mem": mem(),
        "temp_c": temp(),
        "top": top_proc(),
        "uptime": uptime(),
    }


def schedule():
    cache = load_json(os.path.join(HOME, ".local/share/qs_schedule_cache.json"), {})
    current = load_json("/tmp/qs_current_event.json", {})
    now = int(time.time())
    events, tasks = [], []
    for l in cache.get("lessons", []):
        if l.get("type") != "class":
            continue
        if l.get("time") == "Task":
            tasks.append({"title": l.get("subject", "").lstrip("󰄳 ").strip(),
                          "task_id": l.get("taskId", ""),
                          "tasklist_id": l.get("tasklistId", ""),
                          "due": l.get("start")})
        else:
            events.append({"title": l.get("subject", ""),
                           "time": l.get("time", ""),
                           "room": l.get("room", ""),
                           "start": l.get("start"),
                           "end": l.get("end"),
                           "mins_until": (l.get("start", now) - now) // 60 if l.get("start") else None})
    return {"header": cache.get("header", ""),
            "events": events,
            "tasks": tasks,
            "active": current.get("events", [])}


def workspaces():
    return load_json("/tmp/qs_workspaces.json", {})


def focus():
    out = run(["hyprctl", "activewindow", "-j"])
    try:
        w = json.loads(out)
    except Exception:
        return {}
    pid = w.get("pid")
    cwd, project = "", ""
    if pid and pid > 0:
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            cwd = ""
    if cwd:
        d = cwd
        for _ in range(8):
            if os.path.isdir(os.path.join(d, ".git")):
                project = os.path.basename(d)
                break
            nd = os.path.dirname(d)
            if nd == d:
                break
            d = nd
    return {"app": w.get("class", ""), "title": (w.get("title", "") or "")[:120],
            "cwd": cwd, "project": project}


def main():
    ctx = {
        "ts": int(time.time()),
        "system": sys_info(),
        "mic": mic_state(),
        "proc": proc_stats(),
        "schedule": schedule(),
        "workspaces": workspaces(),
        "focus": focus(),
    }
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(ctx, f)
    os.replace(tmp, OUT)
    if "--print" in sys.argv:
        print(json.dumps(ctx, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
