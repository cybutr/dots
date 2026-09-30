#!/usr/bin/env python3
import sys, os, json, subprocess, glob, time, base64, shutil, socket, struct, urllib.request, urllib.parse
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cap_gate

try:
    from claude_say import say as _haiku_say
except Exception:
    def _haiku_say(*a, **k): return ""

HOME = os.path.expanduser("~")
QS = os.path.join(HOME, ".config/hypr/scripts/quickshell")
CTX = "/tmp/qs_context.json"
PROTO = "2024-11-05"

ALLOWED_DIRS = [os.path.join(HOME, "Documents"), os.path.join(HOME, "Downloads"),
                os.path.join(HOME, "Images"), os.path.join(HOME, ".config/hypr")]


def _in_allowed(path):
    rp = os.path.realpath(path)
    return any(rp == d or rp.startswith(d + os.sep) for d in (os.path.realpath(p) for p in ALLOWED_DIRS))


ACTUATORS = {"complete_task", "add_task", "open_widget", "hypr", "notify", "set_volume",
             "toggle_mute", "mic_mute", "power_profile", "night_light", "media_control",
             "set_wallpaper", "remember", "suggest", "wifi_control", "bluetooth_control",
             "browser_open", "browser_switch_tab", "browser_close_tab", "browser_eval",
             "screenshot", "window_control", "app_open", "input_control", "file_ops",
             "clipboard_control", "process_control", "mailbox_post", "mail_open",
             "set_brightness", "audio_device", "systemd_service", "reminder", "display_control",
             "vpn_control"}

ACTION_LOG = "/tmp/qs_agent_actions.log"


def _log_action(name, args, result):
    try:
        ok = result.get("ok") if isinstance(result, dict) else None
        entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "tool": name, "args": args, "ok": ok}
        if isinstance(result, dict) and not ok and "error" in result:
            entry["error"] = result["error"]
        with open(ACTION_LOG, "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def load_ctx():
    try:
        with open(CTX) as f:
            ctx = json.load(f)
        if time.time() - ctx.get("ts", 0) > 90:
            subprocess.run(["python3", os.path.join(QS, "claude/context.py")], timeout=5)
            with open(CTX) as f:
                ctx = json.load(f)
        return ctx
    except Exception:
        subprocess.run(["python3", os.path.join(QS, "claude/context.py")], timeout=5)
        try:
            with open(CTX) as f:
                return json.load(f)
        except Exception:
            return {}


TIMER_FILE = "/tmp/qs_worktimer.json"


def _read_timer():
    try:
        with open(TIMER_FILE) as f:
            d = json.load(f)
        return d if d and "deadline" in d else None
    except Exception:
        return None


def _timer_status(d):
    remaining = int(d["deadline"] - time.time())
    return {"active": remaining > 0, "remaining_sec": max(0, remaining),
            "remaining_human": f"{remaining // 60}m {remaining % 60}s" if remaining > 0 else "expired",
            "task": d.get("task", ""), "deadline": d["deadline"]}


def t_start_work_timer(args):
    try:
        minutes = float(args.get("minutes", 0))
    except (TypeError, ValueError):
        return {"ok": False, "error": "minutes must be a number"}
    if minutes <= 0:
        return {"ok": False, "error": "minutes must be > 0"}
    task = args.get("task", "").strip()
    if not task:
        return {"ok": False, "error": "task required — describe what you must keep doing"}
    now = time.time()
    # Scope the timer to the session that set it: the widget agent runs with
    # QS_AGENT_MODE in env, the CLI does not. The Stop hook only blocks a session
    # whose owner matches — so a widget autopilot timer never traps the CLI.
    owner = "widget" if os.environ.get("QS_AGENT_MODE") else "cli"
    state = {"deadline": now + minutes * 60, "task": task, "set_at": now,
             "minutes": minutes, "owner": owner}
    with open(TIMER_FILE, "w") as f:
        json.dump(state, f)
    return {"ok": True, **_timer_status(state),
            "note": "Stop hook will block any attempt to stop before the deadline. Keep working."}


def t_check_work_timer(_):
    d = _read_timer()
    if not d:
        return {"ok": True, "active": False, "note": "no timer set"}
    return {"ok": True, **_timer_status(d)}


def t_cancel_work_timer(_):
    d = _read_timer()
    if not d or not _timer_status(d)["active"]:
        return {"ok": True, "active": False, "note": "no active timer to cancel"}
    return {"ok": False, "refused": True,
            "error": "Work timer is user-locked. The agent cannot cancel it. Keep working until it "
                     "expires, or the user clicks the timer pill to release it early."}


AUTOPILOT_DECISIONS = "/tmp/qs_autopilot/decisions"


def t_autopilot_await(args):
    rid = str(args.get("id", "")).strip()
    if not rid:
        return {"ok": False, "error": "id required (the request_id you put on the approval card buttons)"}
    safe = "".join(c for c in rid if c.isalnum() or c in "_-")
    path = os.path.join(AUTOPILOT_DECISIONS, f"{safe}.json")
    timeout = float(args.get("timeout", 300))
    deadline = time.time() + min(max(timeout, 1), 600)
    while time.time() < deadline:
        try:
            with open(path) as f:
                d = json.load(f)
            os.remove(path)
            # the "retry the tool call" instruction otherwise only exists in the
            # original blocked-tool error message, several turns back by the time
            # a decision lands — restate it here so acting on it doesn't depend on
            # the model recalling something from far back in context
            note = ("User approved — immediately retry the exact tool call that was "
                    "blocked, now. Do not just report the approval." if d.get("choice") in
                    ("approve", "send", "trust_send")
                    else "User denied — do not run the blocked action. Tell them briefly.")
            return {"ok": True, "decided": True, "note": note, **d}
        except FileNotFoundError:
            time.sleep(0.5)
        except Exception:
            time.sleep(0.5)
    return {"ok": True, "decided": False, "choice": "timeout",
            "note": "No decision within timeout — treat as skip (do not send)."}


def t_system(_):
    c = load_ctx()
    return {"system": c.get("system", {}), "mic": c.get("mic", {}),
            "proc": c.get("proc", {}), "ts": c.get("ts")}


def t_events(_):
    return load_ctx().get("schedule", {})


def t_tasks(_):
    sch = load_ctx().get("schedule", {})
    return {"tasks": sch.get("tasks", [])}


def t_focus(args):
    cmd = ["python3", os.path.join(QS, "focustime/get_stats.py")]
    d = args.get("date", "").strip()
    if d:
        cmd.append(d)
    if args.get("app"):
        cmd += ["--app", args["app"]]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:2000]}


def t_logs(args):
    n = int(args.get("lines", 60))
    logs = sorted(glob.glob("/run/user/1000/quickshell/by-id/*/log.qslog"),
                  key=os.path.getmtime, reverse=True)
    if not logs:
        return {"error": "no logs found"}
    with open(logs[0]) as f:
        tail = f.readlines()[-n:]
    return {"file": logs[0], "tail": "".join(tail)[-4000:]}


SCHED = os.path.join(QS, "calendar/schedule")
MANAGER = os.path.join(HOME, ".config/hypr/scripts/qs_manager.sh")
MEM = os.path.join(HOME, ".local/share/qs_claude_memory.md")
WIDGETS = ["battery", "volume", "notifications", "calendar", "music", "network",
           "monitors", "focustime", "guide", "wallpaper", "workspaces", "power",
           "people", "memory", "netstatus"]


def _sh(cmd, timeout=15, env=None):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
    return {"ok": r.returncode == 0, "out": (r.stdout or r.stderr).strip()[:500]}


YDOTOOL_ENV = {**os.environ, "YDOTOOL_SOCKET": f"/run/user/{os.getuid()}/.ydotool_socket"}


def t_complete_task(args):
    tid, tlid = args.get("task_id", ""), args.get("tasklist_id", "")
    if not tid or not tlid:
        return {"ok": False, "error": "task_id and tasklist_id required (get them from list_tasks)"}
    res = _sh(["bash", os.path.join(SCHED, "toggle_task.sh"), tid, tlid])
    subprocess.run(["python3", os.path.join(QS, "claude/context.py")], timeout=10)
    return res


def _suggest_subtasks(title):
    """#13 task-breakdown — for any task title substantial enough to plausibly
    hide real structure, ask Haiku for a first action + up to 3 subtasks.
    Returned as data on the tool result; the agent decides whether/how to
    offer them (show_card with accept/skip), this never adds anything itself."""
    out = _haiku_say(
        f"Task just added: {title!r}. If this task plausibly has a natural first "
        f"action and 1-3 concrete subtasks, reply with ONLY compact JSON: "
        f'{{"first_action":"...", "subtasks":["...", "..."]}} (subtasks array can be '
        f"empty). If the task is already atomic/trivial and breaking it down would be "
        f"silly, reply with exactly 'SKIP'.",
        system="You break tasks into actionable steps. Terse, exact JSON or SKIP, no "
               "markdown fence, no extra commentary.", timeout=15, max_tokens=150).strip()
    if not out or out.upper() == "SKIP":
        return None
    if out.startswith("```"):
        out = out.strip("`")
        out = out[out.find("{"):]
    try:
        d = json.loads(out)
    except Exception:
        return None
    subtasks = [s for s in (d.get("subtasks") or []) if isinstance(s, str) and s.strip()][:3]
    first_action = (d.get("first_action") or "").strip()
    if not subtasks and not first_action:
        return None
    return {"first_action": first_action, "subtasks": subtasks}


def t_add_task(args):
    title = args.get("title", "").strip()
    if not title:
        return {"ok": False, "error": "title required"}
    res = _sh(["bash", os.path.join(SCHED, "add_task.sh"), title])
    subprocess.run(["python3", os.path.join(QS, "claude/context.py")], timeout=10)
    if res.get("ok") and len(title.split()) >= 4:
        breakdown = _suggest_subtasks(title)
        if breakdown:
            res["subtask_suggestion"] = breakdown
    return res


def t_open_widget(args):
    name = args.get("name", "").strip()
    if name not in WIDGETS:
        return {"ok": False, "error": f"unknown widget; valid: {', '.join(WIDGETS)}"}
    action = "toggle" if args.get("toggle") else "open"
    return _sh(["bash", MANAGER, action, name])


def t_hypr(args):
    dispatch = args.get("dispatch", "").strip()
    if not dispatch:
        return {"ok": False, "error": "dispatch string required, e.g. 'workspace 3'"}
    return _sh(["hyprctl", "dispatch", *dispatch.split()])


def t_notify(args):
    title = args.get("title", "Claude")
    body = args.get("body", "")
    urg = args.get("urgency", "normal")
    return _sh(["notify-send", "-a", "Claude", "-u", urg, "-i", "dialog-information", title, body])


def t_suggest(args):
    msg = args.get("msg", "").strip()
    if not msg:
        return {"ok": False, "error": "msg required"}
    payload = json.dumps({
        "key": args.get("key", "claude"),
        "msg": msg,
        "urgency": args.get("urgency", "normal"),
        "ts": int(time.time()),
        "action_label": args.get("action_label", ""),
        "action_cmd": args.get("action_cmd", ""),
    })
    try:
        with open("/tmp/qs_resident_suggestion", "w") as f:
            f.write(payload)
        return {"ok": True}
    except OSError as e:
        return {"ok": False, "error": str(e)}


def t_workspaces(_):
    try:
        with open("/tmp/qs_workspaces.json") as f:
            return json.load(f)
    except Exception as e:
        return {"error": str(e)}


def t_music(_):
    script = os.path.join(QS, "music/music_info.sh")
    out = subprocess.run(["bash", script], capture_output=True, text=True, timeout=5).stdout.strip()
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:500]}


def _volume_osd_sync():
    muted = subprocess.run(["pamixer", "--get-mute"], capture_output=True, text=True, timeout=5).stdout.strip()
    if muted == "true":
        Path("/tmp/qs_volume_osd").write_text("muted")
    else:
        vol = subprocess.run(["pamixer", "--get-volume"], capture_output=True, text=True, timeout=5).stdout.strip()
        Path("/tmp/qs_volume_osd").write_text(vol or "0")


