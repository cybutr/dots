import os, json, subprocess, time

CAPS_FILE = "/tmp/qs_agent_caps.json"
APPROVE_SCRIPT = os.path.expanduser("~/.config/hypr/scripts/quickshell/claude/approve_cap.sh")

CAPS = ("screenshot", "window_control", "input_control", "file_ops",
        "clipboard_control", "process_control")


def _load():
    try:
        with open(CAPS_FILE) as f:
            return json.load(f)
    except Exception:
        return {"approved": []}


def approved(name):
    return name in _load().get("approved", [])


def unattended():
    return os.environ.get("QS_AGENT_UNATTENDED", "") == "1"


def request(name, reason=""):
    """Gate an actuator capability for unattended (resident-spawned) runs.
    Interactive AUTO chat is already user-supervised, so it's never gated here.
    Returns True if the action may proceed."""
    if not unattended() or approved(name):
        return True
    body = f"Claude wants to use '{name}'" + (f" — {reason}" if reason else "") + \
        f". Approve: bash {APPROVE_SCRIPT} {name}"
    subprocess.run(["notify-send", "-a", "Claude", "-u", "critical", "Needs approval", body],
                   check=False)
    try:
        with open("/tmp/qs_resident_suggestion", "w") as f:
            f.write(json.dumps({
                "key": f"cap_{name}", "msg": body, "urgency": "critical",
                "ts": int(time.time()), "action_label": "", "action_cmd": "",
            }))
    except OSError:
        pass
    return False
