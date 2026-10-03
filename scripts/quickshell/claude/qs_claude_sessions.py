#!/usr/bin/env python3
"""Running Claude Code sessions, for the Fleet app's home screen.

Reads what Claude Code itself keeps on disk, nothing else:
  ~/.claude/sessions/<pid>.json      one per live session: cwd, status, title
  ~/.claude/projects/*/<sid>.jsonl   the transcript; only the tail is read, for
                                     the last tool's name, model and branch
  <sid>/subagents/*.meta.json        agent type and the task label the parent gave it

Never returns prompts, replies, tool arguments or file paths inside the work.

  python3 qs_claude_sessions.py      print what the phone would see
"""
import datetime
import glob
import json
import os
import re
import subprocess
import threading
import time

HOME = os.path.expanduser("~")
CLAUDE = os.path.join(HOME, ".claude")
SESSIONS = os.path.join(CLAUDE, "sessions")
PROJECTS = os.path.join(CLAUDE, "projects")
TAIL = (65536, 524288, 2097152)
HISTORY_TAIL = (131072, 1048576, 4194304, 16777216)
HISTORY_MSG_MAX = 4000
AGENT_LIVE = 150
AGENT_DONE_GRACE = 8
TOOLS = {
    "Read": "reading", "LS": "reading", "NotebookRead": "reading",
    "Grep": "searching", "Glob": "searching", "ToolSearch": "searching",
    "Edit": "editing", "MultiEdit": "editing", "NotebookEdit": "editing", "Write": "writing",
    "Bash": "running", "BashOutput": "running", "KillShell": "running", "Monitor": "watching",
    "Task": "delegating", "Agent": "delegating", "SendMessage": "delegating",
    "WebFetch": "browsing", "WebSearch": "browsing",
    "TodoWrite": "planning", "ExitPlanMode": "planning", "EnterPlanMode": "planning",
    "AskUserQuestion": "asking you", "SubagentHandback": "reporting back",
}
MODEL_RE = re.compile(r"claude-(opus|sonnet|haiku)-(\d+)(?:-(\d{1,2}))?(?:-|$)")
STATUS_ORDER = {"waiting": 0, "busy": 1, "idle": 2}

_mu = threading.Lock()
_tails = {}
_metas = {}
_paths = {}


def _read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _stat_fields(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()
    except (OSError, IndexError):
        return None


def _alive(pid, proc_start):
    f = _stat_fields(pid)
    if not f:
        return False
    if proc_start in (None, ""):
        try:
            with open(f"/proc/{pid}/comm") as c:
                return "claude" in c.read()
        except OSError:
            return False
    return len(f) > 19 and f[19] == str(proc_start)


def _ppid(pid):
    f = _stat_fields(pid)
    try:
        return int(f[1]) if f else 0
    except ValueError:
        return 0


def model_label(raw):
    m = MODEL_RE.search(raw or "")
    if not m:
        return ""
    return m.group(1).title() + " " + m.group(2) + (f".{m.group(3)}" if m.group(3) else "")


def doing_label(tool):
    if not tool:
        return ""
    if tool.startswith("mcp__"):
        return "using tools"
    return TOOLS.get(tool, "working")


def _tail(path, sidechain=False):
    try:
        st = os.stat(path)
    except OSError:
        return None
    key = (st.st_mtime_ns, st.st_size)
    with _mu:
        hit = _tails.get(path)
    if hit and hit[0] == key:
        return hit[1]
    out = {"mtime": st.st_mtime, "tool": "", "phase": "", "model": "", "branch": "", "finished": False}
    seen_main = False
    for n in TAIL:
        try:
            with open(path, "rb") as f:
                f.seek(max(0, st.st_size - n))
                chunk = f.read(n)
        except OSError:
            break
        lines = chunk.split(b"\n")
        if st.st_size > n:
            lines = lines[1:]
        for raw in reversed(lines):
            if not raw.strip():
                continue
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            if not out["branch"] and isinstance(d.get("gitBranch"), str):
                out["branch"] = d["gitBranch"][:60]
            t = d.get("type")
            if t not in ("assistant", "user") or (bool(d.get("isSidechain")) != sidechain):
                continue
            msg = d.get("message") if isinstance(d.get("message"), dict) else {}
            content = msg.get("content") if isinstance(msg.get("content"), list) else []
            if not seen_main:
                seen_main = True
                if t == "assistant":
                    use = next((b for b in reversed(content) if isinstance(b, dict) and b.get("type") == "tool_use"), None)
                    if use:
                        out["tool"] = str(use.get("name") or "")[:40]
                        out["phase"] = "tool"
                    else:
                        out["phase"] = "replied"
                        out["finished"] = msg.get("stop_reason") in ("end_turn", "stop_sequence")
                else:
                    out["phase"] = "thinking"
            if t == "assistant" and not out["model"]:
                label = model_label(str(msg.get("model") or ""))
                if label:
                    out["model"] = label
            if seen_main and out["model"] and out["branch"]:
                break
        if (seen_main and out["model"] and out["branch"]) or st.st_size <= n:
            break
    with _mu:
        _tails[path] = (key, out)
        if len(_tails) > 256:
            _tails.pop(next(iter(_tails)))
    return out


def _transcript(sid):
    with _mu:
        p = _paths.get(sid)
    if p and os.path.exists(p):
        return p
    hits = glob.glob(os.path.join(PROJECTS, "*", glob.escape(sid) + ".jsonl"))
    p = max(hits, key=os.path.getmtime) if hits else None
    with _mu:
        _paths[sid] = p
    return p


def _meta(path):
    with _mu:
        if path in _metas:
            return _metas[path]
    m = _read_json(path)
    m = m if isinstance(m, dict) else {}
    with _mu:
        _metas[path] = m
        if len(_metas) > 512:
            _metas.pop(next(iter(_metas)))
    return m


def _agents(transcript, titles, now):
    sub = os.path.join(transcript[:-len(".jsonl")], "subagents")
    try:
        names = os.listdir(sub)
    except OSError:
        return []
    out = []
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        p = os.path.join(sub, n)
        try:
            age = now - os.path.getmtime(p)
        except OSError:
            continue
        if age > AGENT_LIVE:
            continue
        t = _tail(p, sidechain=True) or {}
        done = t.get("finished") and age > AGENT_DONE_GRACE
        meta = _meta(p[:-len(".jsonl")] + ".meta.json")
        out.append({
            "type": str(meta.get("agentType") or "agent")[:40],
            "label": str(meta.get("description") or "")[:80] if titles else "",
            "background": meta.get("requestShape") == "background",
            "doing": "" if done else doing_label(t.get("tool")) or {"thinking": "thinking", "replied": "replying"}.get(t.get("phase"), ""),
            "done": bool(done),
            "age": int(age),
        })
    out.sort(key=lambda a: (a["done"], a["age"]))
    return out[:12]


def _windows():
    try:
        r = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=2)
        clients = json.loads(r.stdout or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}
    return {c["pid"]: c for c in clients if isinstance(c, dict) and isinstance(c.get("pid"), int)}


