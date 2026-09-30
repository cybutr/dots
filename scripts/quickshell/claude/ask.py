#!/usr/bin/env python3
import sys, os, subprocess, shutil

RS = "\x1e"

def find_claude():
    p = shutil.which("claude")
    if p:
        return p
    for c in [os.path.expanduser("~/.local/bin/claude"), "/usr/bin/claude", "/usr/local/bin/claude"]:
        if os.path.exists(c):
            return c
    return "claude"

SYSTEM = (
    "You are Claude, embedded in the user's Hyprland desktop as an ambient assistant. "
    "Answer tightly and directly — no preamble, no sign-off. Plain text, short. "
    "The user may give you ambient context about their focused window and clipboard; "
    "use it only if relevant to the question."
)

def get_key():
    k = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if k:
        return k
    for p in [os.path.expanduser("~/.config/anthropic/key"),
              os.path.expanduser("~/.config/anthropic/api_key")]:
        try:
            with open(p) as f:
                v = f.read().strip()
                if v:
                    return v
        except OSError:
            pass
    return ""

def emit(text):
    sys.stdout.write(text + RS)
    sys.stdout.flush()

def main():
    prompt = sys.argv[1] if len(sys.argv) > 1 else ""
    context = sys.argv[2] if len(sys.argv) > 2 else ""
    if prompt.strip() == "":
        return

    full = (context + "\n\n---\n\n" + prompt) if context else prompt

    env = os.environ.copy()
    key = get_key()
    if key:
        env["ANTHROPIC_API_KEY"] = key
    env["ANTHROPIC_BASE_URL"] = os.environ.get("ANTHROPIC_BASE_URL", "https://cc.freemodel.dev")
    env["CLAUDE_RICE_IGNORE"] = "1"

    cmd = [find_claude(), "-p", full, "--append-system-prompt", SYSTEM]
    model = os.environ.get("ANTHROPIC_MODEL", "").strip()
    if model:
        cmd += ["--model", model]

    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, env=env, cwd=os.path.expanduser("~"))
    except FileNotFoundError:
        emit("⚠ claude CLI not found on PATH")
        return

    got = False
    if proc.stdout:
        for line in proc.stdout:
            got = True
            emit(line)
    proc.wait()
    if not got:
        err = (proc.stderr.read() if proc.stderr else "" or "").strip()
        emit("⚠ " + (err[:400] if err else "no response"))

if __name__ == "__main__":
    main()
