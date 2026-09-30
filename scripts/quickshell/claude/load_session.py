#!/usr/bin/env python3
"""Reconstructs a simplified {role,text} transcript for one past session, for
the ClaudeAsk history/resume picker to repopulate chatModel with — same idea
as list_sessions.py, reading the real project jsonl rather than a parallel
store. Tool calls/results are skipped; this is a readable recap, not a full
replay (the live daemon continues the ACTUAL resumed session server-side
regardless of what's shown here).

Usage: load_session.py <cwd> <session_id>
Prints a JSON array of {role: "user"|"text", text}.
"""
import sys, os, json

HOME = os.path.expanduser("~")


def escape_cwd(cwd):
    return cwd.replace("/", "-")


def extract_text(content):
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        return " ".join(
            b.get("text", "") for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
    return ""


def main():
    if len(sys.argv) < 3:
        print("[]")
        return
    cwd = sys.argv[1].strip() or HOME
    cwd = os.path.expanduser(cwd)
    sid = sys.argv[2]
    proj_dir = os.path.join(HOME, ".claude", "projects", escape_cwd(cwd))
    path = os.path.join(proj_dir, sid + ".jsonl")
    if not os.path.isfile(path):
        print("[]")
        return

    out = []
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
                t = o.get("type")
                if t not in ("user", "assistant"):
                    continue
                msg = o.get("message") or {}
                text = extract_text(msg.get("content"))
                if not text:
                    continue
                if t == "user":
                    sep = "\n\n---\n\n"
                    if sep in text:
                        text = text.rsplit(sep, 1)[-1].strip()
                out.append({"role": "user" if t == "user" else "text", "text": text})
    except OSError:
        pass
    print(json.dumps(out))


if __name__ == "__main__":
    main()