def t_set_volume(args):
    pct = int(args.get("percent", 50))
    pct = max(0, min(150, pct))
    result = _sh(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{pct}%"])
    _volume_osd_sync()
    return result


def t_toggle_mute(_):
    result = _sh(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    _volume_osd_sync()
    return result


def t_mic_mute(args):
    state = "1" if args.get("muted", True) else "0"
    result = _sh(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", state])
    Path("/tmp/qs_mic_osd").write_text("muted" if state == "1" else "live")
    return result


MEM_CATEGORIES = ("preference", "fact", "project", "person", "general")


def _parse_mem_line(line):
    # "- [category] note  <!--ts-->"  (older plain "- note" still parses as general)
    s = line.strip()
    if not s.startswith("-"):
        return None
    s = s[1:].strip()
    ts = ""
    if "<!--" in s and s.endswith("-->"):
        i = s.rfind("<!--")
        ts = s[i + 4:-3].strip()
        s = s[:i].strip()
    cat = "general"
    if s.startswith("[") and "]" in s:
        j = s.index("]")
        c = s[1:j].strip().lower()
        if c in MEM_CATEGORIES:
            cat = c
            s = s[j + 1:].strip()
    return {"category": cat, "note": s, "ts": ts}


def _load_mem():
    try:
        with open(MEM) as f:
            out = []
            for ln in f:
                p = _parse_mem_line(ln)
                if p and p["note"]:
                    out.append(p)
            return out
    except OSError:
        return []


def _tokens(s):
    return set(w for w in "".join(c.lower() if c.isalnum() else " " for c in s).split() if len(w) > 2)


def t_remember(args):
    note = args.get("note", "").strip().replace("\n", " ")
    if not note:
        return {"ok": False, "error": "note required"}
    cat = (args.get("category") or "general").strip().lower()
    if cat not in MEM_CATEGORIES:
        cat = "general"
    existing = _load_mem()
    # dedup: skip if an existing note is (near-)identical or one contains the other
    nlow = note.lower()
    nt = _tokens(note)
    for e in existing:
        elow = e["note"].lower()
        if elow == nlow or nlow in elow or elow in nlow:
            return {"ok": True, "deduped": True, "note": "already remembered something equivalent"}
        et = _tokens(e["note"])
        if nt and et and len(nt & et) / len(nt | et) > 0.8:
            return {"ok": True, "deduped": True, "note": "already remembered something very similar"}
    try:
        os.makedirs(os.path.dirname(MEM), exist_ok=True)
        with open(MEM, "a") as f:
            f.write(f"- [{cat}] {note}  <!--{time.strftime('%Y-%m-%d')}-->\n")
        return {"ok": True, "category": cat}
    except OSError as e:
        return {"ok": False, "error": str(e)}


def t_recall(args):
    cat = (args.get("category") or "").strip().lower()
    mem = _load_mem()
    if cat in MEM_CATEGORIES:
        mem = [m for m in mem if m["category"] == cat]
    if not mem:
        return {"memory": "", "count": 0}
    lines = [f"- [{m['category']}] {m['note']}" + (f" ({m['ts']})" if m["ts"] else "") for m in mem]
    return {"memory": "\n".join(lines)[-4000:], "count": len(mem)}


def t_memory_search(args):
    q = (args.get("query") or "").strip()
    if not q:
        return {"ok": False, "error": "query required"}
    qt = _tokens(q)
    qlow = q.lower()
    scored = []
    for m in _load_mem():
        et = _tokens(m["note"])
        overlap = len(qt & et)
        substr = 2 if qlow in m["note"].lower() else 0
        score = overlap + substr
        if score > 0:
            scored.append((score, m))
    scored.sort(key=lambda x: -x[0])
    top = [{"category": m["category"], "note": m["note"], "ts": m["ts"]} for _, m in scored[:12]]
    return {"ok": True, "query": q, "matches": top, "count": len(top)}


def t_power_profile(args):
    p = args.get("profile", "balanced")
    if p not in ("performance", "balanced", "power-saver"):
        return {"ok": False, "error": "profile must be performance|balanced|power-saver"}
    return _sh(["powerprofilesctl", "set", p])


WORKSPACE_SCOPES = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/documents",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/tasks",
]


def _workspace_reauth_url():
    try:
        with open(os.path.join(HOME, ".config/workspace-mcp/oauth_client.json")) as f:
            cid = json.load(f).get("client_id", "")
    except Exception:
        cid = ""
    if not cid:
        return ""
    params = urllib.parse.urlencode({
        "client_id": cid,
        "redirect_uri": "http://localhost:8000/oauth2callback",
        "response_type": "code",
        "scope": " ".join(WORKSPACE_SCOPES),
        "access_type": "offline",
        "prompt": "consent",
    })
    return "https://accounts.google.com/o/oauth2/v2/auth?" + params


def t_workspace_status(_):
    cdir = os.path.join(HOME, ".google_workspace_mcp", "credentials")
    authed = False
    try:
        # a per-account "<email>.json" token file means at least one account is authed
        authed = any(f.endswith(".json") and f != "oauth_states.json"
                     for f in os.listdir(cdir))
    except OSError:
        authed = False
    return {"ok": True, "authed": authed, "reauth_url": _workspace_reauth_url(),
            "note": ("Google Workspace is authorized." if authed else
                     "Not authorized yet — show the user an unpinnable reauth card with an "
                     "'Authorize Google' button (action fn open_url to reauth_url).")}


def _brightness_osd_sync():
    cur = subprocess.run(["brightnessctl", "-m"], capture_output=True, text=True, timeout=5).stdout.strip()
    pct = cur.split(",")[3].rstrip("%") if cur.count(",") >= 3 else "0"
    Path("/tmp/qs_brightness_osd").write_text(pct)


def t_set_brightness(args):
    val = str(args.get("value", "")).strip()
    if not val:
        cur = subprocess.run(["brightnessctl", "-m"], capture_output=True, text=True, timeout=5).stdout.strip()
        return {"ok": True, "current": cur.split(",")[3] if cur.count(",") >= 3 else cur}
    # accept "50%", "+10%", "10%-", "50"
    if not all(c.isdigit() or c in "+-%" for c in val):
        return {"ok": False, "error": "value like '50%', '+10%', '10%-'"}
    if val.endswith("%-"):
        result = _sh(["brightnessctl", "set", val[:-2] + "%-"])
    else:
        result = _sh(["brightnessctl", "set", val if val.endswith("%") or val[0] in "+-" else val + "%"])
    _brightness_osd_sync()
    return result


def t_audio_device(args):
    action = args.get("action", "list")
    kind = args.get("kind", "sink")  # sink (output) | source (input)
    if action == "list":
        r = subprocess.run(["wpctl", "status"], capture_output=True, text=True, timeout=5).stdout
        return {"ok": True, "status": r[:2000]}
    if action in ("set", "set-default"):
        node = str(args.get("id", "")).strip()
        if not node.isdigit():
            return {"ok": False, "error": "id (numeric wpctl node id from action=list) required"}
        return _sh(["wpctl", "set-default", node])
    return {"ok": False, "error": "action: list | set (with id)"}


def t_systemd_service(args):
    action = args.get("action", "status")
    svc = str(args.get("service", "")).strip()
    scope = "--user" if args.get("scope", "user") == "user" else "--system"
    if action not in ("status", "start", "stop", "restart", "is-active", "list"):
        return {"ok": False, "error": "action: status|start|stop|restart|is-active|list"}
    if action == "list":
        r = subprocess.run(["systemctl", scope, "list-units", "--type=service", "--state=running", "--no-pager", "--plain"],
                           capture_output=True, text=True, timeout=8).stdout
        return {"ok": True, "running": r[:2000]}
    if not svc:
        return {"ok": False, "error": "service name required"}
    if not all(c.isalnum() or c in "-_.@:" for c in svc):
        return {"ok": False, "error": "invalid service name"}
    if action == "status":
        r = subprocess.run(["systemctl", scope, "--no-pager", "status", svc],
                           capture_output=True, text=True, timeout=8)
        return {"ok": True, "out": (r.stdout or r.stderr)[:1500]}
    return _sh(["systemctl", scope, action, svc])


def t_reminder(args):
    text = str(args.get("text", "")).strip()
    if not text:
        return {"ok": False, "error": "text required"}
    try:
        mins = float(args.get("minutes", 0))
    except (TypeError, ValueError):
        return {"ok": False, "error": "minutes must be a number"}
    if mins <= 0:
        return {"ok": False, "error": "minutes must be > 0"}
    secs = int(mins * 60)
    safe = text.replace("\n", " ")[:200]
    return _sh(["systemd-run", "--user", f"--on-active={secs}", "--unit",
                f"claude-reminder-{int(time.time())}", "--description", "Claude reminder",
                "notify-send", "-a", "Claude", "-u", "normal", "-i", "alarm-symbolic",
                "⏰ Reminder", safe])


def t_display_control(args):
    action = args.get("action", "list")
    if action == "list":
        r = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5).stdout
        try:
            mons = json.loads(r)
            return {"ok": True, "monitors": [{"name": m["name"], "res": f"{m['width']}x{m['height']}@{round(m.get('refreshRate',0))}",
                                              "scale": m.get("scale"), "dpms": m.get("dpmsStatus")} for m in mons]}
        except Exception:
            return {"ok": True, "raw": r[:1000]}
    if action in ("on", "off"):
        mon = str(args.get("monitor", "")).strip() or ""
        target = mon if mon else ""
        return _sh(["hyprctl", "dispatch", "dpms", action] + ([target] if target else []))
    return {"ok": False, "error": "action: list | on | off (optional monitor=<name>)"}


NET = os.path.join(QS, "network")


def _wifi_iface():
    r = subprocess.run(["nmcli", "-t", "-f", "DEVICE,TYPE", "d"], capture_output=True, text=True, timeout=5)
    for line in r.stdout.splitlines():
        if line.endswith(":wifi"):
            return line.split(":")[0]
    return None


def t_wifi_control(args):
    action = args.get("action", "status")
    if action in ("status", "list"):
        r = subprocess.run(["bash", os.path.join(NET, "wifi_panel_logic.sh")],
                            capture_output=True, text=True, timeout=10)
        try:
            return {"ok": True, **json.loads(r.stdout)}
        except Exception:
            return {"ok": False, "error": (r.stdout or r.stderr or "wifi script failed")[:300]}
    if action == "toggle":
        return _sh(["nmcli", "radio", "wifi", "toggle"])
    if action in ("on", "off"):
        return _sh(["nmcli", "radio", "wifi", action])
    if action == "connect":
        ssid = args.get("ssid", "").strip()
        if not ssid:
            return {"ok": False, "error": "ssid required"}
        cmd = ["nmcli", "device", "wifi", "connect", ssid]
        pw = args.get("password", "")
        if pw:
            cmd += ["password", pw]
        return _sh(cmd, timeout=20)
    if action == "disconnect":
        iface = _wifi_iface()
        if not iface:
            return {"ok": False, "error": "no wifi device found"}
        return _sh(["nmcli", "device", "disconnect", iface])
    return {"ok": False, "error": "action must be status|list|toggle|on|off|connect|disconnect"}


def t_bluetooth_control(args):
    action = args.get("action", "status")
    script = os.path.join(NET, "bluetooth_panel_logic.sh")
    if action == "status":
        r = subprocess.run(["bash", script, "--status"], capture_output=True, text=True, timeout=10)
        try:
            return {"ok": True, **json.loads(r.stdout)}
        except Exception:
            return {"ok": False, "error": (r.stdout or r.stderr or "bluetooth script failed")[:300]}
    if action == "toggle":
        return _sh(["bash", script, "--toggle"], timeout=10)
    if action in ("on", "off"):
        return _sh(["bluetoothctl", "power", action])
    if action == "connect":
        mac = args.get("mac", "").strip()
        if not mac:
            return {"ok": False, "error": "mac required (get it from a status call)"}
        return _sh(["bash", script, "--connect", mac], timeout=20)
    if action == "disconnect":
        mac = args.get("mac", "").strip()
        if not mac:
            return {"ok": False, "error": "mac required (get it from a status call)"}
        return _sh(["bash", script, "--disconnect", mac], timeout=10)
    return {"ok": False, "error": "action must be status|toggle|on|off|connect|disconnect"}


# ---- ProtonVPN + per-wifi autoconnect learning -----------------------------
VPN_PROFILES = os.path.expanduser("~/.config/hypr/vpn_profiles.json")


def _current_ssid():
    r = _sh(["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi"])
    for line in (r.get("out") or "").splitlines():
        if line.startswith("yes:"):
            return line.split(":", 1)[1].strip()
    return ""


def _vpn_load():
    try:
        with open(VPN_PROFILES) as f:
            return json.load(f)
    except Exception:
        return {"auto_ssids": {}, "counts": {}}


def _vpn_save(d):
    try:
        os.makedirs(os.path.dirname(VPN_PROFILES), exist_ok=True)
        with open(VPN_PROFILES, "w") as f:
            json.dump(d, f, indent=2)
    except Exception:
        pass


def _vpn_status():
    r = _sh(["protonvpn", "status"], timeout=12)
    out = r.get("out") or ""
    connected = "Connected" in out and "Disconnected" not in out.split("\n")[0]
    server = ""
    for line in out.splitlines():
        if line.strip().lower().startswith("server:"):
            server = line.split(":", 1)[1].strip()
    return connected, server, out


def t_vpn_control(args):
    """ProtonVPN control + per-wifi autoconnect learning.
    actions: status | connect[server?] | disconnect | signin |
             autolearn (record this ssid as a place vpn should auto-connect) |
             autoforget | autolist | autocheck (connect if current ssid is learned)"""
    action = args.get("action", "status")
    prof = _vpn_load()

    if action == "status":
        connected, server, out = _vpn_status()
        ssid = _current_ssid()
        return {"ok": True, "connected": connected, "server": server,
                "ssid": ssid, "auto_here": ssid in prof.get("auto_ssids", {}),
                "raw": out[:400]}

    if action == "connect":
        server = args.get("server", "").strip()
        cmd = ["protonvpn", "connect"]
        if server:
            cmd += ["--server", server] if server.upper() == server and "#" in server else [server]
        return _sh(cmd, timeout=45)

    if action == "disconnect":
        return _sh(["protonvpn", "disconnect"], timeout=20)

    if action == "signin":
        return {"ok": False, "error": "run `protonvpn signin` in a terminal — it's interactive, the agent can't enter credentials."}

    # --- autoconnect learning ---
    if action == "autolearn":
        ssid = args.get("ssid", "").strip() or _current_ssid()
        if not ssid:
            return {"ok": False, "error": "no wifi ssid to learn"}
        prof.setdefault("auto_ssids", {})[ssid] = {"ts": int(time.time())}
        _vpn_save(prof)
        return {"ok": True, "learned": ssid, "note": f"VPN will auto-connect on '{ssid}'."}

    if action == "autoforget":
        ssid = args.get("ssid", "").strip() or _current_ssid()
        prof.get("auto_ssids", {}).pop(ssid, None)
        _vpn_save(prof)
        return {"ok": True, "forgot": ssid}

    if action == "autolist":
        return {"ok": True, "auto_ssids": list(prof.get("auto_ssids", {}).keys()),
                "counts": prof.get("counts", {})}

    # observe: bump the connected-on-this-wifi counter; auto-learn after a threshold
    if action == "observe":
        connected, _, _ = _vpn_status()
        ssid = _current_ssid()
        if connected and ssid:
            c = prof.setdefault("counts", {})
            c[ssid] = c.get(ssid, 0) + 1
            # 3 separate observed sessions on the same wifi → learn it
            if c[ssid] >= 3 and ssid not in prof.get("auto_ssids", {}):
                prof.setdefault("auto_ssids", {})[ssid] = {"ts": int(time.time()), "auto": True}
                _vpn_save(prof)
                return {"ok": True, "auto_learned": ssid, "count": c[ssid]}
            _vpn_save(prof)
        return {"ok": True, "ssid": ssid, "connected": connected,
                "count": prof.get("counts", {}).get(ssid, 0)}

    # autocheck: if current wifi is a learned auto-ssid and vpn is off, connect it
    if action == "autocheck":
        ssid = _current_ssid()
        if not ssid:
            return {"ok": True, "action": "none", "reason": "no wifi"}
        if ssid not in prof.get("auto_ssids", {}):
            return {"ok": True, "action": "none", "reason": f"'{ssid}' not a learned auto-vpn wifi"}
        connected, server, _ = _vpn_status()
        if connected:
            return {"ok": True, "action": "none", "reason": "already connected", "server": server}
        r = _sh(["protonvpn", "connect"], timeout=45)
        return {"ok": r.get("ok", False), "action": "connected", "ssid": ssid, "out": (r.get("out") or "")[:200]}

    return {"ok": False, "error": "action must be status|connect|disconnect|signin|autolearn|autoforget|autolist|autocheck|observe"}


NIGHT_LIGHT_PID = "/tmp/qs_wlsunset.pid"
SETTINGS_FILE = os.path.expanduser("~/.config/hypr/settings.json")


def _settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _night_light_running():
    try:
        pid = int(open(NIGHT_LIGHT_PID).read().strip())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


def t_night_light(args):
    action = args.get("action", "toggle")
    running = _night_light_running()
    if action == "status":
        return {"ok": True, "on": running is not None}
    if action == "toggle":
        action = "off" if running else "on"
    if action == "off":
        if running:
            try:
                os.kill(running, 15)
            except OSError:
                pass
            os.remove(NIGHT_LIGHT_PID)
        return {"ok": True, "on": False}
    if action == "on":
        if running:
            return {"ok": True, "on": True}
        s = _settings()
        temp = str(args.get("temp", s.get("nightLightTemp", 4000)))
        start = s.get("nightLightStart", "18:00")
        end = s.get("nightLightEnd", "07:00")
        proc = subprocess.Popen(
            ["wlsunset", "-t", temp, "-T", "6500", "-S", start, "-s", end],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        with open(NIGHT_LIGHT_PID, "w") as f:
            f.write(str(proc.pid))
        return {"ok": True, "on": True}
    return {"ok": False, "error": "action must be on|off|toggle|status"}


def t_media_control(args):
    action = args.get("action", "play-pause")
    if action not in ("play-pause", "next", "previous", "pause", "play", "stop"):
        return {"ok": False, "error": "action must be play-pause|next|previous|pause|play|stop"}
    return _sh(["playerctl", action])


def t_set_wallpaper(args):
    name = args.get("name", "random")
    return _sh([os.path.join(QS, "wallpaper/set_wallpaper.sh"), name], timeout=30)


CDP = "http://localhost:9222"


def _cdp(path, method="GET"):
    req = urllib.request.Request(CDP + path, method=method)
    with urllib.request.urlopen(req, timeout=5) as r:
        return r.read().decode()


def t_browser_tabs(_):
    try:
        tabs = json.loads(_cdp("/json/list"))
    except Exception as e:
        return {"ok": False, "error": f"Vivaldi CDP not reachable on :9222 ({e})"}
    return {"ok": True, "tabs": [{"id": t["id"], "title": t.get("title", ""), "url": t.get("url", "")}
                                  for t in tabs if t.get("type") == "page"]}


def t_browser_open(args):
    url = args.get("url", "").strip()
    if not url:
        return {"ok": False, "error": "url required"}
    if "://" not in url:
        url = "https://" + url
    new_path = "/json/new?" + urllib.parse.quote(url, safe="")
    try:
        t = json.loads(_cdp(new_path, method="PUT"))
        return {"ok": True, "id": t["id"], "url": t.get("url", url)}
    except Exception:
        pass
    _launch("vivaldi --remote-debugging-port=9222", background=True)
    for _ in range(20):
        time.sleep(0.5)
        try:
            t = json.loads(_cdp(new_path, method="PUT"))
            return {"ok": True, "id": t["id"], "url": t.get("url", url), "launched": True}
        except Exception:
            continue
    return {"ok": False, "error": "Vivaldi CDP not reachable on :9222 after launch attempt"}


def t_browser_switch_tab(args):
    tid = args.get("id", "").strip()
    if not tid:
        return {"ok": False, "error": "id required (get it from browser_tabs)"}
    try:
        _cdp(f"/json/activate/{tid}")
    except Exception as e:
        return {"ok": False, "error": f"Vivaldi CDP not reachable on :9222 ({e})"}
    return {"ok": True}


def t_browser_close_tab(args):
    tid = args.get("id", "").strip()
    if not tid:
        return {"ok": False, "error": "id required (get it from browser_tabs)"}
    try:
        _cdp(f"/json/close/{tid}")
    except Exception as e:
        return {"ok": False, "error": f"Vivaldi CDP not reachable on :9222 ({e})"}
    return {"ok": True}


def _ws_frame(payload):
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    length = len(payload)
    if length < 126:
        header = struct.pack("!BB", 0x81, 0x80 | length)
    elif length < 65536:
        header = struct.pack("!BBH", 0x81, 0x80 | 126, length)
    else:
        header = struct.pack("!BBQ", 0x81, 0x80 | 127, length)
    return header + mask + masked


def _ws_recv(sock):
    data = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError("CDP websocket closed before a full frame arrived")
        data += chunk
        if len(data) < 2:
            continue
        b1 = data[1]
        is_masked = bool(b1 & 0x80)
        plen = b1 & 0x7F
        idx = 2
        if plen == 126:
            if len(data) < 4:
                continue
            plen, idx = struct.unpack("!H", data[2:4])[0], 4
        elif plen == 127:
            if len(data) < 10:
                continue
            plen, idx = struct.unpack("!Q", data[2:10])[0], 10
        if is_masked:
            idx += 4
        if len(data) < idx + plen:
            continue
        body = data[idx:idx + plen]
        if is_masked:
            m = data[idx - 4:idx]
            body = bytes(c ^ m[i % 4] for i, c in enumerate(body))
        return body


def _cdp_ws_eval(ws_url, expression, timeout=8):
    u = urllib.parse.urlparse(ws_url)
    path = u.path + (("?" + u.query) if u.query else "")
    key = base64.b64encode(os.urandom(16)).decode()
    sock = socket.create_connection((u.hostname, u.port or 80), timeout=timeout)
    try:
        req = (f"GET {path} HTTP/1.1\r\nHost: {u.hostname}:{u.port}\r\n"
               "Upgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += sock.recv(4096)
        msg = json.dumps({"id": 1, "method": "Runtime.evaluate",
                           "params": {"expression": expression, "returnByValue": True}}).encode()
        sock.sendall(_ws_frame(msg))
        sock.settimeout(timeout)
        return json.loads(_ws_recv(sock).decode())
    finally:
        sock.close()


def _cdp_ws_send(ws_url, messages, timeout=8):
    """Generic version of _cdp_ws_eval — sends an ordered list of {method, params}
    CDP commands over ONE connection (not just Runtime.evaluate) and returns one parsed
    response per message, same order. Lets a caller (qs_probe.py's browser click tool)
    drive Input.dispatchMouseEvent/dispatchKeyEvent directly — native in-page clicks at
    exact viewport coordinates, no OS-level coordinate translation, no window-focus
    race, none of the ydotool scale-factor issues that affect real desktop clicks."""
    u = urllib.parse.urlparse(ws_url)
    path = u.path + (("?" + u.query) if u.query else "")
    key = base64.b64encode(os.urandom(16)).decode()
    sock = socket.create_connection((u.hostname, u.port or 80), timeout=timeout)
    try:
        req = (f"GET {path} HTTP/1.1\r\nHost: {u.hostname}:{u.port}\r\n"
               "Upgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += sock.recv(4096)
        sock.settimeout(timeout)
        results = []
        for i, m in enumerate(messages, start=1):
            msg = json.dumps({"id": i, "method": m["method"], "params": m.get("params", {})}).encode()
            sock.sendall(_ws_frame(msg))
            results.append(json.loads(_ws_recv(sock).decode()))
        return results
    finally:
        sock.close()


def t_browser_eval(args):
    expression = args.get("expression", "").strip()
    if not expression:
        return {"ok": False, "error": "expression required"}
    tab_id = args.get("id", "").strip()
    try:
        tabs = json.loads(_cdp("/json/list"))
    except Exception as e:
        return {"ok": False, "error": f"Vivaldi CDP not reachable on :9222 ({e})"}
    pages = [t for t in tabs if t.get("type") == "page"]
    if not pages:
        return {"ok": False, "error": "no open tabs"}
    tab = next((t for t in pages if t["id"] == tab_id), None) if tab_id else pages[0]
    if tab is None:
        return {"ok": False, "error": f"tab id {tab_id} not found"}
    ws_url = tab.get("webSocketDebuggerUrl")
    if not ws_url:
        return {"ok": False, "error": "tab has no debugger websocket url"}
    try:
        resp = _cdp_ws_eval(ws_url, expression)
    except Exception as e:
        return {"ok": False, "error": f"eval failed: {e}"}
    result = resp.get("result", {}).get("result", {})
    if resp.get("result", {}).get("exceptionDetails"):
        return {"ok": False, "error": resp["result"]["exceptionDetails"].get("text", "JS exception")}
    return {"ok": True, "value": result.get("value", result.get("description"))}


def _find_window(target):
    r = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5)
    try:
        wins = json.loads(r.stdout)
    except Exception:
        return None
    t = target.lower()
    for w in wins:
        if t in w.get("class", "").lower() or t in w.get("initialClass", "").lower() \
                or t in w.get("title", "").lower():
            return w
    return None


def t_screenshot(args):
    if not cap_gate.request("screenshot", "take a screenshot to see the screen"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    mode = args.get("mode", "full")
    target = args.get("target", "").strip()
    path = f"/tmp/qs_agent_screenshot_{int(time.time())}.png"
    cmd = ["grim"]
    if mode == "window":
        win = _find_window(target) if target else None
        if win is None:
            try:
                win = json.loads(subprocess.run(["hyprctl", "activewindow", "-j"],
                                                 capture_output=True, text=True, timeout=5).stdout)
            except Exception:
                win = None
        if win:
            x, y = win["at"]
            w, h = win["size"]
            cmd += ["-g", f"{x},{y} {w}x{h}"]
    cmd.append(path)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    if r.returncode != 0 or not os.path.exists(path):
        return {"ok": False, "error": (r.stderr or "grim failed").strip()[:300]}
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return {"_image": data, "_mime": "image/png", "path": path}


def t_record_screen(args):
    if not cap_gate.request("record_screen", "record the screen to a video"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    dur = max(1, min(int(args.get("duration", 8)), 120))
    geom = (args.get("geometry") or "").strip()
    mode = geom if geom else args.get("mode", "full")
    path = args.get("path") or f"/tmp/qs_agent_recording_{int(time.time())}.mp4"
    script = os.path.expanduser("~/.config/hypr/scripts/screenrec.sh")
    cmd = ["bash", script, str(dur), path, mode]
    if args.get("audio"):
        cmd.append("--audio")
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=dur + 25)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return {"ok": False, "error": (r.stderr or r.stdout or "wf-recorder failed").strip()[:300]}
    return {"ok": True, "path": path, "bytes": os.path.getsize(path), "duration": dur}


WIN_ACTIONS = {"focus": "focuswindow", "close": "killactive", "float": "togglefloating",
               "fullscreen": "fullscreen", "pin": "pin"}


def _focus_window(win):
    """Focus a window without yanking it out of a special workspace —
    plain focuswindow promotes special-workspace windows onto the active
    workspace instead of just toggling them into view."""
    ws_name = (win.get("workspace") or {}).get("name", "")
    if ws_name.startswith("special:"):
        return _sh(["hyprctl", "dispatch", "togglespecialworkspace", ws_name[len("special:"):]])
    return _sh(["hyprctl", "dispatch", "focuswindow", f"address:{win['address']}"])


def _current_window_addr():
    try:
        win = json.loads(subprocess.run(["hyprctl", "activewindow", "-j"],
                                         capture_output=True, text=True, timeout=5).stdout)
        return win.get("address")
    except Exception:
        return None


_ela_mod = None


def _electron_mod():
    global _ela_mod
    if _ela_mod is None:
        import importlib.util
        p = os.path.expanduser("~/.config/hypr/scripts/electron-a11y.py")
        spec = importlib.util.spec_from_file_location("electron_a11y", p)
        if not spec or not spec.loader:
            raise ImportError("electron-a11y.py not loadable")
        _ela_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_ela_mod)
    return _ela_mod


def _inject_electron_flag(app):
    try:
        m = _electron_mod()
        appid = m.flatpak_appid(app)
        if (appid and m.flatpak_is_electron(appid)) or (appid is None and m.native_is_electron(app)):
            return m.inject_flag(app)
    except Exception:
        pass
    return app


def _launch(app, workspace=None, background=False):
    """Launch app via hyprctl exec. If background, opens without stealing focus/workspace
    and restores whatever was focused beforehand once the new window settles. Electron/CEF
    targets get --force-renderer-accessibility injected so the agent's AT-SPI tier can read
    their UI tree (Chromium ignores runtime a11y activation; the flag-at-launch is required)."""
    app = _inject_electron_flag(app)
    prev_addr = _current_window_addr() if background else None
    parts = ([f"workspace {workspace}"] if workspace else []) + (["silent"] if background else [])
    cmd = f"[{' '.join(parts)}] {app}" if parts else app
    r = _sh(["hyprctl", "dispatch", "exec", cmd])
    if background and prev_addr:
        subprocess.Popen(
            ["bash", "-c", f"sleep 1.5; hyprctl dispatch focuswindow address:{prev_addr} >/dev/null 2>&1"],
            start_new_session=True)
    return r


def t_window_control(args):
    if not cap_gate.request("window_control", "move/resize/focus/launch a window"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    action = args.get("action", "")
    if action == "list":
        r = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5)
        try:
            return {"ok": True, "windows": json.loads(r.stdout)}
        except Exception:
            return {"ok": False, "error": "could not parse hyprctl clients"}
    if action == "launch":
        app = args.get("target", "").strip()
        if not app:
            return {"ok": False, "error": "target (command) required for launch"}
        return _launch(app, args.get("workspace"), bool(args.get("background", False)))
    if action == "workspace":
        ws = args.get("workspace", "")
        if not ws:
            return {"ok": False, "error": "workspace required"}
        return _sh(["hyprctl", "dispatch", "workspace", str(ws)])
    if action in ("move", "resize"):
        direction = args.get("direction", "")
        if direction not in ("l", "r", "u", "d"):
            return {"ok": False, "error": "direction must be l|r|u|d"}
        dispatch = "movewindow" if action == "move" else "resizeactive"
        return _sh(["hyprctl", "dispatch", dispatch, direction])
    if action == "focus":
        target = args.get("target", "").strip()
        win = _find_window(target) if target else None
        if win:
            return _focus_window(win)
        return _sh(["hyprctl", "dispatch", "focuswindow"] + ([f"class:{target}"] if target else []))
    if action in WIN_ACTIONS:
        target = args.get("target", "").strip()
        d = WIN_ACTIONS[action]
        return _sh(["hyprctl", "dispatch", d] + ([f"class:{target}"] if target else []))
    return {"ok": False, "error": f"unknown action; valid: list, launch, workspace, move, resize, {', '.join(WIN_ACTIONS)}"}


def t_app_open(args):
    if not cap_gate.request("window_control", "focus or launch an app"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    target = args.get("target", "").strip()
    if not target:
        return {"ok": False, "error": "target required"}
    launch_cmd = args.get("launch_cmd", "").strip() or target
    workspace = args.get("workspace")
    background = bool(args.get("background", False))
    win = _find_window(target)
    if win:
        r = _focus_window(win)
        r.update({"action": "focused", "class": win.get("class"), "title": win.get("title")})
        return r
    r = _launch(launch_cmd, workspace, background)
    r.update({"action": "launched", "target": launch_cmd})
    return r


def t_input_control(args):
    if not cap_gate.request("input_control", "simulate a click/keypress/type"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    if not shutil.which("ydotool"):
        return {"ok": False, "error": "ydotool not installed — run: sudo pacman -S ydotool && "
                "sudo systemctl enable --now ydotool"}
    action = args.get("action", "")
    if action == "click":
        button = args.get("button", "left")
        code = {"left": "0xC0", "right": "0xC1", "middle": "0xC2"}.get(button, "0xC0")
        return _sh(["ydotool", "click", code], env=YDOTOOL_ENV)
    if action == "key":
        keys = args.get("keys", "").strip()
        if not keys:
            return {"ok": False, "error": "keys required, e.g. 'ctrl+c'"}
        return _sh(["ydotool", "key"] + [f"{k}:1" for k in keys.split("+")] +
                   [f"{k}:0" for k in reversed(keys.split("+"))], env=YDOTOOL_ENV)
    if action == "type":
        text = args.get("text", "")
        if not text:
            return {"ok": False, "error": "text required"}
        return _sh(["ydotool", "type", text], env=YDOTOOL_ENV)
    if action == "move":
        x, y = args.get("x", 0), args.get("y", 0)
        return _sh(["ydotool", "mousemove", "-a", "-x", str(x), "-y", str(y)], env=YDOTOOL_ENV)
    return {"ok": False, "error": "action must be click|key|type|move"}


def t_file_ops(args):
    if not cap_gate.request("file_ops", "read/write/organize a file"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    action = args.get("action", "")
    path = os.path.expanduser(args.get("path", ""))
    if action == "list":
        if not _in_allowed(path):
            return {"ok": False, "error": f"path not in allowed dirs: {ALLOWED_DIRS}"}
        try:
            return {"ok": True, "entries": sorted(os.listdir(path))}
        except OSError as e:
            return {"ok": False, "error": str(e)}
    if action == "read":
        if not _in_allowed(path):
            return {"ok": False, "error": f"path not in allowed dirs: {ALLOWED_DIRS}"}
        try:
            with open(path, errors="replace") as f:
                return {"ok": True, "content": f.read()[:20000]}
        except OSError as e:
            return {"ok": False, "error": str(e)}
    if action == "write":
        if not _in_allowed(path):
            return {"ok": False, "error": f"path not in allowed dirs: {ALLOWED_DIRS}"}
        content = args.get("content", "")
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)
            return {"ok": True}
        except OSError as e:
            return {"ok": False, "error": str(e)}
    if action == "move":
        dst = os.path.expanduser(args.get("dst", ""))
        if not (_in_allowed(path) and _in_allowed(dst)):
            return {"ok": False, "error": f"both src and dst must be in allowed dirs: {ALLOWED_DIRS}"}
        try:
            shutil.move(path, dst)
            return {"ok": True}
        except OSError as e:
            return {"ok": False, "error": str(e)}
    return {"ok": False, "error": "action must be list|read|write|move"}


def t_clipboard_control(args):
    if not cap_gate.request("clipboard_control", "read or write the clipboard"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    action = args.get("action", "")
    if action == "read":
        r = subprocess.run(["wl-paste", "-n"], capture_output=True, timeout=5)
        if r.returncode != 0:
            return {"ok": False, "error": (r.stderr or b"wl-paste failed").decode("utf-8", "replace").strip()[:300]}
        try:
            return {"ok": True, "content": r.stdout.decode("utf-8")}
        except UnicodeDecodeError:
            mime = subprocess.run(["wl-paste", "-l"], capture_output=True, text=True, timeout=5).stdout.strip()
            return {"ok": True, "content": "", "binary": True, "mime": mime, "bytes": len(r.stdout)}
    if action == "write":
        text = args.get("text", "")
        try:
            subprocess.run(["wl-copy"], input=text, text=True, timeout=5)
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}
    if action == "history":
        r = subprocess.run(["cliphist", "list"], capture_output=True, text=True, timeout=5)
        if r.returncode != 0:
            return {"ok": False, "error": (r.stderr or "cliphist failed").strip()[:300]}
        return {"ok": True, "entries": r.stdout.splitlines()[:30]}
    return {"ok": False, "error": "action must be read|write|history"}


def t_process_control(args):
    if not cap_gate.request("process_control", "list or kill a process"):
        return {"ok": False, "pending": True, "error": "needs approval, notification sent"}
    action = args.get("action", "")
    if action == "list":
        r = subprocess.run(["ps", "-eo", "pid,pcpu,pmem,comm", "--sort=-pcpu"],
                            capture_output=True, text=True, timeout=5)
        return {"ok": True, "processes": r.stdout.splitlines()[:40]}
    if action == "kill":
        pid = args.get("pid")
        name = args.get("name", "").strip()
        if pid:
            return _sh(["kill", str(pid)])
        if name:
            return _sh(["pkill", "-f", name])
        return {"ok": False, "error": "pid or name required"}
    return {"ok": False, "error": "action must be list|kill"}


MAILBOX = "/tmp/qs_claude_mailbox.json"
MAILBOX_MAX = 100


def _mailbox_load():
    try:
        with open(MAILBOX) as f:
            return json.load(f)
    except Exception:
        return []


def _mailbox_save(msgs):
    try:
        tmp = MAILBOX + ".tmp"
        with open(tmp, "w") as f:
            json.dump(msgs[-MAILBOX_MAX:], f)
        os.replace(tmp, MAILBOX)
    except OSError:
        pass


def t_mailbox_post(args):
    """Cross-process note: lets the live session ('me'), the resident daemon,
    and one-shot agent runs leave each other messages without sharing a process —
    same file-poll pattern as the suggestion/pending-task state everywhere else."""
    to = (args.get("to") or "").strip()
    msg = (args.get("msg") or "").strip()
    frm = (args.get("from") or "me").strip()
    if not to or not msg:
        return {"ok": False, "error": "to and msg required"}
    msgs = _mailbox_load()
    entry = {"id": int(time.time() * 1000), "from": frm, "to": to, "msg": msg,
             "ts": int(time.time()), "read": False}
    msgs.append(entry)
    _mailbox_save(msgs)
    return {"ok": True, "id": entry["id"]}


def t_mailbox_read(args):
    for_ = (args.get("for") or "").strip()
    unread_only = args.get("unread_only", True)
    msgs = _mailbox_load()
    out = [m for m in msgs if not for_ or m.get("to") == for_]
    if unread_only:
        out = [m for m in out if not m.get("read")]
    if args.get("mark_read", True):
        ids = {m["id"] for m in out}
        for m in msgs:
            if m["id"] in ids:
                m["read"] = True
        _mailbox_save(msgs)
    return {"ok": True, "messages": out}


def t_scratchpad_note(args):
    """Push text into the user's desktop scratchpad, or save it straight to Obsidian."""
    text = args.get("text") or ""
    cmd = ["python3", os.path.join(os.path.dirname(os.path.abspath(__file__)), "scratchpad_push.py"), "-",
           "--source", (args.get("from") or "claude")]
    if args.get("heading"):
        cmd += ["--heading", args["heading"]]
    if args.get("open"):
        cmd.append("--open")
    if args.get("to_obsidian"):
        cmd += ["--obsidian", args.get("folder") or ""]
    try:
        r = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=20)
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception as e:
        return {"ok": False, "error": str(e)[:200]}


def t_notification_read(_):
    try:
        with open("/tmp/qs_notifications.json") as f:
            return {"ok": True, "notifications": json.load(f)}
    except FileNotFoundError:
        return {"ok": True, "notifications": []}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def t_pinned_cards(_):
    """Compact summary of what's already pinned in the side panel — title, board, card_id,
    and the block kinds each card carries — so card-building can avoid duplicating data the
    user already keeps on screen. Full specs are deliberately omitted to stay cheap."""
    try:
        with open(PINNED_CARDS_FILE) as f:
            pins = json.load(f)
    except (FileNotFoundError, ValueError):
        return {"ok": True, "pinned": []}
    except Exception as e:
        return {"ok": False, "error": str(e)}
    out = []
    for p in pins:
        spec = p.get("spec", {}) or {}
        kinds = [b.get("kind") for b in spec.get("blocks", []) if isinstance(b, dict)]
        metrics = sorted({b["metric"] for b in spec.get("blocks", [])
                          if isinstance(b, dict) and b.get("metric")})
        out.append({"title": spec.get("title", ""), "board": p.get("board", "Default"),
                    "card_id": spec.get("card_id", ""), "blocks": kinds, "metrics": metrics})
    return {"ok": True, "pinned": out}


PINNED_CARDS_FILE = os.path.expanduser("~/.cache/quickshell/claude/pinned_cards.json")
PINNED_CARDS_QML = os.path.join(QS, "PinnedCards.qml")
PINNED_PANEL_PID = os.path.expanduser("~/.cache/quickshell/claude/pinned_panel.pid")
# update_card's patch target for an inline (unpinned) chat card — ClaudeAsk.qml watches
# this and mutates the matching chat row's spec in place by card_id.
CARD_PATCHES_FILE = os.path.expanduser("~/.cache/quickshell/claude/card_patches.json")
# per-card undo trail: card_id -> [spec_snapshot, ...] oldest first, last 5 kept. A
# QML Process pops the tail via inline python -c for zero-token local revert.
CARD_HISTORY_FILE = os.path.expanduser("~/.cache/quickshell/claude/card_history.json")


def _push_card_history(card_id, old_spec):
    if not card_id or old_spec is None:
        return
    if _has_secret_block(old_spec.get("blocks", [])):
        return
    try:
        os.makedirs(os.path.dirname(CARD_HISTORY_FILE), exist_ok=True)
        try:
            with open(CARD_HISTORY_FILE) as f:
                hist = json.load(f)
        except Exception:
            hist = {}
        hist.setdefault(card_id, []).append(old_spec)
        hist[card_id] = hist[card_id][-5:]
        with open(CARD_HISTORY_FILE, "w") as f:
            json.dump(hist, f)
    except OSError:
        pass


def _ensure_pinned_panel():
    # pgrep -f 'quickshell -p.*PinnedCards.qml' is a trap here: the checker process's
    # own argv (this script's path passed to quickshell) literally contains
    # "PinnedCards.qml", so it matches *itself* and always reports "already running" —
    # spawn silently never happens, every time. A PID file sidesteps the self-match.
    try:
        with open(PINNED_PANEL_PID) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return  # still alive
    except (OSError, ValueError):
        pass
    proc = subprocess.Popen(["quickshell", "-p", PINNED_CARDS_QML],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    try:
        os.makedirs(os.path.dirname(PINNED_PANEL_PID), exist_ok=True)
        with open(PINNED_PANEL_PID, "w") as f:
            f.write(str(proc.pid))
    except OSError:
        pass


def _pin_compact_default():
    try:
        with open(os.path.expanduser("~/.config/hypr/settings.json")) as f:
            return bool(json.load(f).get("pinCompactMode", True))
    except Exception:
        return True


def _find_pin(pins, spec):
    """card_id (agent-chosen, stable across show_card/update_card calls) is the precise
    dedup key when present — title-dedup is the fallback for cards that never got one,
    kept for back-compat with cards pinned before card_id existed."""
    card_id = (spec.get("card_id") or "").strip()
    if card_id:
        match = next((p for p in pins if (p.get("spec", {}).get("card_id") or "") == card_id), None)
        if match is not None:
            return match
    title = (spec.get("title") or "").strip().lower()
    return next((p for p in pins if title and (p.get("spec", {}).get("title") or "").strip().lower() == title), None)


def _pin_card(spec, pin_id, board="Default"):
    """Pins spec, deduped by card_id/title — re-pinning the "same" card (e.g. Claude
    calling show_card(pinned=true) again across turns, or update_card) updates the
    existing panel entry in place instead of piling up duplicates. Returns the id
    actually used (existing or new) so the caller can report the real pin_id back to
    the chat card, or None on failure. board groups cards into named tabs in the side
    panel (PinnedCards.qml)."""
    board = (board or "Default").strip() or "Default"
    try:
        os.makedirs(os.path.dirname(PINNED_CARDS_FILE), exist_ok=True)
        try:
            with open(PINNED_CARDS_FILE) as f:
                pins = json.load(f)
        except Exception:
            pins = []
        existing = _find_pin(pins, spec)
        if existing is not None:
            old_spec = existing.get("spec")
            hist_id = ((old_spec or {}).get("card_id") or spec.get("card_id") or "").strip()
            if not _has_secret_block(spec.get("blocks", [])):
                _push_card_history(hist_id, old_spec)
            existing["spec"] = spec
            existing["board"] = board
            pin_id = existing["id"]
        else:
            pins.append({"id": pin_id, "spec": spec, "board": board, "compact": _pin_compact_default()})
        with open(PINNED_CARDS_FILE + ".tmp", "w") as f:
            json.dump(pins, f)
        os.replace(PINNED_CARDS_FILE + ".tmp", PINNED_CARDS_FILE)
    except OSError:
        return None
    _ensure_pinned_panel()
    return pin_id


CARD_TEMPLATES_FILE = os.path.expanduser("~/.local/share/qs_card_templates.json")


def _load_templates():
    try:
        with open(CARD_TEMPLATES_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def t_card_template(args):
    action = args.get("action", "list")
    name = (args.get("name") or "").strip()
    templates = _load_templates()
    if action == "list":
        return {"ok": True, "names": sorted(templates.keys())}
    if action == "get":
        if not name:
            return {"ok": False, "error": "name required"}
        spec = templates.get(name)
        return {"ok": True, "spec": spec} if spec is not None else {"ok": False, "error": f"no template named {name!r}"}
    if action == "save":
        if not name:
            return {"ok": False, "error": "name required"}
        spec = args.get("spec")
        if not isinstance(spec, dict) or not spec.get("title"):
            return {"ok": False, "error": "spec (the same show_card args object: title/icon/blocks) required"}
        templates[name] = spec
        try:
            os.makedirs(os.path.dirname(CARD_TEMPLATES_FILE), exist_ok=True)
            with open(CARD_TEMPLATES_FILE, "w") as f:
                json.dump(templates, f)
        except OSError as e:
            return {"ok": False, "error": str(e)}
        return {"ok": True}
    if action == "delete":
        if not name:
            return {"ok": False, "error": "name required"}
        if templates.pop(name, None) is None:
            return {"ok": False, "error": f"no template named {name!r}"}
        try:
            with open(CARD_TEMPLATES_FILE, "w") as f:
                json.dump(templates, f)
        except OSError as e:
            return {"ok": False, "error": str(e)}
        return {"ok": True}
    return {"ok": False, "error": "action must be list|get|save|delete"}


# server-side guard, not just a UI convention — an unrecognized fn in a secret block
# would mean the client substitutes a typed credential into an arbitrary command, which
# is exactly the hole this whole feature exists to avoid
SECRET_ACTION_ALLOWLIST = {"wifi_connect", "vpn_connect", "bluetooth_pair"}


def _has_secret_block(blocks):
    return any(isinstance(b, dict) and b.get("kind") == "secret" for b in blocks)


def _has_approval_block(blocks):
    for b in blocks:
        if isinstance(b, dict) and b.get("kind") in ("buttons", "pills"):
            for it in b.get("items", []) or []:
                act = (it.get("action") or {}) if isinstance(it, dict) else {}
                fn = act.get("fn")
                if fn == "autopilot_decide":
                    return True
                # reauth / sign-in cards are one-shot — never pin them
                if fn == "open_url" and "accounts.google.com" in str((act.get("args") or {}).get("url", "")):
                    return True
    return False


def t_show_card(args):
    title = args.get("title", "")
    icon = args.get("icon", "")
    blocks = args.get("blocks", []) or []
    if isinstance(blocks, str):
        try: blocks = json.loads(blocks)
        except Exception: blocks = []
    glance = args.get("glance", "")
    for b in blocks:
        if isinstance(b, dict) and b.get("kind") == "secret":
            fn = (b.get("action") or {}).get("fn")
            if fn not in SECRET_ACTION_ALLOWLIST:
                return {"ok": False, "error": f"secret block action.fn must be one of {sorted(SECRET_ACTION_ALLOWLIST)}, got {fn!r}"}
    # an agent-chosen card_id (reused across calls) is what makes update_card possible —
    # without it every show_card mints a fresh id and there's no stable handle to patch
    card_id = (args.get("card_id") or "").strip() or f"card_{int(time.time() * 1000)}"
    card = {"card_id": card_id, "title": title, "icon": icon, "blocks": blocks}
    if glance:
        card["glance"] = glance
    has_actionable = any(isinstance(b, dict) and b.get("kind") in ("buttons", "pills")
                          for b in blocks)
    if has_actionable:
        try:
            with open("/tmp/qs_resident_suggestion", "w") as f:
                json.dump({
                    "key": card_id, "msg": title, "urgency": "normal",
                    "ts": int(time.time()), "action_label": "open",
                    "action_cmd": "open", "label": "wants act"}, f)
        except Exception:
            pass
    if args.get("pinned") and _has_secret_block(blocks):
        return {"ok": False, "error": "cards with a secret block can't be pinned — they're one-shot by design", **card}
    if args.get("pinned") and _has_approval_block(blocks):
        return {"ok": False, "error": "approval cards can't be pinned — they're one-shot by design", **card}
    if args.get("pinned"):
        # pin_id is reported back in the result (not just a bool) so the chat-side card
        # can pick it up and show itself as pinned with a working unpin toggle, instead
        # of looking unpinned in chat while actually pinned in the side panel.
        used_id = _pin_card(card, int(time.time() * 1000) + 1, args.get("board", "Default"))
        card["pinned"] = used_id is not None
        if used_id is not None:
            card["pin_id"] = used_id
    return {"ok": True, **card}


def _apply_block_ops(blocks, block_ops):
    blocks = list(blocks)
    for op in block_ops or []:
        kind = op.get("op")
        if kind == "insert":
            idx = op.get("index", len(blocks))
            blocks.insert(max(0, min(idx, len(blocks))), op.get("block", {}))
        elif kind in ("replace", "remove"):
            idx = op.get("index")
            if idx is None and op.get("match", {}).get("kind"):
                idx = next((i for i, b in enumerate(blocks)
                            if isinstance(b, dict) and b.get("kind") == op["match"]["kind"]), None)
            if idx is not None and 0 <= idx < len(blocks):
                if kind == "replace":
                    blocks[idx] = op.get("block", blocks[idx])
                else:
                    blocks.pop(idx)
    return blocks


def t_update_card(args):
    card_id = (args.get("card_id") or "").strip()
    if not card_id:
        return {"ok": False, "error": "card_id required — the id show_card returned, or one you chose and passed to show_card yourself"}
    patch = args.get("patch", {}) or {}

    # secret blocks are a one-shot, lock-after-use credential prompt — never let a patch
    # resurrect/re-target one, that would defeat the whole point of it being one-shot
    def has_secret(spec):
        return any(isinstance(b, dict) and b.get("kind") == "secret" for b in spec.get("blocks", []))

    applied_pinned = False
    try:
        try:
            with open(PINNED_CARDS_FILE) as f:
                pins = json.load(f)
        except Exception:
            pins = []
        target = next((p for p in pins if (p.get("spec", {}).get("card_id") or "") == card_id), None)
        if target is not None and not has_secret(target["spec"]):
            spec = target["spec"]
            if not has_secret(spec):
                _push_card_history(card_id, json.loads(json.dumps(spec)))
            if "title" in patch: spec["title"] = patch["title"]
            if "icon" in patch: spec["icon"] = patch["icon"]
            if "glance" in patch: spec["glance"] = patch["glance"]
            if "blocks" in patch: spec["blocks"] = patch["blocks"]
            if "block_ops" in patch: spec["blocks"] = _apply_block_ops(spec.get("blocks", []), patch["block_ops"])
            with open(PINNED_CARDS_FILE + ".tmp", "w") as f:
                json.dump(pins, f)
            os.replace(PINNED_CARDS_FILE + ".tmp", PINNED_CARDS_FILE)
            applied_pinned = True
    except OSError:
        pass

    # also drop a patch event for the inline chat row (if the card is/was unpinned, or
    # the user still has the original chat message visible) — ClaudeAsk.qml watches this
    # file and mutates the matching row's spec in place, same card_id key
    try:
        os.makedirs(os.path.dirname(CARD_PATCHES_FILE), exist_ok=True)
        try:
            with open(CARD_PATCHES_FILE) as f:
                queued = json.load(f)
        except Exception:
            queued = []
        queued.append({"card_id": card_id, "patch": patch, "ts": int(time.time() * 1000)})
        with open(CARD_PATCHES_FILE, "w") as f:
            json.dump(queued[-50:], f)
    except OSError:
        pass

    return {"ok": True, "card_id": card_id, "applied_pinned": applied_pinned}


EQ_RC = os.path.expanduser("~/.config/easyeffects/db/equalizerrc")
EQ_PRESETS_DIR = os.path.expanduser("~/.config/easyeffects/output")

# 10-band mapping: freq (Hz) -> band number in equalizerrc (32-band EQ)
EQ_BAND_MAP = {31: 0, 63: 3, 125: 6, 250: 9, 500: 12,
               1000: 15, 2000: 18, 4000: 21, 8000: 24, 16000: 27}


def _eq_parse():
    """Return {section: {key: val}} from equalizerrc. Section names are the part after [soe]."""
    result = {}
    cur = None
    try:
        with open(EQ_RC) as f:
            for line in f:
                s = line.strip()
                if not s or s.startswith(";") or s.startswith("#"):
                    continue
                if s.startswith("[soe][") and s.endswith("]"):
                    cur = s[6:-1]
                    result.setdefault(cur, {})
                elif s.startswith("[") and s.endswith("]"):
                    cur = s[1:-1]
                    result.setdefault(cur, {})
                elif "=" in s and cur is not None:
                    k, _, v = s.partition("=")
                    result[cur][k.strip()] = v.strip()
    except OSError:
        pass
    return result


def _eq_write(sections):
    lines = []
    for sec, kv in sections.items():
        lines.append(f"[soe][{sec}]")
        for k, v in kv.items():
            lines.append(f"{k}={v}")
        lines.append("")
    with open(EQ_RC, "w") as f:
        f.write("\n".join(lines))


def _eq_reload():
    subprocess.Popen(["bash", "-c",
        "pkill easyeffects 2>/dev/null; sleep 0.4; easyeffects --hide-window >/dev/null 2>&1 &"],
        start_new_session=True)
    time.sleep(0.5)


def t_equalizer(args):
    action = args.get("action", "status")

    if action == "status":
        secs = _eq_parse()
        left = secs.get("Equalizer#0#left", {})
        bands = {}
        for freq, bnum in EQ_BAND_MAP.items():
            gain = left.get(f"band{bnum}Gain", "0")
            label = f"{freq}Hz" if freq < 1000 else f"{freq // 1000}kHz"
            bands[label] = float(gain)
        r = subprocess.run(["easyeffects", "-s"], capture_output=True, text=True, timeout=5)
        bypassed = subprocess.run(["easyeffects", "-b", "3"], capture_output=True, text=True, timeout=5)
        return {"ok": True, "bands": bands,
                "presets": r.stdout.strip(),
                "bypassed": "1" in (bypassed.stdout or "")}

    if action == "list_presets":
        r = subprocess.run(["easyeffects", "-p"], capture_output=True, text=True, timeout=5)
        return {"ok": True, "presets": r.stdout.strip()}

    if action == "load_preset":
        name = args.get("name", "").strip()
        if not name:
            return {"ok": False, "error": "name required"}
        r = subprocess.run(["easyeffects", "-l", name], capture_output=True, text=True, timeout=8)
        return {"ok": r.returncode == 0, "out": (r.stdout or r.stderr).strip()[:300]}

    if action == "bypass":
        state = args.get("state", "toggle")
        if state == "toggle":
            r = subprocess.run(["easyeffects", "--bypass-toggle"], capture_output=True, text=True, timeout=5)
        elif state in ("on", "1"):
            r = subprocess.run(["easyeffects", "-b", "1"], capture_output=True, text=True, timeout=5)
        elif state in ("off", "2"):
            r = subprocess.run(["easyeffects", "-b", "2"], capture_output=True, text=True, timeout=5)
        else:
            return {"ok": False, "error": "state must be on|off|toggle"}
        return {"ok": r.returncode == 0}

    if action == "set_band":
        freq = args.get("freq")
        gain = args.get("gain")
        if freq is None or gain is None:
            return {"ok": False, "error": "freq (Hz: 31,63,125,250,500,1000,2000,4000,8000,16000) and gain (dB, e.g. 5.0) required"}
        freq = int(freq)
        if freq not in EQ_BAND_MAP:
            return {"ok": False, "error": f"freq must be one of {sorted(EQ_BAND_MAP.keys())}"}
        bnum = EQ_BAND_MAP[freq]
        gain_str = str(float(gain))
        secs = _eq_parse()
        for ch in ("Equalizer#0#left", "Equalizer#0#right"):
            secs.setdefault(ch, {})[f"band{bnum}Gain"] = gain_str
        _eq_write(secs)
        _eq_reload()
        return {"ok": True, "band": bnum, "freq_hz": freq, "gain_db": float(gain)}

    if action == "set_bands":
        bands = args.get("bands", {})
        if not bands:
            return {"ok": False, "error": "bands required: {31: 5.0, 63: 3.0, ...}"}
        secs = _eq_parse()
        applied = {}
        for freq_str, gain in bands.items():
            freq = int(freq_str)
            if freq not in EQ_BAND_MAP:
                continue
            bnum = EQ_BAND_MAP[freq]
            gain_str = str(float(gain))
            for ch in ("Equalizer#0#left", "Equalizer#0#right"):
                secs.setdefault(ch, {})[f"band{bnum}Gain"] = gain_str
            label = f"{freq}Hz" if freq < 1000 else f"{freq // 1000}kHz"
            applied[label] = float(gain)
        _eq_write(secs)
        _eq_reload()
        return {"ok": True, "applied": applied}

    if action == "flat":
        secs = _eq_parse()
        for bnum in EQ_BAND_MAP.values():
            for ch in ("Equalizer#0#left", "Equalizer#0#right"):
                secs.setdefault(ch, {})[f"band{bnum}Gain"] = "0"
        _eq_write(secs)
        _eq_reload()
        return {"ok": True, "note": "all 10 bands set to 0 dB"}

    return {"ok": False, "error": "action must be status|list_presets|load_preset|bypass|set_band|set_bands|flat"}


IPC_ALLOWED = {
    "/tmp/qs_widget_state",
    "/tmp/qs_resident_suggestion",
    "/tmp/qs_guide_tab",
    "/tmp/qs_guide_scroll",
    "/tmp/qs_alttab_nav",
    "/tmp/qs_volume_state",
}


def t_widget_ipc(args):
    """Write to a quickshell IPC file to control widgets without mouse simulation."""
    cmd = args.get("cmd", "").strip()
    if not cmd:
        return {"ok": False, "error": "cmd required — see description for valid commands"}

    # Named high-level commands mapped to IPC
    if cmd.startswith("widget:"):
        name = cmd[7:].strip()
        try:
            with open("/tmp/qs_widget_state", "w") as f:
                f.write(name)
            return {"ok": True, "wrote": name, "file": "/tmp/qs_widget_state"}
        except OSError as e:
            return {"ok": False, "error": str(e)}

    if cmd.startswith("guide_tab:"):
        tab = cmd[10:].strip()
        try:
            with open("/tmp/qs_guide_tab", "w") as f:
                f.write(tab)
            return {"ok": True, "wrote": tab, "file": "/tmp/qs_guide_tab"}
        except OSError as e:
            return {"ok": False, "error": str(e)}

    if cmd.startswith("claude:"):
        try:
            with open("/tmp/qs_widget_state", "w") as f:
                f.write(cmd)
            return {"ok": True, "wrote": cmd, "file": "/tmp/qs_widget_state"}
        except OSError as e:
            return {"ok": False, "error": str(e)}

    # Raw write: file:path value:content
    target = args.get("file", "").strip()
    value = args.get("value", "").strip()
    if target and value:
        if target not in IPC_ALLOWED:
            return {"ok": False, "error": f"file not in IPC allowlist: {sorted(IPC_ALLOWED)}"}
        try:
            with open(target, "w") as f:
                f.write(value)
            return {"ok": True, "wrote": value, "file": target}
        except OSError as e:
            return {"ok": False, "error": str(e)}

    return {"ok": False, "error": "use cmd='widget:<name>' | cmd='guide_tab:<n>' | cmd='claude:<prompt>' | pass file+value for raw IPC write"}


HYPR_CONF = os.path.expanduser("~/.config/hypr/hyprland.conf")

_KB_CACHE = None
_KB_CACHE_MT = 0


def _parse_keybinds():
    global _KB_CACHE, _KB_CACHE_MT
    try:
        mt = os.path.getmtime(HYPR_CONF)
    except OSError:
        mt = 0
    if _KB_CACHE is not None and mt == _KB_CACHE_MT:
        return _KB_CACHE

    variables = {}
    binds = []
    try:
        with open(HYPR_CONF) as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line and not line.lower().startswith("bind"):
                    k, _, v = line.partition("=")
                    k = k.strip().lstrip("$")
                    variables[k] = v.strip()
                    continue
                if not line.lower().startswith("bind"):
                    continue
                # strip bind type prefix (bind, binde, bindl, bindel, bindm)
                parts = line.split("=", 1)
                if len(parts) < 2:
                    continue
                rhs = parts[1].strip()
                segments = [s.strip() for s in rhs.split(",")]
                if len(segments) < 3:
                    continue
                mods_raw, key, dispatch = segments[0], segments[1], segments[2]
                rest = ",".join(segments[3:]).strip() if len(segments) > 3 else ""
                # substitute variables
                for var, val in variables.items():
                    mods_raw = mods_raw.replace(f"${var}", val)
                mods = [m.strip() for m in mods_raw.replace("&", " ").split() if m.strip()]
                binds.append({"mods": mods, "key": key.strip(),
                               "dispatch": dispatch.strip(), "args": rest})
    except OSError:
        pass
    _KB_CACHE = binds
    _KB_CACHE_MT = mt
    return binds


def _run_keybind(b):
    """Execute what a keybind would do."""
    dispatch = b["dispatch"]
    args = b["args"]
    if dispatch == "exec":
        cmd = args
        for v in ("HOME", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DISPLAY",
                  "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE"):
            if v in os.environ:
                pass  # already in env
        proc = subprocess.Popen(["bash", "-c", cmd], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"ok": True, "launched": cmd, "pid": proc.pid}
    # non-exec: use hyprctl dispatch
    full_dispatch = f"{dispatch} {args}".strip()
    r = _sh(["hyprctl", "dispatch"] + full_dispatch.split())
    return r


VOICE_DIR = os.path.expanduser("~/.config/hypr/scripts/quickshell/claude/voice")


def t_listen(args):
    """Capture mic speech and transcribe (Czech + English auto). Uses the warm
    STT server (faster-whisper on CUDA). Lets the agent *hear* on demand."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "stt_client", os.path.join(VOICE_DIR, "stt_client.py"))
    stt = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stt)
    timeout = float(args.get("timeout", 8))
    lang = args.get("language") or None
    res = stt.listen(timeout=timeout, language=lang)
    if not res.get("ok"):
        return {"ok": False, "error": res.get("error", "stt failed")}
    return {"ok": True, "text": res.get("text", ""), "language": res.get("lang", ""),
            "heard": bool(res.get("text", "").strip())}


def t_voice_wake(args):
    """Control the always-on wake-word listener ('hey jarvis' → speak → agent)."""
    action = args.get("action", "status")
    if action == "start":
        subprocess.Popen(["bash", os.path.join(VOICE_DIR, "wake.sh")],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return {"ok": True, "started": True}
    if action == "stop":
        pid = "/tmp/qs_wake_daemon.pid"
        if os.path.exists(pid):
            try:
                os.kill(int(open(pid).read().strip()), 15)
            except (OSError, ValueError):
                pass
        return {"ok": True, "stopped": True}
    # status
    running = os.path.exists("/tmp/qs_wake_active")
    muted = "yes" in _sh(["pactl", "get-source-mute", "@DEFAULT_SOURCE@"]).get("out", "")
    return {"ok": True, "running": running, "mic_muted": muted}


WAKE_TRAIN_DIR = os.path.join(VOICE_DIR, "wake_train")
WAKE_MODEL_PATH = os.path.join(VOICE_DIR, "models", "kandor.onnx")
WAKE_TRAIN_STATUS = "/tmp/qs_wake_train_status.json"
WAKE_TRAIN_LOG = "/tmp/qs_wake_train.log"


def t_retrain_wake_model(args):
    """Kick off (or check on) a retrain of the custom 'yo kandor' wake-word model —
    runs openWakeWord's pipeline in voice/wake_train/ against the current synthetic
    set plus any real recordings dropped into build/kandor/positive_train/."""
    action = args.get("action", "status")
    if action == "status":
        try:
            with open(WAKE_TRAIN_STATUS) as f:
                st = json.load(f)
        except (OSError, json.JSONDecodeError):
            st = {"state": "never_run"}
        tail = ""
        try:
            with open(WAKE_TRAIN_LOG) as f:
                tail = f.read()[-1500:]
        except OSError:
            pass
        st["log_tail"] = tail
        st["model_exists"] = os.path.exists(WAKE_MODEL_PATH)
        if st["model_exists"]:
            st["model_age_days"] = round((time.time() - os.path.getmtime(WAKE_MODEL_PATH)) / 86400, 1)
        return {"ok": True, **st}

    if action != "start":
        return {"ok": False, "error": "action must be start|status"}

    try:
        with open(WAKE_TRAIN_STATUS) as f:
            cur = json.load(f)
    except (OSError, json.JSONDecodeError):
        cur = {}
    if cur.get("state") == "running":
        return {"ok": True, "already_running": True, "started_ts": cur.get("started_ts")}

    started = int(time.time())
    with open(WAKE_TRAIN_STATUS, "w") as f:
        json.dump({"state": "running", "started_ts": started}, f)
    script = (
        f"cd {WAKE_TRAIN_DIR} && "
        f"if bash run_pipeline.sh all > {WAKE_TRAIN_LOG} 2>&1; then "
        f"  mkdir -p {os.path.dirname(WAKE_MODEL_PATH)} && "
        f"  cp build/kandor.onnx {WAKE_MODEL_PATH} && "
        f"  python3 -c \"import json,time; json.dump({{'state':'done','started_ts':{started},"
        f"'finished_ts':int(time.time())}}, open('{WAKE_TRAIN_STATUS}','w'))\"; "
        f"else "
        f"  python3 -c \"import json,time; json.dump({{'state':'failed','started_ts':{started},"
        f"'finished_ts':int(time.time())}}, open('{WAKE_TRAIN_STATUS}','w'))\"; "
        f"fi"
    )
    subprocess.Popen(["bash", "-c", script], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True, "started": True, "started_ts": started,
            "note": "runs in the background, can take a while — poll with action:'status'"}


def t_keybind(args):
    action = args.get("action", "list")

    if action == "list":
        binds = _parse_keybinds()
        out = []
        for b in binds:
            mods = "+".join(b["mods"]) if b["mods"] else "none"
            label = f"{mods}+{b['key']}" if b["mods"] else b["key"]
            desc = b["dispatch"]
            if b["dispatch"] == "exec":
                desc = b["args"][:80]
            elif b["args"]:
                desc = f"{b['dispatch']} {b['args']}"
            out.append({"combo": label, "action": desc})
        return {"ok": True, "count": len(out), "binds": out}

    if action == "run":
        combo = args.get("combo", "").strip()
        if not combo:
            return {"ok": False, "error": "combo required, e.g. 'SUPER+T' or 'SUPER+SHIFT+E'"}
        # normalise: uppercase, sort mods
        parts = [p.strip().upper() for p in combo.replace("+", " ").split() if p.strip()]
        key = parts[-1]
        mods = set(parts[:-1])

        binds = _parse_keybinds()
        match = None
        for b in binds:
            bmods = {m.upper().replace("SHIFT_L", "SHIFT").replace("CTRL_L", "CTRL")
                     for m in b["mods"]}
            cmods = {m.replace("SHIFT_L", "SHIFT").replace("CTRL_L", "CTRL") for m in mods}
            if b["key"].upper() == key and bmods == cmods:
                match = b
                break
        if not match:
            return {"ok": False, "error": f"no keybind found for '{combo}'"}
        return _run_keybind(match)

    if action == "search":
        query = args.get("query", "").strip().lower()
        if not query:
            return {"ok": False, "error": "query required"}
        binds = _parse_keybinds()
        results = []
        for b in binds:
            haystack = (b["dispatch"] + " " + b["args"] + " " + b["key"]).lower()
            if query in haystack:
                mods = "+".join(b["mods"]) if b["mods"] else ""
                label = f"{mods}+{b['key']}" if mods else b["key"]
                desc = b["args"][:80] if b["dispatch"] == "exec" else f"{b['dispatch']} {b['args']}"
                results.append({"combo": label, "action": desc})
        return {"ok": True, "matches": results}

    return {"ok": False, "error": "action must be list|run|search"}


def _mira():
    import mira_mail
    return mira_mail


def t_mail_search(args):
    mm = _mira()
    try:
        return mm.search((args.get("query") or "").strip(), args.get("account") or None, args.get("limit") or 8)
    except mm.MailError as e:
        return {"ok": False, "error": str(e)}


def t_mail_read(args):
    mm = _mira()
    try:
        return mm.read((args.get("thread_id") or "").strip(), args.get("account") or None,
                       int(args.get("max_chars") or 6000))
    except mm.MailError as e:
        return {"ok": False, "error": str(e)}


def t_mail_open(args):
    mm = _mira()
    try:
        return mm.open_in_mira((args.get("thread_id") or "").strip() or None, args.get("account") or None,
                               (args.get("query") or "").strip() or None)
    except mm.MailError as e:
        return {"ok": False, "error": str(e)}


TOOLS = [
    {"name": "mail_search",
     "description": "Search the user's mail through Mira (their Gmail client) across every account Mira has connected. "
                     "Takes Gmail search syntax: from:, to:, subject:, has:attachment, after:YYYY/MM/DD, before:, newer_than:7d, "
                     "in:anywhere, label:, is:unread, plus free words. Turn fuzzy asks into a query yourself (\"that email from Alza "
                     "about the refund\" -> 'from:alza refund'); if nothing comes back, loosen it (drop words, add in:anywhere) and retry once. "
                     "Each result has thread_id, account, from, subject, date, snippet, unread and an open_action. To let the user jump "
                     "straight to a hit, show_card with a buttons block whose action is the result's open_action "
                     "({fn:'open_mail', args:{thread_id, account}}) labelled 'Open in Mira' - runs locally, no approval needed.",
     "inputSchema": {"type": "object", "properties": {
         "query": {"type": "string", "description": "Gmail search query"},
         "account": {"type": "string", "description": "limit to one Mira account email; omit for all"},
         "limit": {"type": "integer", "description": "max threads per account (1-25)", "default": 8}},
         "required": ["query"]},
     "fn": t_mail_search},
    {"name": "mail_read",
     "description": "Read a mail thread found via mail_search (plain text of each message, newest kept when truncated). "
                     "Use when the user asks what an email says, not just whether it exists.",
     "inputSchema": {"type": "object", "properties": {
         "thread_id": {"type": "string"},
         "account": {"type": "string", "description": "account from the search result"},
         "max_chars": {"type": "integer", "default": 6000}},
         "required": ["thread_id"]},
     "fn": t_mail_read},
    {"name": "mail_open",
     "description": "Bring up Mira (SUPER+SHIFT+Y mail client) on a specific thread (thread_id + account from mail_search), "
                     "or with its search box pre-filled (query). Launches Mira if it isn't running.",
     "inputSchema": {"type": "object", "properties": {
         "thread_id": {"type": "string"},
         "account": {"type": "string"},
         "query": {"type": "string", "description": "open Mira's search on this query instead of a thread"}}},
     "fn": t_mail_open},
    {"name": "get_system_state",
     "description": "Live machine state: battery (percent/status), audio volume/mute, mic on/off, wifi, bluetooth, keyboard layout, CPU%, load, memory, temperature, top process, uptime.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_system},
    {"name": "list_events",
     "description": "Today's calendar: header summary, timed events (with mins_until), all-day items, and currently active events.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_events},
    {"name": "list_tasks",
     "description": "Open Google Tasks for today with their task_id and tasklist_id (needed to complete them later).",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_tasks},
    {"name": "focus_stats",
     "description": "Per-application focus/usage time from focustime tracking for a given day.",
     "inputSchema": {"type": "object", "properties": {
         "date": {"type": "string", "description": "ISO date YYYY-MM-DD; omit for today"},
         "app": {"type": "string", "description": "optional app_class filter"}}},
     "fn": t_focus},
    {"name": "read_quickshell_logs",
     "description": "Tail the most recent quickshell log file. Use to diagnose QML errors in widgets.",
     "inputSchema": {"type": "object", "properties": {
         "lines": {"type": "integer", "description": "how many trailing lines", "default": 60}}},
     "fn": t_logs},
    {"name": "complete_task",
     "description": "Mark a Google Task done (or toggle it back). Get task_id and tasklist_id from list_tasks first.",
     "inputSchema": {"type": "object", "properties": {
         "task_id": {"type": "string"}, "tasklist_id": {"type": "string"}},
         "required": ["task_id", "tasklist_id"]},
     "fn": t_complete_task},
    {"name": "add_task",
     "description": "Add a new Google Task due today. If the title is 4+ words, the result "
                     "may include 'subtask_suggestion': {first_action, subtasks:[...]} (#13 "
                     "task-breakdown) — when present, call show_card with a 'buttons' block "
                     "('Add subtasks' / 'Skip') to offer it; if accepted, call add_task again "
                     "for the first_action and each subtask. Never add them without asking.",
     "inputSchema": {"type": "object", "properties": {
         "title": {"type": "string"}}, "required": ["title"]},
     "fn": t_add_task},
    {"name": "open_widget",
     "description": "Open (or toggle) a quickshell widget popup: battery, volume, notifications, calendar, music, network, monitors, focustime, guide, wallpaper, workspaces, power.",
     "inputSchema": {"type": "object", "properties": {
         "name": {"type": "string"},
         "toggle": {"type": "boolean", "description": "toggle instead of open", "default": False}},
         "required": ["name"]},
     "fn": t_open_widget},
    {"name": "hypr",
     "description": "Run a hyprctl dispatch command, e.g. dispatch='workspace 3', 'movewindow l', 'togglefloating'.",
     "inputSchema": {"type": "object", "properties": {
         "dispatch": {"type": "string"}}, "required": ["dispatch"]},
     "fn": t_hypr},
    {"name": "notify",
     "description": "Send a desktop notification.",
     "inputSchema": {"type": "object", "properties": {
         "title": {"type": "string"}, "body": {"type": "string"},
         "urgency": {"type": "string", "description": "low | normal | critical", "default": "normal"}},
         "required": ["title"]},
     "fn": t_notify},
    {"name": "set_volume",
     "description": "Set output volume to a percent (0-100).",
     "inputSchema": {"type": "object", "properties": {
         "percent": {"type": "integer"}}, "required": ["percent"]},
     "fn": t_set_volume},
    {"name": "toggle_mute",
     "description": "Toggle output (speaker) mute.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_toggle_mute},
    {"name": "mic_mute",
     "description": "Mute or unmute the microphone. muted=true mutes, false unmutes.",
     "inputSchema": {"type": "object", "properties": {
         "muted": {"type": "boolean", "default": True}}},
     "fn": t_mic_mute},
    {"name": "power_profile",
     "description": "Set the system power profile.",
     "inputSchema": {"type": "object", "properties": {
         "profile": {"type": "string", "description": "performance | balanced | power-saver"}},
         "required": ["profile"]},
     "fn": t_power_profile},
    {"name": "set_brightness",
     "description": "Get or set screen backlight brightness. Omit value to read current; pass '50%' to set, '+10%'/'10%-' to adjust relative.",
     "inputSchema": {"type": "object", "properties": {
         "value": {"type": "string", "description": "e.g. '50%', '+10%', '10%-'; omit to read current"}}},
     "fn": t_set_brightness},
    {"name": "audio_device",
     "description": "List audio devices (action=list shows wpctl status with node ids) or switch the default output/input (action=set, id=<node id from list>). Use to move sound to headphones/speakers or pick a mic.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "list | set"},
         "id": {"type": "string", "description": "numeric wpctl node id (for set)"},
         "kind": {"type": "string", "description": "sink (output) | source (input)"}}},
     "fn": t_audio_device},
    {"name": "systemd_service",
     "description": "Control systemd services. action=list shows running; status|start|stop|restart act on a named service. scope=user (default) or system. For system scope, start/stop may need privileges and could fail without them.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "status | start | stop | restart | is-active | list"},
         "service": {"type": "string"}, "scope": {"type": "string", "description": "user | system"}},
         "required": ["action"]},
     "fn": t_systemd_service},
    {"name": "vpn_control",
     "description": "Control ProtonVPN and manage per-wifi auto-connect. actions: status (connected?, server, current ssid, whether this wifi is a learned auto-vpn spot); connect (fastest, or server=<id/country like 'NL' or 'NL-FREE#214'>); disconnect; autolearn (mark the current/given ssid so VPN auto-connects there — use when the user says 'always vpn on this wifi'); autoforget; autolist (which wifis auto-connect); autocheck (if the current wifi is a learned spot and VPN is off, connect it — the resident calls this on wifi change); observe (bump the 'was connected on this wifi' counter, auto-learns after 3 sessions); signin (returns instructions — interactive, agent can't do it). Default idle: never connects unless told or on a learned wifi.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "status|connect|disconnect|autolearn|autoforget|autolist|autocheck|observe|signin"},
         "server": {"type": "string", "description": "optional server/country for connect, e.g. 'NL' or 'NL-FREE#214'"},
         "ssid": {"type": "string", "description": "optional wifi ssid for autolearn/autoforget (defaults to current wifi)"}},
         "required": ["action"]},
     "fn": t_vpn_control},
    {"name": "reminder",
     "description": "Set a real timed reminder that fires a desktop notification after N minutes (uses a transient systemd timer, survives this turn). Use when the user says 'remind me to X in N minutes'.",
     "inputSchema": {"type": "object", "properties": {
         "text": {"type": "string"}, "minutes": {"type": "number"}},
         "required": ["text", "minutes"]},
     "fn": t_reminder},
    {"name": "display_control",
     "description": "List monitors (action=list — name, resolution, refresh, scale, dpms) or turn a display on/off (action=on|off, optional monitor=<name>; omit monitor for all). Use to blank/wake screens.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "list | on | off"},
         "monitor": {"type": "string"}}},
     "fn": t_display_control},
    {"name": "workspace_status",
     "description": "Check whether Google Workspace (Gmail/Drive/Docs/Sheets/Calendar) is authorized. Returns authed + a reauth_url. Call this before Workspace actions; if authed is false, show the user an UNPINNABLE card titled e.g. 'Google sign-in needed' with a buttons block: [{label:'Authorize Google',icon:'google',action:{fn:'open_url',args:{url:'<reauth_url>'}}}] — clicking opens the consent page in the browser. Re-check after they authorize.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_workspace_status},
    {"name": "wifi_control",
     "description": "Wifi via NetworkManager: status (power + current connection + nearby networks), "
                     "list (alias for status), toggle, on, off, connect [ssid, password?], disconnect.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "status | list | toggle | on | off | connect | disconnect", "default": "status"},
         "ssid": {"type": "string"}, "password": {"type": "string"}}},
     "fn": t_wifi_control},
    {"name": "bluetooth_control",
     "description": "Bluetooth: status (power + connected + nearby/paired devices with mac/name/icon/"
                     "battery), toggle, on, off, connect [mac], disconnect [mac]. Get mac from status first.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "status | toggle | on | off | connect | disconnect", "default": "status"},
         "mac": {"type": "string"}}},
     "fn": t_bluetooth_control},
    {"name": "night_light",
     "description": "Turn the blue-light filter (wlsunset) on/off/toggle, or check status. "
                     "When on, runs warm color temp 18:00-07:00, normal during the day.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "on | off | toggle | status", "default": "toggle"},
         "temp": {"type": "integer", "description": "warm temp in K, default 4000"}}},
     "fn": t_night_light},
    {"name": "media_control",
     "description": "Control the active media player (Spotify etc via playerctl).",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "play-pause | next | previous | pause | play | stop",
                    "default": "play-pause"}}},
     "fn": t_media_control},
    {"name": "set_wallpaper",
     "description": "Set the desktop wallpaper from the wallpaper pool (wallpaperDir in settings.json). "
                     "name='random' (default) picks one at random, or pass an exact filename.",
     "inputSchema": {"type": "object", "properties": {
         "name": {"type": "string", "default": "random"}}},
     "fn": t_set_wallpaper},
    {"name": "suggest",
     "description": "Write a proactive suggestion/nudge to the ClaudeStatus bar widget. Triggers 'needs you' state with the message shown as a tooltip. Use for ambient alerts the user should see when they glance at the bar.",
     "inputSchema": {"type": "object", "properties": {
         "msg": {"type": "string", "description": "Short message shown in tooltip"},
         "urgency": {"type": "string", "description": "normal | critical", "default": "normal"},
         "action_label": {"type": "string", "description": "optional button label"},
         "action_cmd": {"type": "string", "description": "optional shell command on action click"},
         "key": {"type": "string", "description": "dedup key (default: claude)"}},
         "required": ["msg"]},
     "fn": t_suggest},
    {"name": "get_workspaces",
     "description": "Current Hyprland workspace state — id, active/occupied/empty, and window tooltip per workspace.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_workspaces},
    {"name": "get_music",
     "description": "Currently playing track via MPRIS — title, artist, album, player, playback state.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_music},
    {"name": "remember",
     "description": "Save a durable fact about the user or an ongoing matter to long-term memory. Use when the user shares a preference, habit, recurring task, or anything worth recalling later. Pass a category so memory stays organized: preference | fact | project | person | general. Duplicates are auto-skipped, so remember freely without worrying about repeats.",
     "inputSchema": {"type": "object", "properties": {
         "note": {"type": "string"},
         "category": {"type": "string", "description": "preference | fact | project | person | general"}},
         "required": ["note"]},
     "fn": t_remember},
    {"name": "recall",
     "description": "Read saved long-term memory about the user. Optionally pass a category (preference|fact|project|person|general) to read just that slice. For a specific lookup prefer memory_search instead of dumping everything.",
     "inputSchema": {"type": "object", "properties": {
         "category": {"type": "string"}}},
     "fn": t_recall},
    {"name": "memory_search",
     "description": "Search long-term memory for entries relevant to a query — returns the best-matching notes ranked, instead of the whole memory. Use this for a targeted recall ('what do I know about X') to save tokens vs reading everything.",
     "inputSchema": {"type": "object", "properties": {
         "query": {"type": "string"}}, "required": ["query"]},
     "fn": t_memory_search},
    {"name": "browser_tabs",
     "description": "List open Vivaldi tabs (id, title, url) via the CDP debug port. Use this to see "
                     "what's actually open before switching/closing.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_browser_tabs},
    {"name": "browser_open",
     "description": "Open a URL in a new Vivaldi tab. Returns the new tab's id. If Vivaldi isn't "
                     "running, launches it and retries automatically — no need to launch it yourself first.",
     "inputSchema": {"type": "object", "properties": {
         "url": {"type": "string"}}, "required": ["url"]},
     "fn": t_browser_open},
    {"name": "browser_switch_tab",
     "description": "Focus/activate an existing Vivaldi tab by id (from browser_tabs).",
     "inputSchema": {"type": "object", "properties": {
         "id": {"type": "string"}}, "required": ["id"]},
     "fn": t_browser_switch_tab},
    {"name": "browser_close_tab",
     "description": "Close a Vivaldi tab by id (from browser_tabs).",
     "inputSchema": {"type": "object", "properties": {
         "id": {"type": "string"}}, "required": ["id"]},
     "fn": t_browser_close_tab},
    {"name": "screenshot",
     "description": "Capture the screen (full or a specific window) and see it. For mode=window, pass "
                     "target (class/title substring, e.g. 'vivaldi') to capture that app's window "
                     "specifically — otherwise it falls back to whatever's currently focused, which is "
                     "often the chat widget itself and not useful. Gated: first use in an "
                     "unattended/resident run needs user approval (notification sent).",
     "inputSchema": {"type": "object", "properties": {
         "mode": {"type": "string", "description": "full | window", "default": "full"},
         "target": {"type": "string", "description": "window class/title substring, for mode=window"}}},
     "fn": t_screenshot},
    {"name": "record_screen",
     "description": "Record the screen to an mp4 (wf-recorder) for a fixed duration in seconds, then "
                     "return the file PATH (not the video bytes — too large to inline). mode=full records "
                     "the whole screen; pass geometry 'X,Y WxH' to record just a region/widget. Runs "
                     "unattended (no interactive region picker). Gated: first use in a resident run needs "
                     "approval (notification sent).",
     "inputSchema": {"type": "object", "properties": {
         "duration": {"type": "integer", "description": "seconds, 1-120", "default": 8},
         "mode": {"type": "string", "description": "full (default)", "default": "full"},
         "geometry": {"type": "string", "description": "X,Y WxH region; overrides mode"},
         "audio": {"type": "boolean", "default": False},
         "path": {"type": "string", "description": "output mp4 path (optional)"}}},
     "fn": t_record_screen},
    {"name": "window_control",
     "description": "Control windows/workspaces: list, launch <target> [workspace] [background], "
                     "workspace <n>, move/resize <l|r|u|d>, focus/close/float/fullscreen/pin "
                     "[target=window class]. launch's background=true opens the app without "
                     "stealing focus or switching workspace, then restores whatever was focused — "
                     "use it for anything the user didn't directly ask to see right now. "
                     "Gated: first use in an unattended/resident run needs approval.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string"}, "target": {"type": "string"},
         "direction": {"type": "string"}, "workspace": {"type": "string"},
         "background": {"type": "boolean"}},
         "required": ["action"]},
     "fn": t_window_control},
    {"name": "app_open",
     "description": "Focus an app if it's already running, or launch it if not — one call instead of "
                     "list+launch+focus. target is matched against window class/title/initialClass "
                     "(substring, case-insensitive); launch_cmd overrides the command used to launch if "
                     "it differs from target (e.g. target='vivaldi', launch_cmd='vivaldi --new-window'). "
                     "background=true launches without stealing focus/workspace and restores the "
                     "previous focus after — use for ambient/prep opens, not ones the user asked to see.",
     "inputSchema": {"type": "object", "properties": {
         "target": {"type": "string"}, "launch_cmd": {"type": "string"},
         "workspace": {"type": "string"}, "background": {"type": "boolean"}},
         "required": ["target"]},
     "fn": t_app_open},
    {"name": "input_control",
     "description": "Simulate mouse/keyboard input via ydotool: click [button], key [keys e.g. "
                     "'ctrl+c'], type [text], move [x,y]. Gated: first use in an unattended/resident "
                     "run needs approval. Requires ydotool installed.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string"}, "button": {"type": "string"}, "keys": {"type": "string"},
         "text": {"type": "string"}, "x": {"type": "integer"}, "y": {"type": "integer"}},
         "required": ["action"]},
     "fn": t_input_control},
    {"name": "file_ops",
     "description": "Scoped filesystem actuator (separate from the session's own Read/Write): list, "
                     "read, write [content], move [dst]. Restricted to ~/Documents, ~/Downloads, "
                     "~/Images, ~/.config/hypr. Gated: first use in an unattended/resident run needs approval.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string"}, "path": {"type": "string"},
         "content": {"type": "string"}, "dst": {"type": "string"}},
         "required": ["action", "path"]},
     "fn": t_file_ops},
    {"name": "browser_eval",
     "description": "Run a JS expression in an open Vivaldi tab via CDP and get the result back — use "
                     "this to actually read a page (e.g. expression='document.body.innerText.slice(0,5000)' "
                     "or 'document.title'), not just open it blind. Defaults to the first open tab if id "
                     "omitted (get id from browser_tabs).",
     "inputSchema": {"type": "object", "properties": {
         "expression": {"type": "string"}, "id": {"type": "string"}},
         "required": ["expression"]},
     "fn": t_browser_eval},
    {"name": "clipboard_control",
     "description": "Read/write the system clipboard (wl-copy/wl-paste) or view cliphist history: "
                     "read, write [text], history. Gated: first use in an unattended/resident run "
                     "needs approval.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string"}, "text": {"type": "string"}},
         "required": ["action"]},
     "fn": t_clipboard_control},
    {"name": "process_control",
     "description": "List running processes (pid/cpu%/mem%/name, sorted by cpu) or kill one by pid "
                     "or name (pkill -f). Gated: first use in an unattended/resident run needs approval.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string"}, "pid": {"type": "integer"}, "name": {"type": "string"}},
         "required": ["action"]},
     "fn": t_process_control},
    {"name": "notification_read",
     "description": "Read the last ~20 notifications (appName, summary, body) from quickshell's native "
                     "notification server. Note: swaync is killed at startup in this config — "
                     "notifications run through quickshell's own NotificationServer (Main.qml), not "
                     "swaync; this reads that, not swaync's history.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_notification_read},
    {"name": "pinned_cards",
     "description": "List what's already pinned in the persistent side panel — each entry is "
                     "{title, board, card_id, blocks (kinds), metrics}. Call this before building "
                     "a non-trivial or dashboard-style card so you don't duplicate data the user "
                     "already keeps pinned (e.g. don't add a CPU/mem gauge card when a System card "
                     "with those metrics is already pinned — update that one by card_id instead).",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_pinned_cards},
    {"name": "mailbox_post",
     "description": "Leave a note for another Claude process to pick up — 'to' is one of "
                     "'me' (the live coding session), 'resident' (the ambient daemon), or "
                     "'agent' (one-shot resident-spawned runs). Use this instead of guessing "
                     "at shared state when you want another process to know something or act on it.",
     "inputSchema": {"type": "object", "properties": {
         "to": {"type": "string"}, "msg": {"type": "string"}, "from": {"type": "string"}},
         "required": ["to", "msg"]},
     "fn": t_mailbox_post},
    {"name": "scratchpad_note",
     "description": "Save text to the user's notes. Default: appends to the live desktop scratchpad "
                     "(ScratchpadHost; falls back to its save file if not running), optional markdown "
                     "'heading', open=true pops the scratchpad up. to_obsidian=true instead saves the "
                     "text as its own Obsidian note in 'folder' (omitted = auto-suggested from content) "
                     "and shows a resident card. Use when the user says 'save this to my notes'.",
     "inputSchema": {"type": "object", "properties": {
         "text": {"type": "string"}, "heading": {"type": "string"}, "open": {"type": "boolean"},
         "to_obsidian": {"type": "boolean"}, "folder": {"type": "string"}, "from": {"type": "string"}},
         "required": ["text"]},
     "fn": t_scratchpad_note},
    {"name": "mailbox_read",
     "description": "Read mailbox notes addressed to 'for' (defaults to all). unread_only "
                     "defaults true; mark_read defaults true so re-reading doesn't redeliver.",
     "inputSchema": {"type": "object", "properties": {
         "for": {"type": "string"}, "unread_only": {"type": "boolean"}, "mark_read": {"type": "boolean"}}},
     "fn": t_mailbox_read},
    {"name": "card_template",
     "description": "Save/recall a named show_card layout so you don't rebuild the same dashboard "
                     "from scratch every time the user asks for it again. save{name, spec} stores "
                     "spec exactly as you'd pass it to show_card (title/icon/blocks — omit pinned/"
                     "board, pass those fresh each time you actually show it). get{name} returns "
                     "that spec back — pass it straight through to show_card's args. list{} returns "
                     "all saved names. delete{name} removes one. Use this the moment a user reacts "
                     "well to a dashboard you built and might want again ('that's exactly what I "
                     "wanted') — save it under a short name so 'show me my system dashboard' next "
                     "time is one get+show_card call instead of reconstructing every block/source.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "list | get | save | delete", "default": "list"},
         "name": {"type": "string"},
         "spec": {"type": "object", "description": "for action=save: the title/icon/blocks object, same shape as show_card's args"}},
         "required": ["action"]},
     "fn": t_card_template},
    {"name": "show_card",
     "description": "Push a composable interactive card into the chat UI instead of plain text. "
                     "Give it a title/icon and a list of 'blocks' — stack as many as you want, any "
                     "order, mix freely, to build whatever layout fits. Block kinds:\n"
                     "  rows    — {kind:'rows', items:[{icon?,label,value}]} — icon+label/value grid, "
                     "            2 per row (good for spec sheets: OS, kernel, CPU, GPU, user...).\n"
                     "  gauges  — {kind:'gauges', items:[{icon?,label,value,metric?,source?,interval_ms?}]} — "
                     "            circular ring meters for percent-like values (0-1, 0-100, or '73%'), "
                     "            evenly fill the card width.\n"
                     "  bars    — {kind:'bars', items:[{icon?,label,value,metric?,source?,interval_ms?}]} — "
                     "            linear progress bars (icon + bar + optional value), stacked, for "
                     "            things like storage/volume.\n"
                     "  table   — {kind:'table', headers:['PID','Name','CPU'], rows:[[...]]} OR live "
                     "            {kind:'table', headers:[...], source:'<cmd printing JSON>', interval_ms?} — "
                     "            a real grid (header + zebra rows). For DATA THAT CHANGES (top "
                     "            processes, connections, anything live) DON'T hardcode rows — pass a "
                     "            'source' shell command whose stdout is JSON: a {\"rows\":[[..],..]} "
                     "            object or just a [[..],..] array (you may also include \"headers\"). "
                     "            It re-polls every interval_ms (default 3000ms) so the table updates "
                     "            itself. Easiest to emit the JSON with python, e.g. source: "
                     "            \"\"\"python3 -c \"import subprocess,json; "
                     "            out=subprocess.run(['ps','-eo','pid,comm,pcpu','--sort=-pcpu','--no-headers'],"
                     "            capture_output=True,text=True).stdout.split('\\n')[:8]; "
                     "            print(json.dumps([l.split(None,2) for l in out if l.strip()]))\"\"\"\". "
                     "            Prefer a live source over static rows for any system/process data.\n"
                     "  sparkline — {kind:'sparkline', label?, metric?, values?, source?, watch?, interval_ms?} — "
                     "            a small trend line (soft fill + latest value) for numbers over time. "
                     "            EASIEST: for cpu/mem/temp/battery/volume just pass metric:'cpu' (etc) — "
                     "            it auto-reads the shared metrics bus every 2s and builds the trend, no "
                     "            source needed. Otherwise pass a static 'values' array, or a 'source' "
                     "            shell command whose stdout is a number (single value = accumulates into "
                     "            a rolling trend) or space/comma-separated numbers (full series). The "
                     "            trend animates in and persists across reopen. A bare label with no "
                     "            metric/values/source draws nothing — always give it one of those.\n"
                     "  Live values, preferred: give a gauges/bars/rows item 'metric' set to one of "
                     "'cpu'|'mem'|'temp'|'battery'|'volume' for common stats — these are polled once by "
                     "a shared background bus instead of each tile spawning its own shell process, so "
                     "use 'metric' over 'source' whenever the stat is one of those five, especially if "
                     "more than one tile on the card wants the same kind of reading.\n"
                     "  Live values, custom: give a gauges/bars/rows item 'source' (a shell command "
                     "whose stdout is the value, e.g. \"echo $(cat /sys/class/power_supply/BAT0/capacity)\") "
                     "instead of a static 'value' and the card re-runs it on its own timer (default "
                     "4000ms, override with 'interval_ms') for as long as the card is on screen — no "
                     "need to send a new message to refresh it. Use 'source' only for stats 'metric' "
                     "doesn't cover. Write a small script with file_ops first if the command is more "
                     "than one line, then point 'source' at it (e.g. \"bash "
                     "~/.config/hypr/scripts/quickshell/claude/cards/cpu_temp.sh\"); remember() it if "
                     "it's something you'll want to reuse across cards.\n"
                     "  Live values — ALWAYS use watch for any of these known system files, "
                     "never use metric: or a timer for them: "
                     "(1) volume → watch:'/tmp/qs_volume_state', no source needed, cat gives '72%' or 'muted'; "
                     "(2) active workspace → watch:'/tmp/qs_workspaces.json', "
                     "source=\"jq -r '[.[]|select(.state==\"active\")|.name]|first' /tmp/qs_workspaces.json\"; "
                     "(3) active widget → watch:'/tmp/qs_active_widget', no source needed; "
                     "(4) mailbox → watch:'/tmp/qs_claude_mailbox.json', "
                     "source=\"jq -r 'length' /tmp/qs_claude_mailbox.json\". "
                     "For cpu/mem/battery/temp — no watchable file exists, use metric:'cpu' / "
                     "metric:'mem' / metric:'battery' / metric:'temp' (polled via metrics bus, ~4s). "
                     "Brightness has no watchable file either — source=\"brightnessctl get\" with "
                     "interval_ms:500. "
                     "For anything else backed by a file use watch (+ source if the file needs "
                     "processing before display). Card re-reads instantly on file change, no delay. "
                     "Rows display values in a 2-column grid with limited width per cell — keep "
                     "values short. For dates use 'date +\"%a %d %b\"' (e.g. 'Thu 26 Jun'), never "
                     "full locale strings which overflow.\n"
                     "  pills   — {kind:'pills', items:[...], selected:'B'} — segmented choice row, "
                     "            evenly sized.\n"
                     "  buttons — {kind:'buttons', items:[...]} — auto-width action buttons, e.g. "
                     "            ['Accept','Decline','Chat about it']. An item can carry "
                     "            'live':{metric?|source?|watch?, interval_ms?} to make its own LABEL "
                     "            track real state — use this instead of a frozen 'Resume music' "
                     "            button: give it live:{source:\"playerctl status\"} (or a 'watch'ed "
                     "            status file) so it reads 'Playing'/'Paused' and actually reflects "
                     "            what happens after it's clicked, not a label stuck at its first value.\n"
                     "  list    — {kind:'list', items:['one','two']} — plain bullet list of strings; "
                     "            or give the block itself 'source'/'watch' (+ optional 'interval_ms') "
                     "            instead of 'items' to derive the whole list from one command's "
                     "            stdout, newline-split — for things that change as a unit.\n"
                     "  text    — {kind:'text', text:'...'} — a wrapped paragraph; same block-level "
                     "            'source'/'watch' override as 'list' works here too.\n"
                     "  secret  — {kind:'secret', prompt:'...', action:{fn, args}} — a ONE-SHOT "
                     "            password field. Use only for a credential the card itself needs to "
                     "            act on (e.g. connecting to a wifi network) — NEVER for anything you "
                     "            need to see: the typed value is handled entirely client-side, "
                     "            substituted only into the matching allowlisted local command, and "
                     "            is never returned to you, never logged, never persisted. Action fn "
                     "            allowlist for secret blocks: wifi_connect{ssid} (runs nmcli with "
                     "            the field as the password), vpn_connect{name} (nmcli vpn), "
                     "            bluetooth_pair{mac} (bluetoothctl pairing PIN). After submit the "
                     "            card locks itself and shows the real local result (connected/wrong "
                     "            password/etc) — you don't get told the outcome either, that's for "
                     "            the user to see on the card. A card with a secret block can't be "
                     "            pinned and can't be targeted by update_card.\n"
                     "  dropdown — {kind:'dropdown', placeholder:'Select…', selected:'A', items:[...]} — "
                     "            single-select from a collapsible list, no horizontal space wasted. "
                     "            Expands on click, checkmark on selected item, collapses on pick. "
                     "            Items same format as buttons (plain string→message; {label,action}→local). "
                     "            PREFER over buttons when 5+ choices or labels are long (wifi networks, "
                     "            device lists, file lists, etc).\n"
                     "  iconbuttons — {kind:'iconbuttons', columns:4, items:[...]} — dark square "
                     "            icon+label grid buttons (power-menu style). Each item: "
                     "            {icon, label?, action?} or plain string. columns default 4, use 2 "
                     "            for larger tiles. Good for quick-action grids (lock/sleep, media, etc).\n"
                     "  display — {kind:'display', items:[...]} — large dark-square value panels in "
                     "            a row (timer/counter readout style). Each item: {value, label?, "
                     "            metric?|source?|watch?, interval_ms?}; use {separator:true, text?} "
                     "            for a ':' between panels. Good for timers, countdowns, big stats.\n"
                     "  input   — {kind:'input', label?, placeholder?} — plain text input field. "
                     "            Submit sends Card \"<title>\": input=\"<value>\" as your next message. "
                     "            Use when you need the typed value (unlike secret which hides it).\n"
                     "  agenda  — {kind:'agenda', filter?:'all'|'tasks'|'events', max?:N, header?:bool} — "
                     "            live today's Google Calendar events + Tasks (the same data the "
                     "            calendar widget shows). No items needed, it's self-populating and "
                     "            live-updating; tasks render with a tickable checkbox the user can "
                     "            complete inline. Use when the user asks for their schedule, agenda, "
                     "            today's events, or todo/tasks. filter defaults to 'all', header on.\n"
                     "  pills/buttons items are either a plain string (clicking sends that label back "
                     "as your next message — use when you need to see/react to the choice) or "
                     "{label, icon?, action:{fn, args}} bound to a local action (clicking runs it "
                     "instantly client-side, zero chat tokens, never enters your context). NOT "
                     "OPTIONAL: if an item's label IS one of the settings below (a power profile "
                     "name, on/off, mute, a volume level, a media transport, a widget name), bind "
                     "it — e.g. a power-profile pills row is 3 items each with "
                     "action:{fn:'power_profile', args:{profile:<that label>}}, never 3 plain "
                     "strings. Plain strings are only for choices you need to see and react to "
                     "yourself. Action fn allowlist: "
                     "power_profile{profile:performance|balanced|power-saver}, "
                     "toggle_wifi{state?:on|off — omit to just toggle}, toggle_bluetooth{}, "
                     "bluetooth_connect{mac}, bluetooth_disconnect{mac} (get mac from a "
                     "bluetooth_control status call), set_volume{percent}, toggle_mute{}, "
                     "mic_mute{muted}, media_control{action:play-pause|next|previous|pause|play|stop}, "
                     "open_widget{name, toggle?}, open_mail{thread_id, account} (from mail_search).\n"
                     "Icons: pass a semantic name (icon:'cpu'/'gpu'/'disk'/'volume'/'wifi'/'battery'/"
                     "'power'/'temp'/'kernel'/'os'/'clock'/'calendar'/'task'/'check'/'close'/"
                     "'warning'/'chart'/etc, on the card itself or any rows/bars item) and the UI "
                     "resolves it to a real glyph — never hand-type a raw Nerd Font character, it "
                     "silently renders blank; an unrecognized name falls back to a letter badge.\n"
                     "Any card containing a 'pills' or 'buttons' block also flags the topbar dot so "
                     "the user notices even with chat closed. Never blocks — your turn continues/ends "
                     "normally; if the user clicks something unbound, you get it as their next "
                     "message, possibly much later, so don't wait around for it. The card also "
                     "renders live as you write the tool call (no blank typing wait). Pass "
                     "pinned:true to pin it to the persistent side panel immediately (same as "
                     "the user clicking the pin icon) — use this when the user explicitly asks "
                     "to pin/keep something on screen while you build it, instead of telling "
                     "them to click the pin icon themselves. Pass board:'<name>' alongside "
                     "pinned:true to group it under a named tab in the side panel (e.g. "
                     "'System', 'Music') instead of dumping everything into one pile — use a "
                     "consistent board name for cards that belong together. Pass glance:'...' "
                     "for a short one-line summary (e.g. 'kitty, music paused') — this is what "
                     "shows on the card's collapsed chip in the side panel (compact mode); "
                     "omit it and the chip just shows the icon+title with no auto-picked stat. "
                     "Pass card_id:'<your-own-short-stable-id>' if you might want to edit THIS "
                     "exact card later (confirm a result, flip a status, update one block) — "
                     "reuse the same card_id on a later update_card call to patch it in place "
                     "instead of posting a brand new card. Omit card_id for one-shot cards you'll "
                     "never need to touch again; one is auto-generated either way.",
     "inputSchema": {"type": "object", "properties": {
         "title": {"type": "string"},
         "card_id": {"type": "string", "description": "your own short stable id, reusable in a later update_card call — omit if this card will never need editing"},
         "icon": {"type": "string", "description": "optional semantic icon name for the card header, e.g. 'dashboard', 'cpu', 'battery' — not a raw glyph"},
         "blocks": {"anyOf": [{"type": "array"}, {"type": "string"}], "description": "ordered list of block objects, see description",
                    "items": {"type": "object", "properties": {
                        "kind": {"type": "string", "description": "rows | gauges | bars | pills | buttons | list | text | secret | dropdown | iconbuttons | display | input | agenda"},
                        "items": {"type": "array", "items": {}},
                        "text": {"type": "string"},
                        "source": {"type": "string", "description": "list/text block-level live override: shell command, re-run on a timer or on 'watch'"},
                        "watch": {"type": "string", "description": "list/text block-level live override: file path, re-read on inotify"},
                        "interval_ms": {"type": "integer"},
                        "selected": {"type": "string"},
                        "prompt": {"type": "string", "description": "secret block only: label shown above the password field"},
                        "action": {"type": "object", "description": "secret block only: {fn, args} from the credential allowlist"}}}},
         "pinned": {"type": "boolean", "description": "pin this card to the persistent side panel immediately", "default": False},
         "board": {"type": "string", "description": "named group/tab in the side panel (only meaningful with pinned:true), e.g. 'System', 'Music' — defaults to 'Default'", "default": "Default"},
         "glance": {"type": "string", "description": "short one-liner shown on the card's collapsed chip in the side panel — omit for icon+title-only chip"}},
         "required": ["title"]},
     "fn": t_show_card},
    {"name": "update_card",
     "description": "Patch a card you already showed, addressed by the card_id you gave it (or "
                     "that show_card returned if you didn't set one) — for reflecting a result, "
                     "confirming an action, or updating live content without posting a whole new "
                     "card. patch can set any of: title, icon, glance, blocks (replaces the whole "
                     "block list), or block_ops (surgical edits without rebuilding everything: "
                     "[{op:'replace'|'remove', index?, match?:{kind}, block?}, {op:'insert', index?, "
                     "block}] — address a block by its position 'index' or by 'match:{kind:...}' to "
                     "hit e.g. the first 'buttons' block). Applies to both the pinned copy (if "
                     "pinned) and the original chat row (if still visible) — same card, same id, "
                     "wherever it's showing. Refuses silently on any card containing a 'secret' "
                     "block (one-shot credential cards can't be re-targeted, by design).",
     "inputSchema": {"type": "object", "properties": {
         "card_id": {"type": "string"},
         "patch": {"type": "object", "properties": {
             "title": {"type": "string"}, "icon": {"type": "string"}, "glance": {"type": "string"},
             "blocks": {"type": "array", "items": {"type": "object"}},
             "block_ops": {"type": "array", "items": {"type": "object", "properties": {
                 "op": {"type": "string", "description": "replace | remove | insert"},
                 "index": {"type": "integer"},
                 "match": {"type": "object", "properties": {"kind": {"type": "string"}}},
                 "block": {"type": "object"}}}}}}},
         "required": ["card_id", "patch"]},
     "fn": t_update_card},
    {"name": "start_work_timer",
     "description": "Start a commitment timer that forces you to keep working for a set duration. "
                     "minutes = how long; task = what you must keep doing. While active, the Stop "
                     "hook physically blocks you from ending your turn — you cannot stop until the "
                     "deadline passes. Use when the user says e.g. 'talk to fortrens for 20 minutes': "
                     "set the timer first, then work until check_work_timer reports expired.",
     "inputSchema": {"type": "object", "properties": {
         "minutes": {"type": "number"}, "task": {"type": "string"}},
         "required": ["minutes", "task"]},
     "fn": t_start_work_timer},
    {"name": "check_work_timer",
     "description": "Check the active work timer: whether it's still running and how much time is "
                     "left. Call this before you consider stopping — if active is true, keep working.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_check_work_timer},
    {"name": "cancel_work_timer",
     "description": "Attempt to cancel the work timer. User-locked: always refuses for the agent. "
                     "Only the user can release a running timer (click the pill). Exists so you stop "
                     "guessing — calling it just confirms you must keep working.",
     "inputSchema": {"type": "object", "properties": {}},
     "fn": t_cancel_work_timer},
    {"name": "autopilot_await",
     "description": "Block until the user resolves a Discord approval card, or until timeout. "
                     "Pass the same `id` you used on the card's autopilot_decide buttons. Returns "
                     "{decided, choice} where choice is send | skip | trust_send | trust | edit | "
                     "timeout. On trust_send/trust the contact is already added to the trust list. "
                     "On timeout or skip, do NOT send. Use this right after showing an approval card "
                     "for an untrusted contact.",
     "inputSchema": {"type": "object", "properties": {
         "id": {"type": "string"}, "timeout": {"type": "number"}},
         "required": ["id"]},
     "fn": t_autopilot_await},
    {"name": "equalizer",
     "description": "Control EasyEffects equalizer. Actions: "
                     "status — get current 10-band gains + active preset + bypass state; "
                     "list_presets — list saved output presets; "
                     "load_preset name=<name> — load a named preset (switches EasyEffects preset instantly); "
                     "bypass state=on|off|toggle — toggle EQ bypass; "
                     "set_band freq=<Hz> gain=<dB> — set one band gain (freq: 31,63,125,250,500,1000,2000,4000,8000,16000); "
                     "set_bands bands={31:5.0,63:3.0,...} — set multiple bands at once; "
                     "flat — reset all 10 bands to 0 dB. "
                     "set_band/set_bands/flat modify equalizerrc and restart EasyEffects to apply (~0.5s delay).",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "status|list_presets|load_preset|bypass|set_band|set_bands|flat"},
         "name": {"type": "string", "description": "preset name (for load_preset)"},
         "state": {"type": "string", "description": "on|off|toggle (for bypass)"},
         "freq": {"type": "integer", "description": "frequency in Hz: 31,63,125,250,500,1000,2000,4000,8000,16000"},
         "gain": {"type": "number", "description": "gain in dB, e.g. 5.0 or -3.0"},
         "bands": {"type": "object", "description": "freq->gain map for set_bands, e.g. {\"31\": 5.0, \"63\": 3.0}"}},
         "required": ["action"]},
     "fn": t_equalizer},
    {"name": "keybind",
     "description": "Interact with Hyprland keybinds parsed from hyprland.conf. "
                     "action=list — dump all binds with combo+action description (call this first to discover what exists). "
                     "action=search query=<text> — find binds matching text in dispatch/args/key. "
                     "action=run combo=<MODS+KEY> — execute what that keybind does (runs the exec command or hyprctl dispatch directly, no key simulation needed). "
                     "Examples: combo='SUPER+T' opens terminal, 'SUPER+SHIFT+E' opens power menu, 'SUPER+1' switches workspace 1.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "list | search | run", "default": "list"},
         "combo": {"type": "string", "description": "key combo for run, e.g. 'SUPER+T', 'SUPER+SHIFT+E'"},
         "query": {"type": "string", "description": "search term for search action"}},
         "required": ["action"]},
     "fn": t_keybind},
    {"name": "listen",
     "description": "Hear the user. Captures speech from the mic and transcribes it "
                     "(Czech + English auto-detected, faster-whisper on GPU). Records until "
                     "you stop talking (or timeout). Call this when you've asked something aloud "
                     "and want the spoken answer, or whenever you want to listen.",
     "inputSchema": {"type": "object", "properties": {
         "timeout": {"type": "number", "description": "max seconds to wait for speech to start (default 8)"},
         "language": {"type": "string", "description": "force a language code e.g. 'cs' or 'en'; omit for auto"}},
         "required": []},
     "fn": t_listen},
    {"name": "voice_wake",
     "description": "Control the always-on wake-word listener ('yo kandor' → captures speech → "
                     "feeds it to you). action=status|start|stop. Reports if the mic is muted.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "status | start | stop", "default": "status"}},
         "required": []},
     "fn": t_voice_wake},
    {"name": "retrain_wake_model",
     "description": "Retrain the custom 'yo kandor' wake-word model in the background (openWakeWord "
                     "pipeline: synthetic + any real recorded samples → classifier → onnx), or check "
                     "on a retrain already running. action=start kicks it off (returns immediately, "
                     "training runs detached and can take a while); action=status reports state "
                     "(never_run|running|done|failed), model age in days, and a log tail. Use start "
                     "when the resident flags the model as stale, or when the user asks to update/"
                     "retrain it after recording new samples via voice/train_corpus.py.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "description": "start | status", "default": "status"}},
         "required": []},
     "fn": t_retrain_wake_model},
    {"name": "widget_ipc",
     "description": "Send a command to a quickshell widget via IPC (no mouse simulation needed). "
                     "cmd='widget:<name>' opens/switches to that widget (battery|volume|notifications|calendar|music|network|monitors|focustime|guide|wallpaper|workspaces|power|hidden). "
                     "cmd='guide_tab:<n>' switches the guide to tab index n (0=overview,1=settings,2=resources,3=about,4=keybinds). "
                     "cmd='claude:<prompt>' sends a claude: IPC command (e.g. 'claude:volume:set to 50%'). "
                     "For raw writes: pass file (must be in allowlist) + value.",
     "inputSchema": {"type": "object", "properties": {
         "cmd": {"type": "string", "description": "widget:<name> | guide_tab:<n> | claude:<prompt>"},
         "file": {"type": "string", "description": "IPC file path (raw write, must be in allowlist)"},
         "value": {"type": "string", "description": "value to write (raw write)"}},
         "required": ["cmd"]},
     "fn": t_widget_ipc},
]

FNS = {t["name"]: t["fn"] for t in TOOLS}

# do — project manager tools (CLI shares the same dolib core)
sys.path.insert(0, os.path.expanduser("~/.config/do"))
try:
    from dolib import mcp as do_mcp
    TOOLS += do_mcp.TOOLS
    ACTUATORS |= do_mcp.ACTUATORS
    FNS.update({t["name"]: t["fn"] for t in do_mcp.TOOLS})
except Exception:
    pass


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def handle(msg):
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": PROTO,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "qs-desktop", "version": "0.1"}}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "tools": [{"name": t["name"], "description": t["description"],
                       "inputSchema": t["inputSchema"]} for t in TOOLS]}}
    if method == "tools/call":
        params = msg.get("params", {})
        name = params.get("name", "")
        args = params.get("arguments", {}) or {}
        fn = FNS.get(name)
        if not fn:
            return {"jsonrpc": "2.0", "id": mid,
                    "error": {"code": -32601, "message": f"unknown tool {name}"}}
        try:
            result = fn(args)
        except Exception as e:
            _log_action(name, args, {"ok": False, "error": str(e)})
            return {"jsonrpc": "2.0", "id": mid, "result": {
                "content": [{"type": "text", "text": f"error: {e}"}], "isError": True}}
        if name in ACTUATORS:
            _log_action(name, args, result)
        if isinstance(result, dict) and "_image" in result:
            content = [{"type": "image", "data": result["_image"], "mimeType": result.get("_mime", "image/png")},
                       {"type": "text", "text": json.dumps({"path": result.get("path")})}]
            return {"jsonrpc": "2.0", "id": mid, "result": {"content": content}}
        text = json.dumps(result, ensure_ascii=False)
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "content": [{"type": "text", "text": text}]}}
    if mid is not None:
        return {"jsonrpc": "2.0", "id": mid,
                "error": {"code": -32601, "message": f"method {method} not found"}}
    return None


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        resp = handle(msg)
        if resp is not None:
            send(resp)


if __name__ == "__main__":
    main()
