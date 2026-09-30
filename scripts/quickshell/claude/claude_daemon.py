#!/usr/bin/env python3
import os, sys, json, time, subprocess, threading, signal

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, ".config/hypr/scripts/quickshell/claude")
AGENT = os.path.join(BASE, "agent.py")
FIFO = "/tmp/qs_claude_in"
STREAM = "/tmp/qs_claude_stream"
PID = "/tmp/qs_claude_daemon.pid"
STATUS = "/tmp/qs_claude_status"
RS = "\x1e"

_lock = threading.Lock()
state = {"mode": "ask", "model": "", "session": "", "auth": "auto", "workdir": "",
         "proc": None, "busy": False, "turn_start": 0, "silent_errs": set(), "extended_until": 0}
TURN_TIMEOUT = 150   # if no reply in this long, unstick the UI with an error

DEBUG_LOG = "/tmp/qs_claude_debug.log"
SETTINGS = os.path.expanduser("~/.config/hypr/settings.json")
CARD_ACKS = "/tmp/qs_card_acks"   # card silent-interaction resolution bus (watched by CardRenderer)


def write_card_ack(iid, status):
    if not iid:
        return
    try:
        with open(CARD_ACKS, "a") as f:
            f.write(json.dumps({"iid": iid, "status": status, "ts": int(time.time())}) + "\n")
    except OSError:
        pass


def debug_on():
    try:
        with open(SETTINGS) as f:
            return bool(json.load(f).get("claudeDebug", False))
    except Exception:
        return False


def dbg(msg):
    if not debug_on():
        return
    try:
        with open(DEBUG_LOG, "a") as f:
            f.write(f"[{time.strftime('%H:%M:%S')}] {msg}\n")
    except OSError:
        pass


def set_status(s):
    try:
        with open(STATUS, "w") as f:
            f.write(s)
    except OSError:
        pass


def append(obj):
    with _lock:
        with open(STREAM, "a") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def reader(proc):
    buf = ""
    for chunk in iter(lambda: proc.stdout.read(1), ""):
        if chunk == RS:
            line = buf.strip()
            buf = ""
            if not line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = o.get("t")
            sil = bool(o.get("silent"))
            iid = o.get("iid", "")
            if t == "session":
                state["session"] = o.get("id", state["session"])
            elif t == "ready":
                continue
            elif t == "error" and sil and iid:
                state["silent_errs"].add(iid)
            elif t in ("turn", "done"):
                state["busy"] = False
                state["extended_until"] = 0
                set_status("idle")
                if sil and iid:
                    status = "fail" if iid in state["silent_errs"] else "ok"
                    state["silent_errs"].discard(iid)
                    write_card_ack(iid, status)
            elif t == "tool" and str(o.get("name", "")).endswith("autopilot_await"):
                # this tool call legitimately blocks server-side for up to its own
                # `timeout` arg (default 300s, capped 600s) waiting on a HUMAN to
                # click a card — no further stream events arrive from the underlying
                # claude process during that wait, since it's just sitting inside one
                # tool call. The generic TURN_TIMEOUT watchdog below used to kill the
                # whole process at 150s regardless, which — if the user took longer
                # than 150s to notice and click Approve (extremely normal) — meant
                # nothing was listening anymore by the time they decided, so the
                # approval silently went nowhere. Extend the deadline to cover it.
                try:
                    to = float((o.get("input") or {}).get("timeout", 300))
                except (TypeError, ValueError):
                    to = 300
                state["extended_until"] = time.time() + min(max(to, 1), 600) + 15
            # any event = the agent is alive; reset the idle/stall clock
            state["turn_start"] = time.time()
            dbg("<- agent event: " + line[:160])
            # silent card interactions never touch the chat transcript — they resolve via the
            # ack bus above, not a visible bubble.
            if not sil:
                append(o)
        else:
            buf += chunk


def start_agent():
    stop_agent()
    cmd = ["python3", AGENT, state["mode"], state["model"],
           state["session"], state["auth"], state["workdir"]]
    dbg("spawn agent: " + " ".join(repr(c) for c in cmd))
    errto = open(DEBUG_LOG, "a") if debug_on() else subprocess.DEVNULL
    # start_new_session puts agent.py in its own process group, so stop_agent()
    # can kill the group and take its grandchild `claude` CLI process down with
    # it — without this, terminating agent.py alone orphaned the still-running
    # claude subprocess, which kept the turn going after the user pressed stop.
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=errto, text=True, bufsize=1, start_new_session=True)
    state["proc"] = proc
    threading.Thread(target=reader, args=(proc,), daemon=True).start()


