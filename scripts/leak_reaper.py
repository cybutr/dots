#!/usr/bin/env python3
import os, sys, json, time, signal, fcntl

INTERVAL = 10
MIN_AGE = 15
LOG = "/tmp/qs_leak_reaper.log"
LOCK = "/tmp/qs_leak_reaper.lock"
MAILBOX = "/tmp/qs_claude_mailbox.json"
MAILBOX_REAP_THRESHOLD = 5
PATTERNS = (
    "sys_toggles.sh; sleep 0.2",
    "playerctl --player=spotify --follow",
    "playerctl -p spotify --follow",
    "inotifywait -m -q -e close_write --format %w /tmp/qs_",
    "inotifywait -qq -e close_write,modify /tmp/qs_",
    "inotifywait -qq -e close_write,modify /tmp/music",
    "inotifywait -qq -e modify,close_write /tmp/qs_",
    "dbus-monitor --session",
    "quickshell/workspaces.sh",
    "quickshell/music/music_watch.sh",
    "sys_toggles_daemon.sh",
    "['playerctl','position']",
    "playerctl metadata --format",
    "playerctl -p spotify",
    "playerctl --player=spotify",
    "quickshell/music/audio_spectrum.py",
)
CLK = os.sysconf("SC_CLK_TCK")


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + msg + "\n")
        if os.path.getsize(LOG) > 200000:
            os.replace(LOG, LOG + ".old")
    except OSError:
        pass


def mailbox_post(to, msg, frm="leak_reaper"):
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


def boot_time():
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("btime"):
                return int(line.split()[1])
    return 0


BTIME = boot_time()


def scan():
    me = os.getpid()
    uid = os.getuid()
    now = time.time()
    out = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        if pid == me:
            continue
        try:
            st = os.stat(f"/proc/{pid}")
            if st.st_uid != uid:
                continue
            with open(f"/proc/{pid}/stat") as f:
                raw = f.read()
            rest = raw[raw.rindex(")") + 2:].split()
            ppid = int(rest[1])
            if ppid != 1:
                continue
            start = BTIME + int(rest[19]) / CLK
            if now - start < MIN_AGE:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
        except (OSError, ValueError, IndexError):
            continue
        if not cmd:
            continue
        if "eco_daemon" in cmd or "leak_reaper" in cmd:
            continue
        if (
            cmd.startswith("inotifywait")
            or any(p in cmd for p in PATTERNS)
            or (cmd.startswith(("/usr/bin/bash -c", "bash -c")) and "inotifywait" in cmd)
        ):
            out.append((pid, cmd))
    return out


def reap():
    victims = scan()
    if not victims:
        return
    for pid, _ in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    time.sleep(1.5)
    for pid, _ in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    log(f"reaped {len(victims)} orphan(s), e.g. {victims[0][1][:80]}")
    if len(victims) >= MAILBOX_REAP_THRESHOLD:
        mailbox_post("user", f"Reaped {len(victims)} leaked orphan processes", frm="leak_reaper")


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    if "--once" in sys.argv:
        reap()
        return
    while True:
        try:
            reap()
        except Exception as e:
            log(f"error {e!r}")
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
