#!/usr/bin/env python3
"""Samples quickshell's own CPU cost + leaked-watcher count every ~10s,
writes /tmp/qs_perf.json for TopBar's quickshell-cpu chip, and emits at most
one 'Bar running hot' resident card per 10 minutes when things stay bad."""
import os, sys, time, fcntl, json, subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leak_reaper

INTERVAL = 10
CPU_HOT_PCT = 35.0
CPU_HOT_STREAK = 3
ORPHAN_HOT_COUNT = 30
CARD_COOLDOWN = 600
AUTOCLEAN_COOLDOWN = 180
OUT = "/tmp/qs_perf.json"
LOCK = "/tmp/qs_perf_watch.lock"
# Persists last_card_ts/last_autoclean_ts across perf_watch.py restarts (the
# process itself gets restarted often during active dev sessions) so a
# restart can't reset the cooldown and cause the same nag to refire minutes
# later — this was the actual cause of "leaked process" nags recurring every
# few minutes instead of the intended once-per-10-min ceiling.
STATE = "/tmp/qs_perf_watch_state.json"
HIST_LEN = 24
CLK = os.sysconf("SC_CLK_TCK")
KILL_ORPHANS_SH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "kill_orphans.sh"
)
RESIDENT_CARD = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "quickshell/claude/resident_card.py"
)


def _load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {"last_card_ts": 0, "last_autoclean_ts": 0}


def _save_state(state):
    try:
        tmp = STATE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, STATE)
    except OSError:
        pass


def _quickshell_pids():
    out = []
    try:
        raw = subprocess.run(["pgrep", "-f", "quickshell -p"], capture_output=True, text=True).stdout
        out = [int(p) for p in raw.split() if p.isdigit()]
    except Exception:
        pass
    return out


def _proc_cpu_ticks(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            raw = f.read()
        rest = raw[raw.rindex(")") + 2:].split()
        return int(rest[11]) + int(rest[12])  # utime + stime
    except (OSError, ValueError, IndexError):
        return None


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return

    prev_ticks = {}
    prev_wall = time.time()
    hist = []
    hot_streak = 0
    pstate = _load_state()
    last_card_ts = pstate.get("last_card_ts", 0)
    last_autoclean_ts = pstate.get("last_autoclean_ts", 0)

    while True:
        pids = _quickshell_pids()
        now_wall = time.time()
        dt = max(0.001, now_wall - prev_wall)
        total_ticks = 0
        cur_ticks = {}
        for pid in pids:
            t = _proc_cpu_ticks(pid)
            if t is None:
                continue
            cur_ticks[pid] = t
            if pid in prev_ticks:
                total_ticks += max(0, t - prev_ticks[pid])
        cpu_pct = min(100.0, (total_ticks / CLK) / dt * 100.0)
        prev_ticks = cur_ticks
        prev_wall = now_wall

        try:
            orphans = len(leak_reaper.scan())
        except Exception:
            orphans = 0

        hist.append(round(cpu_pct, 1))
        hist = hist[-HIST_LEN:]

        data = {
            "cpu_pct": round(cpu_pct, 1),
            "orphans": orphans,
            "hist": hist,
            "ts": int(now_wall),
        }
        try:
            tmp = OUT + ".tmp"
            with open(tmp, "w") as f:
                json.dump(data, f)
            os.replace(tmp, OUT)
        except OSError:
            pass

        hot_streak = hot_streak + 1 if cpu_pct > CPU_HOT_PCT else 0

        # Leaked processes: user wants this handled fully autonomously, not
        # asked about (standing autonomy grant covers process cleanup) — just
        # run the cleanup directly, no card, no confirmation.
        if orphans > ORPHAN_HOT_COUNT and (now_wall - last_autoclean_ts) > AUTOCLEAN_COOLDOWN:
            last_autoclean_ts = now_wall
            _save_state({"last_card_ts": last_card_ts, "last_autoclean_ts": last_autoclean_ts})
            try:
                subprocess.run(["bash", KILL_ORPHANS_SH], timeout=15, check=False,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

        # Pure CPU-hot (not just orphan count) is a different, genuinely
        # worth-surfacing condition — keep the card for that, still cooldown'd
        # and now state-persisted so a perf_watch restart can't refire it.
        if hot_streak >= CPU_HOT_STREAK and (now_wall - last_card_ts) > CARD_COOLDOWN:
            last_card_ts = now_wall
            _save_state({"last_card_ts": last_card_ts, "last_autoclean_ts": last_autoclean_ts})
            try:
                subprocess.run(
                    ["python3", RESIDENT_CARD,
                     "--title", "Bar running hot",
                     "--body", f"quickshell CPU at {cpu_pct:.0f}% for {hot_streak * INTERVAL}s+. "
                               "This slows down opening and closing widgets.",
                     "--icon", "gauge",
                     "--urgency", "normal",
                     "--source", "perf_watch"],
                    timeout=5, check=False,
                )
            except Exception:
                pass

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
