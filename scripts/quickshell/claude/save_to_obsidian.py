#!/usr/bin/env python3
# Saves the desktop scratchpad's current text as a note in the Obsidian
# vault — smarter version: derives a real title from the note's own content
# instead of a bare timestamp, suggests which vault folder it probably
# belongs in (keyword match against existing folder names — this is a
# heuristic, not an LLM call, so it stays fast and works fully unattended),
# and confirms the save through the resident card queue + the cross-session
# Claude mailbox so any session (including one helping with schoolwork)
# can see what got saved and where.
#
# Tries the Local REST API plugin first (same server the `obsidian` MCP
# connector talks to, config/creds at ~/.config/obsidian-mcp/config.json)
# — only works while the Obsidian app is actually open. Since a vault is
# just a folder of markdown files, falls back to a direct file write when
# the API is unreachable, so saving works either way.
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import resident_card  # noqa: E402

CONFIG_PATH = os.path.expanduser("~/.config/obsidian-mcp/config.json")
VAULT_PATH = os.path.expanduser("~/obsidian/main")
DEFAULT_FOLDER = "Scratchpad"
MAILBOX = "/tmp/qs_claude_mailbox.json"
MAILBOX_MAX = 100

IGNORE_DIRS = {".obsidian", ".trash", ".git"}


def mailbox_post(to, msg, frm="scratchpad"):
    try:
        try:
            with open(MAILBOX) as f:
                msgs = json.load(f)
        except (OSError, ValueError):
            msgs = []
        msgs.append({"id": int(time.time() * 1000), "from": frm, "to": to, "msg": msg,
                     "ts": int(time.time()), "read": False})
        tmp = MAILBOX + ".tmp"
        with open(tmp, "w") as f:
            json.dump(msgs[-MAILBOX_MAX:], f)
        os.replace(tmp, MAILBOX)
    except OSError:
        pass


def list_folders():
    try:
        entries = os.listdir(VAULT_PATH)
    except OSError:
        return []
    return sorted(
        d for d in entries
        if d not in IGNORE_DIRS and not d.startswith(".")
        and os.path.isdir(os.path.join(VAULT_PATH, d))
    )


def suggest_folder(text, folders):
    """Keyword-match heuristic: score each existing folder name by how often
    it (or its individual words) shows up in the note text, case-insensitive.
    Picks the best match above a small threshold; otherwise the caller falls
    back to DEFAULT_FOLDER. Deliberately simple — no LLM call, has to run
    unattended from a QML button click in well under a second."""
    if not folders:
        return None
    low = text.lower()
    best, best_score = None, 0
    for folder in folders:
        words = [w for w in re.split(r"[\s_-]+", folder.lower()) if len(w) > 2]
        score = sum(low.count(w) for w in words)
        if folder.lower() in low:
            score += 3  # whole-name match is a much stronger signal than word overlap
        if score > best_score:
            best, best_score = folder, score
    return best if best_score > 0 else None


def derive_title(text):
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        line = re.sub(r"^#+\s*", "", line)          # markdown heading marker
        line = re.sub(r"^[-*+]\s*", "", line)        # list marker
        line = re.sub(r'[\\/:*?"<>|]', "", line)      # filesystem-unsafe chars
        line = line.strip()
        if line:
            return line[:60]
    return None


def do_list():
    folders = list_folders()
    text = sys.stdin.read() if not sys.stdin.isatty() else ""
    suggested = suggest_folder(text, folders) if text else None
    print(json.dumps({"folders": folders, "suggested": suggested or DEFAULT_FOLDER}))


def save_via_api(note_path, body):
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    base_url = cfg["baseUrl"].rstrip("/")
    api_key = cfg["apiKey"]
    url = f"{base_url}/vault/{urllib.parse.quote(note_path)}"
    req = urllib.request.Request(
        url, data=body.encode("utf-8"), method="PUT",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "text/markdown"},
    )
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(req, timeout=5, context=ctx) as resp:
        resp.read()


def save_direct(note_path, body):
    full_path = os.path.join(VAULT_PATH, note_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w") as f:
        f.write(body)


def unique_path(folder, title):
    base = f"{folder}/{title}"
    if not os.path.exists(os.path.join(VAULT_PATH, base + ".md")):
        return base + ".md"
    stamp = time.strftime("%Y-%m-%d %H%M")
    return f"{base} — {stamp}.md"


def save_note(text, folder=None, source="scratchpad", from_scratchpad=True):
    if not text.strip():
        return {"error": "empty note, nothing to save"}
    folder = folder or suggest_folder(text, list_folders()) or DEFAULT_FOLDER
    title = derive_title(text) or time.strftime("Scratchpad %Y-%m-%d %H%M")
    note_path = unique_path(folder, title)
    body = text if text.lstrip().startswith("#") else f"# {title}\n\n{text}\n"

    via = None
    try:
        save_via_api(note_path, body)
        via = "api"
    except Exception:
        try:
            save_direct(note_path, body)
            via = "direct"
        except OSError as e:
            return {"error": str(e)}

    import shlex
    vault_name = "main"
    obsidian_uri = "obsidian://open?vault=" + urllib.parse.quote(vault_name) + "&file=" + urllib.parse.quote(note_path[:-3])
    words = len(text.split())
    preview = " ".join(ln.strip() for ln in text.splitlines()
                       if ln.strip() and not ln.lstrip().startswith("#"))[:140]
    actions = [{"label": "Open note", "cmd": "xdg-open " + shlex.quote(obsidian_uri)}]
    if from_scratchpad:
        actions.append({"label": "Clear scratchpad", "cmd": "echo clear > /tmp/qs_scratchpad_cmd"})
    else:
        actions.append({"label": "Show scratchpad", "cmd": "echo show > /tmp/qs_scratchpad_cmd"})
    resident_card.emit(
        f"Saved to {folder}", f"{title}\n{words} words · {'Obsidian' if via == 'api' else 'vault file'}"
        + (f"\n{preview}" if preview else ""),
        "document-save", "low", 12, actions, source, card_id="obsidian-save",
        kind="note",
        data={"title": title, "folder": folder, "path": note_path, "uri": obsidian_uri,
              "words": words, "via": via, "preview": preview},
    )
    mailbox_post("me", f"Saved note '{title}' → {note_path} ({words} words, via {via})", frm=source)
    return {"ok": True, "path": note_path, "via": via, "folder": folder, "title": title}


def do_save(note_file, folder_arg):
    try:
        with open(note_file) as f:
            text = f.read()
    except OSError as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    r = save_note(text, folder_arg or DEFAULT_FOLDER)
    print(json.dumps(r))
    if not r.get("ok"):
        sys.exit(1)


def main():
    if "--list" in sys.argv:
        do_list()
        return
    args = [a for a in sys.argv[1:] if a != "--list"]
    note_file = args[0] if args else None
    folder_arg = None
    if "--folder" in args:
        i = args.index("--folder")
        folder_arg = args[i + 1] if i + 1 < len(args) else None
        args = [a for j, a in enumerate(args) if j not in (i, i + 1)]
        note_file = args[0] if args else note_file
    if not note_file:
        print(json.dumps({"error": "usage: save_to_obsidian.py <note_file> [--folder NAME] | --list"}))
        sys.exit(1)
    do_save(note_file, folder_arg)


if __name__ == "__main__":
    main()