def stop_agent():
    p = state.get("proc")
    if p and p.poll() is None:
        try:
            os.killpg(p.pid, signal.SIGTERM)
            p.wait(timeout=3)
        except Exception:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except Exception:
                pass
    state["proc"] = None


def forward(text, context="", silent=False, iid=""):
    p = state.get("proc")
    if not p or p.poll() is not None:
        start_agent()
        p = state["proc"]
    state["busy"] = True
    state["turn_start"] = time.time()
    set_status("busy")
    # silent card interactions get no visible user bubble — they resolve via the ack bus.
    if not silent:
        append({"t": "user", "d": text})
    # agent.py expects {"text","context"} and wraps it into claude format itself
    msg = {"text": text, "context": context}
    if silent:
        msg["silent"] = True
        msg["iid"] = iid
    dbg("-> agent stdin: " + json.dumps(msg)[:200])
    try:
        p.stdin.write(json.dumps(msg) + "\n")
        p.stdin.flush()
    except (BrokenPipeError, ValueError):
        start_agent()
        try:
            state["proc"].stdin.write(json.dumps(msg) + "\n")
            state["proc"].stdin.flush()
        except Exception:
            if silent:
                write_card_ack(iid, "fail")
            else:
                append({"t": "error", "d": "agent restart failed"})
                append({"t": "turn"})
            state["busy"] = False
            set_status("idle")


def handle(cmd):
    c = cmd.get("cmd")
    if c == "config":
        # "session" lets the UI hand back a specific past session id to
        # resume (history/resume picker) — same field agent.py already reads
        # off its own argv and passes to `claude -p --resume`, just settable
        # from outside instead of only ever being learned from the agent's
        # own "session" stream event.
        respawn = (cmd.get("mode", state["mode"]) != state["mode"] or
                   cmd.get("model", state["model"]) != state["model"] or
                   cmd.get("auth", state["auth"]) != state["auth"] or
                   cmd.get("workdir", state["workdir"]) != state["workdir"] or
                   cmd.get("session", state["session"]) != state["session"])
        for k in ("mode", "model", "auth", "workdir", "session"):
            if k in cmd:
                state[k] = cmd[k]
        if respawn and state.get("proc"):
            start_agent()
    elif c == "clear":
        state["session"] = ""
        stop_agent()
        with _lock:
            open(STREAM, "w").close()
    elif c == "stop":
        stop_agent()
        state["busy"] = False
        set_status("idle")
    elif "text" in cmd:
        forward(cmd.get("text", ""), cmd.get("context", ""),
                bool(cmd.get("silent", False)), cmd.get("iid", ""))


def watchdog():
    while True:
        time.sleep(5)
        if not (state["busy"] and state["turn_start"]):
            continue
        deadline = state["turn_start"] + TURN_TIMEOUT
        deadline = max(deadline, state.get("extended_until", 0))
        if time.time() > deadline:
            append({"t": "error", "d": "No response in time — the account may be busy "
                    "(another Claude session running) or rate-limited. Try again."})
            append({"t": "turn"})
            state["busy"] = False
            state["turn_start"] = 0
            state["extended_until"] = 0
            set_status("idle")
            stop_agent()


def main():
    # self-dedup: never run two daemons (they fight over the FIFO + transcript)
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))
    open(STREAM, "w").close()
    set_status("idle")
    if not os.path.exists(FIFO):
        os.mkfifo(FIFO)
    fd = os.open(FIFO, os.O_RDWR)
    threading.Thread(target=watchdog, daemon=True).start()
    append({"t": "ready"})
    with os.fdopen(fd, "r") as fifo:
        for raw in fifo:
            raw = raw.strip()
            if not raw:
                continue
            try:
                cmd = json.loads(raw)
            except json.JSONDecodeError:
                continue
            try:
                handle(cmd)
            except Exception as e:
                append({"t": "error", "d": f"daemon: {e}"})


if __name__ == "__main__":
    main()
