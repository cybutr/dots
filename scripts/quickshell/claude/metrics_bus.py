#!/usr/bin/env python3
import os, json, time, subprocess, re

OUT = os.path.expanduser("~/.cache/quickshell/claude/live_metrics.json")
PIDF = os.path.expanduser("~/.cache/quickshell/claude/metrics_bus.pid")
INTERVAL = 2.5


def run(cmd, timeout=2):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


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


def mem_percent():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            info[k] = int(v.strip().split()[0])
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", 0)
    return round(100 * (total - avail) / total, 1) if total else None


def temp_c():
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


def battery_percent():
    out = run(["bash", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1"])
    try:
        return int(out)
    except Exception:
        return None


def volume_percent():
    out = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    m = re.search(r"[\d.]+", out)
    if not m:
        return None
    try:
        return round(float(m.group()) * 100)
    except Exception:
        return None


def collect():
    metrics = {}
    try:
        v = cpu_percent()
        if v is not None:
            metrics["cpu"] = v
    except Exception:
        pass
    try:
        v = mem_percent()
        if v is not None:
            metrics["mem"] = v
    except Exception:
        pass
    try:
        v = temp_c()
        if v is not None:
            metrics["temp"] = v
    except Exception:
        pass
    try:
        v = battery_percent()
        if v is not None:
            metrics["battery"] = v
    except Exception:
        pass
    try:
        v = volume_percent()
        if v is not None:
            metrics["volume"] = v
    except Exception:
        pass
    return metrics


def write(metrics):
    metrics["ts"] = int(time.time())
    tmp = OUT + ".tmp"
    try:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(metrics, f)
        os.replace(tmp, OUT)
    except OSError:
        pass


def main():
    try:
        os.makedirs(os.path.dirname(PIDF), exist_ok=True)
        with open(PIDF, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    while True:
        write(collect())
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