def _window_for(pid, wins):
    p = pid
    for _ in range(14):
        if p <= 1:
            return None
        if p in wins:
            return p, wins[p]
        p = _ppid(p)
    return None


def _home(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + "/") else path


def _headless(known, now):
    out = []
    try:
        pids = [int(p) for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return out
    for pid in pids:
        if pid in known:
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() != "claude":
                    continue
            cwd = os.readlink(f"/proc/{pid}/cwd")
            started = os.stat(f"/proc/{pid}").st_mtime
        except OSError:
            continue
        if _ppid(pid) in known:
            continue
        out.append({"pid": pid, "project": os.path.basename(cwd) or "~", "path": _home(cwd), "age": int(now - started)})
    return out[:8]


def sessions(titles=True):
    now = time.time()
    wins = _windows()
    by_sid = {}
    for path in glob.glob(os.path.join(SESSIONS, "*.json")):
        s = _read_json(path)
        if not isinstance(s, dict) or not isinstance(s.get("pid"), int):
            continue
        pid = s["pid"]
        if not _alive(pid, s.get("procStart")):
            continue
        sid = str(s.get("sessionId") or "")
        prev = by_sid.get(sid)
        if prev and (prev[1].get("updatedAt") or 0) >= (s.get("updatedAt") or 0):
            continue
        by_sid[sid or str(pid)] = (pid, s)

    out = []
    for sid, (pid, s) in by_sid.items():
        cwd = str(s.get("cwd") or "")
        status = str(s.get("status") or "idle")
        status_at = (s.get("statusUpdatedAt") or s.get("updatedAt") or 0) / 1000
        tpath = _transcript(sid) if sid else None
        tail = (_tail(tpath) if tpath else None) or {}
        win = _window_for(pid, wins)
        last = max(tail.get("mtime") or 0, status_at)
        doing = ""
        if status == "busy":
            doing = doing_label(tail.get("tool")) if tail.get("phase") == "tool" else "replying" if tail.get("phase") == "replied" else "thinking"
        agents = _agents(tpath, titles, now) if tpath else []
        if status == "busy" and now - (tail.get("mtime") or 0) > 20 and any(not a["done"] for a in agents):
            doing = "waiting on agents"
        out.append({
            "pid": pid,
            "id": sid[:8],
            "name": str(s.get("name") or "")[:80] if titles else "",
            "project": os.path.basename(cwd.rstrip("/")) or "~",
            "path": _home(cwd),
            "branch": tail.get("branch", ""),
            "status": status if status in STATUS_ORDER else "idle",
            "waiting_for": str(s.get("waitingFor") or "")[:40] if status == "waiting" else "",
            "status_age": int(max(0, now - status_at)) if status_at else None,
            "active_age": int(max(0, now - last)) if last else None,
            "doing": doing,
            "tool": tail.get("tool", "") if status == "busy" and tail.get("phase") == "tool" else "",
            "model": tail.get("model", ""),
            "kind": str(s.get("kind") or "")[:20],
            "entry": str(s.get("entrypoint") or "")[:20],
            "version": str(s.get("version") or "")[:20],
            "uptime": int(max(0, now - (s.get("startedAt") or 0) / 1000)) if s.get("startedAt") else None,
            "agents": agents,
            "window": win is not None,
            "workspace": str(((win[1].get("workspace") or {}).get("name")) or "") if win else "",
        })
    out.sort(key=lambda e: (STATUS_ORDER.get(e["status"], 3), e["active_age"] if e["active_age"] is not None else 1e9))
    return {"ts": int(now), "sessions": out, "headless": _headless({e["pid"] for e in out}, now)}


def focus(pid):
    wins = _windows()
    for path in glob.glob(os.path.join(SESSIONS, "*.json")):
        s = _read_json(path)
        if isinstance(s, dict) and s.get("pid") == pid and _alive(pid, s.get("procStart")):
            win = _window_for(pid, wins)
            if not win:
                return False, "that session has no window to focus"
            r = subprocess.run(["hyprctl", "dispatch", "focuswindow", f"pid:{win[0]}"], capture_output=True, text=True, timeout=3)
            return r.returncode == 0 and "ok" in (r.stdout or "").lower(), "hyprctl refused"
    return False, "that session isn't running anymore"


def _session_for_pid(pid):
    for path in glob.glob(os.path.join(SESSIONS, "*.json")):
        s = _read_json(path)
        if isinstance(s, dict) and s.get("pid") == pid and _alive(pid, s.get("procStart")):
            return s
    return None


def _iso_to_epoch(ts):
    try:
        return int(datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S.%fZ")
                   .replace(tzinfo=datetime.timezone.utc).timestamp())
    except (TypeError, ValueError):
        return None


def _turn_text(content):
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(p for p in parts if p).strip()
    return ""


def history(sid, limit=40):
    """The user-visible turns of a transcript: no tool calls, no thinking,
    no tool results — just what the user typed and what Claude said back."""
    path = _transcript(sid)
    if not path:
        return []
    limit = max(1, min(int(limit or 40), 200))
    turns = []
    for n in HISTORY_TAIL:
        try:
            st = os.stat(path)
        except OSError:
            return []
        try:
            with open(path, "rb") as f:
                f.seek(max(0, st.st_size - n))
                chunk = f.read(n)
        except OSError:
            return []
        lines = chunk.split(b"\n")
        if st.st_size > n:
            lines = lines[1:]
        turns = []
        for raw in lines:
            if not raw.strip():
                continue
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(d, dict) or d.get("type") not in ("user", "assistant") or d.get("isSidechain"):
                continue
            msg = d.get("message") if isinstance(d.get("message"), dict) else {}
            text = _turn_text(msg.get("content"))
            if not text:
                continue
            turns.append({"role": d["type"], "text": text[:HISTORY_MSG_MAX], "ts": _iso_to_epoch(d.get("timestamp"))})
        if len(turns) >= limit or st.st_size <= n:
            break
    return turns[-limit:]


def history_for_pid(pid, limit=40):
    s = _session_for_pid(pid)
    if not s:
        return None, "that session isn't running anymore"
    sid = str(s.get("sessionId") or "")
    if not sid:
        return [], None
    return history(sid, limit), None


DIFF_STAT_MAX = 4000
DIFF_BODY_MAX = 20000
DIFF_LINES_MAX = 400


def diff(pid):
    s = _session_for_pid(pid)
    if not s:
        return {"ok": False, "error": "that session isn't running anymore"}
    cwd = str(s.get("cwd") or "")
    if not cwd or not os.path.isdir(cwd):
        return {"ok": False, "error": "that session has no working directory to check"}
    top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=3)
    if top.returncode != 0:
        return {"ok": False, "error": "not a git repo"}
    stat = subprocess.run(["git", "-C", cwd, "diff", "--stat"], capture_output=True, text=True, timeout=5).stdout
    status = subprocess.run(["git", "-C", cwd, "status", "--porcelain"], capture_output=True, text=True, timeout=5).stdout
    if not stat.strip() and not status.strip():
        return {"ok": True, "clean": True}
    full = subprocess.run(["git", "-C", cwd, "diff"], capture_output=True, text=True, timeout=8).stdout
    capped = "\n".join(full.splitlines()[:DIFF_LINES_MAX])
    return {"ok": True, "clean": False, "stat": stat.strip()[:DIFF_STAT_MAX], "diff": capped[:DIFF_BODY_MAX]}


if __name__ == "__main__":
    print(json.dumps(sessions(), indent=2))
