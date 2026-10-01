#!/usr/bin/env python3
import os, sys, json, time, uuid, argparse, subprocess

QUEUE = "/tmp/qs_stage.jsonl"
ACK = "/tmp/qs_stage_ack"
CTL = "/tmp/qs_stage_ctl"
QUEUE_MAX = 30
ACK_MAX = 200
KINDS = ("info", "step", "tip", "done", "warn", "error", "wait")
COMMANDS = ("say", "ack", "cancel", "pending", "clear", "collapse", "expand")
HERE = os.path.dirname(os.path.abspath(__file__))
WAIT_SH = os.path.join(HERE, "stage_wait.sh")
SETTINGS = os.path.expanduser("~/.config/hypr/settings.json")
BACKENDS = ("dock", "resident")
KIND_URGENCY = {"error": "high", "warn": "normal"}


def backend():
    try:
        with open(SETTINGS) as f:
            b = json.load(f).get("showcaseBackend", "dock")
    except (OSError, ValueError):
        b = "dock"
    return b if b in BACKENDS else "dock"


def _resident(entry, closed=None):
    sys.path.insert(0, HERE)
    import resident_card
    wait = entry.get("wait") and not closed
    actions = [{"label": "Continue", "cmd": f"python3 {os.path.abspath(__file__)} ack {entry['id']}"}] if wait else None
    title = entry.get("title") or entry.get("kind", "info").capitalize()
    body = entry.get("body", "")
    if closed:
        body = (body + f"\n\n[{closed}]").strip()
    hold = 0 if wait else (8 if closed else entry.get("hold"))
    resident_card.emit(title, body, entry.get("icon", ""), KIND_URGENCY.get(entry.get("kind"), "normal"),
                       hold, actions, source="stage", card_id=entry["id"])


def _read(path):
    try:
        with open(path) as f:
            return f.read().splitlines()
    except OSError:
        return []


def _entries():
    out = []
    for ln in _read(QUEUE):
        try:
            e = json.loads(ln)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("id"):
            out.append(e)
    return out


def _write_queue(entries):
    tmp = QUEUE + ".tmp"
    with open(tmp, "w") as f:
        f.write("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in entries[-QUEUE_MAX:]))
    os.replace(tmp, QUEUE)


def _acks():
    out = {}
    for ln in _read(ACK):
        parts = ln.split()
        if len(parts) >= 2:
            out[parts[0]] = parts[1]
    return out


def _ctl(op):
    tmp = CTL + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"op": op, "ts": time.time()}, f)
    os.replace(tmp, CTL)


def pending():
    acks = _acks()
    return [e["id"] for e in _entries() if e.get("wait") and e["id"] not in acks]


def ack(entry_id=None, state="ok"):
    ids = [entry_id] if entry_id else pending()[-1:]
    if not ids:
        return []
    stamp = int(time.time())
    lines = _read(ACK) + [f"{i} {state} {stamp}" for i in ids]
    with open(ACK, "w") as f:
        f.write("\n".join(lines[-ACK_MAX:]) + "\n")
    if state != "ok":
        for e in _entries():
            if e["id"] in ids and e.get("via") == "resident":
                _resident(e, "timed out" if state == "expired" else "skipped")
    return ids


def say(body="", title="", icon="", kind=None, wait=False, hold=None, entry_id=None, append=False, via=None):
    via = via if via in BACKENDS else backend()
    entries = _entries()
    rev = max([int(time.time() * 1000)] + [int(e.get("rev", 0)) + 1 for e in entries])
    current = next((e for e in entries if entry_id and e["id"] == entry_id), None)
    if current and append:
        current["body"] = current.get("body", "") + body
        if title:
            current["title"] = title
        if icon:
            current["icon"] = icon
        if kind:
            current["kind"] = kind
        if hold is not None:
            current["hold"] = hold
        current["rev"] = rev
        entries.remove(current)
        entries.append(current)
        _write_queue(entries)
        if current.get("via") == "resident":
            _resident(current)
        return current
    if wait:
        stale = pending()
        if stale:
            for i in stale:
                ack(i, "cancel")
        open(ACK, "a").close()
    entry = {
        "id": entry_id or uuid.uuid4().hex[:10],
        "rev": rev,
        "ts": int(time.time()),
        "title": title,
        "body": body,
        "icon": icon,
        "kind": kind if kind in KINDS else ("wait" if wait else "info"),
        "wait": bool(wait),
        "hold": hold,
        "via": via,
    }
    entries = [e for e in entries if e["id"] != entry["id"]] + [entry]
    _write_queue(entries)
    if via == "resident":
        _resident(entry)
    return entry


def clear():
    for i in pending():
        ack(i, "cancel")
    _write_queue([])


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] not in COMMANDS:
        argv = ["say"] + argv
    ap = argparse.ArgumentParser(prog="stage_say.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("say")
    s.add_argument("text", nargs="?", default="")
    s.add_argument("--title", default="")
    s.add_argument("--icon", default="")
    s.add_argument("--kind", choices=KINDS, default=None)
    s.add_argument("--wait", action="store_true")
    s.add_argument("--block", action="store_true")
    s.add_argument("--timeout", type=int, default=300)
    s.add_argument("--hold", type=int, default=None)
    s.add_argument("--id", default=None)
    s.add_argument("--append", action="store_true")
    s.add_argument("--backend", choices=BACKENDS, default=None)
    a_ack = sub.add_parser("ack")
    a_ack.add_argument("id", nargs="?", default=None)
    a_ack.add_argument("--state", choices=("ok", "cancel", "expired"), default="ok")
    a_cancel = sub.add_parser("cancel")
    a_cancel.add_argument("id", nargs="?", default=None)
    sub.add_parser("pending")
    sub.add_parser("clear")
    sub.add_parser("collapse")
    sub.add_parser("expand")
    a = ap.parse_args(argv)

    if a.cmd == "say":
        text = sys.stdin.read().rstrip("\n") if a.text == "-" else a.text
        if not text and not a.title:
            ap.error("say needs text or --title")
        wait = a.wait or a.block
        e = say(text, a.title, a.icon, a.kind, wait, a.hold, a.id, a.append, a.backend)
        print(e["id"], flush=True)
        if a.block:
            sys.exit(subprocess.call(["bash", WAIT_SH, e["id"], str(a.timeout)]))
    elif a.cmd == "ack":
        print("\n".join(ack(a.id, a.state)))
    elif a.cmd == "cancel":
        print("\n".join(ack(a.id, "cancel")))
    elif a.cmd == "pending":
        print("\n".join(pending()))
    elif a.cmd == "clear":
        clear()
    else:
        _ctl(a.cmd)


if __name__ == "__main__":
    main()
