import os, sys, time, subprocess, signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from typing import Any

import psutil

d: Any = sys.modules["__main__"] if hasattr(sys.modules.get("__main__"), "Eco") else __import__("eco_daemon")

OK, BAD = [], []


def check(name, cond, extra=""):
    (OK if cond else BAD).append(name)
    print(("PASS " if cond else "FAIL ") + name + (f"  [{extra}]" if extra else ""))


def cpu_pct(pid, secs=1.0):
    p = psutil.Process(pid)
    p.cpu_percent(None)
    time.sleep(secs)
    return sum(c.cpu_percent(None) for c in [p] + p.children(recursive=True))


def quota_off(cg):
    try:
        return open(d.cg_dir(cg) + "/cpu.max").read().startswith("max")
    except OSError:
        return True


def win(cls, pid=99999, **kw):
    w = {"addr": "a", "class": cls, "initial": cls, "pid": pid, "focused": False, "fullscreen": False,
         "urgent": False, "visible": True, "unfocus": 100.0, "hidden": 0.0}
    w.update(kw)
    return {"key": ("pid", pid), "cg": "", "pid": pid, "windows": [w]}


def main(Eco):
    d.STATE_FILE = "/tmp/qs_eco_selftest_state.json"
    d.ANR_MARKER = "/tmp/qs_eco_selftest_anr"
    eco = Eco()
    eco.rules = {k.lower(): v for k, v in d.DEFAULT_RULES["rules"].items()}
    cfg = {"enabled": True, "throttle": 20, "freeze": 300}
    quiet = {"tokens": set(), "pids": set(), "generic": False, "capture": False, "ts": 0}
    playing = {"tokens": {"spotify", "firefox"}, "pids": set(), "generic": False, "capture": False, "ts": 0}

    def dec(g, audio=quiet):
        return eco.decide(g, time.time(), cfg, audio, eco.rules)[0:2]

    check("spotify unfocused idle -> throttle", dec(win("spotify"))[0] == 1)
    check("spotify audio playing -> none", dec(win("spotify"), playing)[0] == 0, dec(win("spotify"), playing)[1])
    check("spotify never freeze even hidden 999s", dec(win("spotify", visible=False, hidden=999))[0] == 1)
    check("firefox hidden 400s idle -> freeze", dec(win("firefox", visible=False, hidden=400))[0] == 2)
    check("firefox hidden 400s audio -> none", dec(win("firefox", visible=False, hidden=400), playing)[0] == 0)
    check("firefox visible unfocused -> none (no throttle for freeze-level)", dec(win("firefox"))[0] == 0)
    check("firefox hidden 100s -> throttle only", dec(win("firefox", visible=False, hidden=100))[0] == 1)
    check("focused -> none", dec(win("spotify", focused=True))[0] == 0)
    check("fullscreen -> none", dec(win("firefox", visible=False, hidden=400, fullscreen=True))[0] == 0)
    check("urgent -> none", dec(win("firefox", visible=False, hidden=400, urgent=True))[0] == 0)
    check("kitty never", dec(win("kitty", visible=False, hidden=999))[0] == 0)
    check("unknown class never", dec(win("randomapp", visible=False, hidden=999))[0] == 0)
    check("screen capture blocks all", dec(win("firefox", visible=False, hidden=400), dict(quiet, capture=True))[0] == 0)
    check("generic voice stream blocks vesktop", dec(win("vesktop"), dict(quiet, generic=True))[0] == 0)

    unit = f"eco-selftest-{os.getpid()}"
    proc = subprocess.Popen(["systemd-run", "--user", "--scope", f"--unit={unit}", "--quiet", "bash", "-c", "yes >/dev/null"],
                            stderr=subprocess.DEVNULL)
    time.sleep(1.2)
    ypid = int(subprocess.run(["pgrep", "-n", "-x", "yes"], capture_output=True, text=True).stdout.strip() or 0)
    cg = d.cgroup_path(ypid)
    check("synthetic workload in managed scope", d.is_managed(cg), cg)
    base = cpu_pct(ypid)
    check("workload burns cpu", base > 15, f"{base:.0f}%")
    check("quota set", d.set_quota(cg, "20%"))
    time.sleep(0.5)
    thr = cpu_pct(ypid, 2.0)
    check("throttled cpu near 20%", thr < 40 and thr < base * 0.8 or thr < 25, f"{thr:.0f}% vs base {base:.0f}%")
    check("cpu.max applied", open(d.cg_dir(cg) + "/cpu.max").read().startswith("20000"))
    check("quota reset", d.set_quota(cg, ""))
    time.sleep(0.5)
    rest = cpu_pct(ypid, 1.5)
    check("cpu restored after quota reset", quota_off(cg), f"{rest:.0f}% vs throttled {thr:.0f}% (box under load)")
    check("cgroup freeze on", d.cg_freeze(cg, True))
    time.sleep(0.4)
    fz = cpu_pct(ypid, 1.0)
    check("frozen cpu ~0", fz < 2, f"{fz:.1f}%")
    check("cgroup frozen flag", "frozen 1" in open(d.cg_dir(cg) + "/cgroup.events").read())
    check("cgroup freeze off", d.cg_freeze(cg, False))
    time.sleep(0.4)
    check("resumed after thaw", "frozen 0" in open(d.cg_dir(cg) + "/cgroup.events").read())

    g = {"key": ("cg", cg), "cg": cg, "pid": ypid, "windows": [win("spotify", ypid)["windows"][0]]}
    eco.apply(g, 1, "20%", "selftest")
    eco.apply(g, 2, "20%", "selftest")
    check("engine: applied freeze state recorded", any(e["level"] >= 2 for e in eco.applied.values()))
    check("engine: anr marker set", os.path.exists(d.ANR_MARKER))
    check("engine: state file written", any(e["class"] == "selftest" for e in d.jload(d.STATE_FILE, [])))
    eco.restore_all()
    time.sleep(0.5)
    check("engine: restore_all thawed", "frozen 0" in open(d.cg_dir(cg) + "/cgroup.events").read())
    check("engine: restore_all reset quota", quota_off(cg))
    check("engine: anr marker cleared", not os.path.exists(d.ANR_MARKER))
    check("engine: state file emptied", d.jload(d.STATE_FILE, ["x"]) == [])

    eco.apply(g, 2, "20%", "selftest")
    time.sleep(0.8)
    check("sweep setup froze", "frozen 1" in open(d.cg_dir(cg) + "/cgroup.events").read())
    eco.applied.clear()
    Eco().sweep()
    time.sleep(0.4)
    check("startup sweep thawed stale freeze", "frozen 0" in open(d.cg_dir(cg) + "/cgroup.events").read())
    check("startup sweep reset quota", quota_off(cg))
    subprocess.run(["systemctl", "--user", "stop", unit + ".scope"], capture_output=True)
    proc.terminate()

    sp = subprocess.Popen(["bash", "-c", "yes >/dev/null & yes >/dev/null & wait"])
    time.sleep(0.6)
    pmap = d.sigstop_tree(sp.pid)
    time.sleep(0.3)
    states = {p: psutil.Process(p).status() for p in pmap}
    check("sigstop tree stops all", len(pmap) == 3 and all(s == "stopped" for s in states.values()), str(states))
    d.sigcont_pids(pmap)
    time.sleep(0.3)
    check("sigcont resumes all", all(psutil.Process(p).status() != "stopped" for p in pmap))
    for p in pmap:
        try:
            os.kill(p, signal.SIGKILL)
        except OSError:
            pass
    sp.wait()

    eco.refresh_audio()
    print("live audio tokens:", sorted(eco.audio["tokens"]), "capture:", eco.audio["capture"])
    sp = subprocess.run(["pgrep", "-o", "-x", "spotify"], capture_output=True, text=True).stdout.split()
    if sp:
        spid = int(sp[0])
        sp_g = win("spotify", spid)
        sp_g["cg"] = d.cgroup_path(spid)
        print("live spotify decision (audio state as seen now):", dec(sp_g, eco.audio))
        playing_now = {"tokens": {"spotify"}, "pids": {spid}, "generic": False, "capture": False, "ts": 0}
        check("live spotify with audio flag never touched", dec(sp_g, playing_now)[0] == 0)
    else:
        print("spotify not running; live check skipped")
    print(f"\n{len(OK)} passed, {len(BAD)} failed", BAD)
    return 1 if BAD else 0
