#!/usr/bin/env python3
"""#17 project-context-dock.
Watches focus.project in /tmp/qs_context.json (inotify on the file, which
context_daemon.sh already rewrites regularly). On a real project change,
debounced 10s, fires a full-agent turn that pulls git status/branches/TODOs
and updates a single pinned 'Project' board card in place (card_id
'project_dock') via show_card/update_card."""
import os, sys, json, subprocess, time, threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from claude_resident import load, spawn_full_agent
except Exception:
    def load(path, default):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            return default

    CLAUDE_BIN = "claude"
    AGENT_LOG = "/tmp/qs_resident_agent.log"

    def spawn_full_agent(prompt, tag="task"):
        def run():
            try:
                with open(AGENT_LOG, "a") as f:
                    subprocess.run([CLAUDE_BIN, "--no-continue", "-p", prompt],
                                    stdout=f, stderr=f, timeout=180, check=False)
            except Exception:
                pass
        threading.Thread(target=run, daemon=True).start()

PID = "/tmp/qs_project_watch.pid"
CTX = "/tmp/qs_context.json"
DEBOUNCE = 10
PINNED_FILE = "/tmp/qs_pinned_cards.json"
CARD_ID = "project_dock"


def _current_project():
    ctx = load(CTX, {})
    focus = ctx.get("focus", {}) if isinstance(ctx, dict) else {}
    return focus.get("project", ""), focus.get("cwd", "")


def _card_exists():
    pins = load(PINNED_FILE, [])
    for p in pins if isinstance(pins, list) else []:
        spec = p.get("spec", {}) if isinstance(p, dict) else {}
        if spec.get("card_id") == CARD_ID:
            return True
    return False


def build_dock(project, cwd):
    verb = "update_card (card_id 'project_dock')" if _card_exists() else \
           "show_card (card_id 'project_dock', pinned:true, board:'Project')"
    subprocess.run  # noqa: keep import used
    prompt = (
        f"I just switched to working on project '{project}' (cwd: {cwd or 'unknown'}). "
        f"cd there and run: git status --short, git branch --show-current, git log "
        f"--oneline -5, and grep -rn 'TODO' in tracked files (limit output, top ~5 hits) — "
        f"use file_ops/window_control style shell access as needed, or just read files "
        f"directly if that's simpler for you. Then call {verb} — title '{project}', a rows "
        f"or text block with: current branch, short git status summary (clean / N changed "
        f"files), last commit, and up to 3 open TODOs found. Keep it tight, this is a "
        f"glanceable dock, not a report. If you can't access the project directory for any "
        f"reason, show a minimal card saying so instead of failing silently."
    )
    spawn_full_agent(prompt, tag=f"project_dock_{project}")


def main():
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))

    last_project, _ = _current_project()
    pending_project = None
    pending_since = 0

    proc = subprocess.Popen(["inotifywait", "-m", "-e", "close_write,create,moved_to", CTX],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    if proc.stdout is None:
        return

    while True:
        line = proc.stdout.readline()
        if not line:
            time.sleep(1)
            continue
        project, cwd = _current_project()
        if not project or project == last_project:
            continue
        now = time.time()
        if project != pending_project:
            pending_project = project
            pending_since = now
            continue
        if now - pending_since < DEBOUNCE:
            continue
        last_project = project
        pending_project = None
        build_dock(project, cwd)


if __name__ == "__main__":
    main()
