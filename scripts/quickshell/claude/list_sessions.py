#!/usr/bin/env python3
"""History/resume list for ClaudeAsk.qml. Reads real Claude Code project
transcripts directly (~/.claude/projects/<escaped-cwd>/*.jsonl) instead of
keeping a parallel index — that's the ground truth `claude --resume` itself
reads from, so this can't drift out of sync with it.

Usage: list_sessions.py [cwd]   (defaults to $HOME, matching agent.py's own
default workdir when the ask widget doesn't set one)
Prints a JSON array of {id, ts, title}, newest first, capped at 20.
"""
import sys, os, json, glob

HOME = os.path.expanduser("~")


def escape_cwd(cwd):
    return cwd.replace("/", "-")


def first_user_text(path):
    try:
        with open(path, "r", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if o.get("type") != "user":
                    continue
                msg = o.get("message") or {}
                content = msg.get("content")
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = " ".join(
                        b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text"
                    )
                else:
                    continue
                # agent.py joins any auto-injected context (focused app,
                # clipboard, etc) with the real typed message via this exact
                # separator — strip it off so the title is what the user
                # actually asked, not the boilerplate context dump.
                sep = "\n\n---\n\n"
                if sep in text:
                    text = text.rsplit(sep, 1)[-1]
                text = text.strip()
                if text:
                    return text
    except OSError:
        pass
    return ""


def main():
    cwd = sys.argv[1] if len(sys.argv) > 1 else HOME
    cwd = os.path.expanduser(cwd.strip()) if cwd.strip() else HOME
    proj_dir = os.path.join(HOME, ".claude", "projects", escape_cwd(cwd))
    out = []
    for path in glob.glob(os.path.join(proj_dir, "*.jsonl")):
        sid = os.path.splitext(os.path.basename(path))[0]
        try:
            mtime = int(os.path.getmtime(path))
        except OSError:
            continue
        title = first_user_text(path)
        if not title:
            continue  # empty/aborted session, nothing worth resuming
        out.append({"id": sid, "ts": mtime, "title": title[:120]})
    out.sort(key=lambda e: e["ts"], reverse=True)
    print(json.dumps(out[:20]))


if __name__ == "__main__":
    main()
