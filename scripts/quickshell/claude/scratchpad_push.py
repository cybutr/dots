#!/usr/bin/env python3
"""Push text into the desktop scratchpad (or straight into Obsidian) from any
process — a Claude chat session, the resident, a shell.
  scratchpad_push.py "text" [--heading H] [--open]
  scratchpad_push.py "text" --obsidian [FOLDER]
  echo text | scratchpad_push.py - [...]
Live scratchpad: appended via /tmp/qs_scratchpad_append (JSONL, watched by
ScratchpadHost.qml). Scratchpad not running: appended to its save file."""
import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import resident_card  # noqa: E402

SPOOL = "/tmp/qs_scratchpad_append"
SAVE_FILE = os.path.expanduser("~/.local/share/qs_scratchpad.txt")


def scratchpad_running():
    r = subprocess.run(["pgrep", "-f", "^quickshell -p .*ScratchpadHost\\.qml"], capture_output=True)
    return r.returncode == 0


def block(text, heading):
    text = text.strip("\n")
    return f"## {heading}\n\n{text}" if heading else text


def push(text, heading=None, open_=False, source="claude"):
    if not text.strip():
        return {"ok": False, "error": "empty text"}
    if scratchpad_running():
        with open(SPOOL, "a") as f:
            f.write(json.dumps({"text": text, "heading": heading or "", "open": open_,
                                "source": source}, ensure_ascii=False) + "\n")
        where = "live"
    else:
        try:
            with open(SAVE_FILE) as f:
                cur = f.read()
        except OSError:
            cur = ""
        sep = "" if not cur.strip() else ("\n" if cur.endswith("\n\n") else ("\n\n" if not cur.endswith("\n") else "\n"))
        os.makedirs(os.path.dirname(SAVE_FILE), exist_ok=True)
        with open(SAVE_FILE, "w") as f:
            f.write(cur + sep + block(text, heading) + "\n")
        where = "file"
    resident_card.osd("Added to scratchpad", "󰈙")
    return {"ok": True, "where": where}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text")
    ap.add_argument("--heading", default="")
    ap.add_argument("--open", action="store_true")
    ap.add_argument("--obsidian", nargs="?", const="", default=None)
    ap.add_argument("--source", default="claude")
    a = ap.parse_args()
    text = sys.stdin.read() if a.text == "-" else a.text
    if a.obsidian is not None:
        import save_to_obsidian
        r = save_to_obsidian.save_note(block(text, a.heading), a.obsidian or None,
                                       source=a.source, from_scratchpad=False)
    else:
        r = push(text, a.heading, a.open, a.source)
    print(json.dumps(r, ensure_ascii=False))
    sys.exit(0 if r.get("ok") else 1)


if __name__ == "__main__":
    main()
