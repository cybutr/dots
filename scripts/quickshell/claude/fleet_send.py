#!/usr/bin/env python3
"""Send files from this laptop to another fleet device through the hub's relay.

  fleet_send.py [FILE ...] [--to phone] [--quiet]
  fleet_send.py --peek PATH        JSON about PATH, for the palette preview

No FILE opens a file picker. Paths may be quoted, ~-relative or file:// URIs.
The phone's Fleet app shows them under "From laptop" until saved or the hub
expires them (48 h). Uses the same hub address and laptop token as
fleet_watch.py.
"""
import hashlib
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import quote, unquote, urlsplit

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet_watch  # noqa: E402

LIMIT_CACHE = "/tmp/qs_fleet_relay.json"
DEFAULT_MAX = 25 * 1024 * 1024
LIMIT_TTL = 6 * 3600
PROGRESS_FROM = 2 * 1024 * 1024
ICON = "document-send"


def resolve(arg):
    p = (arg or "").strip().strip("'\"")
    if p.startswith("file://"):
        p = unquote(urlsplit(p).path)
    p = os.path.expanduser(p)
    return p if os.path.isabs(p) else os.path.join(os.path.expanduser("~"), p)


def cached_max():
    try:
        with open(LIMIT_CACHE) as f:
            d = json.load(f)
        return int(d["max_bytes"]), time.time() - d.get("ts", 0) < LIMIT_TTL
    except (OSError, ValueError, KeyError, TypeError):
        return DEFAULT_MAX, False


def fetch_max(url, token):
    cap, fresh = cached_max()
    if fresh:
        return cap
    try:
        cap = int(fleet_watch._http("GET", f"{url}/relay/{fleet_watch.DEVICE}", token).get("max_bytes") or cap)
        tmp = LIMIT_CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"max_bytes": cap, "ts": int(time.time())}, f)
        os.replace(tmp, LIMIT_CACHE)
    except Exception:
        pass
    return cap


def peek(arg):
    cap = cached_max()[0]
    out = {"arg": arg or "", "max": cap, "maxHuman": fleet_watch._human(cap)}
    if not (arg or "").strip():
        return {**out, "state": "empty"}
    path = resolve(arg)
    name = os.path.basename(path.rstrip("/")) or path
    out.update(path=path, name=name)
    if os.path.isdir(path):
        return {**out, "state": "dir"}
    if not os.path.isfile(path):
        return {**out, "state": "missing"}
    size = os.path.getsize(path)
    mime = mimetypes.guess_type(name)[0] or ""
    return {**out, "state": "big" if size > cap else "empty-file" if size == 0 else "ok",
            "size": size, "human": fleet_watch._human(size), "mime": mime,
            "image": mime in ("image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp")}


def pick():
    r = subprocess.run(["zenity", "--file-selection", "--multiple", "--separator=\n",
                        "--title=Send to the phone", f"--filename={os.path.expanduser('~')}/"],
                       capture_output=True, text=True)
    return [ln for ln in r.stdout.splitlines() if ln.strip()]


class Progress:
    def __init__(self, f, size, tick):
        self.f, self.size, self.sent, self.tick, self.last = f, size, 0, tick, time.time()

    def read(self, n=-1):
        chunk = self.f.read(n)
        self.sent += len(chunk)
        now = time.time()
        if now - self.last >= 1 and self.sent < self.size:
            self.last = now
            self.tick(self.sent)
        return chunk


def upload(url, token, path, to, tick):
    size = os.path.getsize(path)
    name = os.path.basename(path)
    with open(path, "rb") as f:
        body = Progress(f, size, tick) if size >= PROGRESS_FROM else f
        req = urllib.request.Request(f"{url}/relay/{to}", data=body, method="POST", headers={
            "Authorization": "Bearer " + token,
            "Content-Type": mimetypes.guess_type(name)[0] or "application/octet-stream",
            "Content-Length": str(size),
            "X-Filename": quote(name),
        })
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            try:
                detail = json.loads(e.read()).get("detail")
            except Exception:
                detail = None
            return False, detail or f"hub said {e.code}"
        except OSError as e:
            return False, type(e).__name__
    return True, ""


def send_all(paths, to="phone", card=lambda *a, **k: None):
    """Returns [(name, ok, message)]."""
    cfg = fleet_watch.env()
    token = cfg.get("FLEET_TOKEN_LAPTOP")
    up, peer = fleet_watch.tailnet()
    url = fleet_watch.hub_url(peer, cfg)
    if not up or not url:
        return [(os.path.basename(p), False, "the hub isn't reachable (tailnet down?)") for p in paths]
    if not token:
        return [(os.path.basename(p), False, "no laptop token in " + fleet_watch.TOKENS_ENV) for p in paths]
    cap = fetch_max(url, token)
    out = []
    for i, path in enumerate(paths):
        name = os.path.basename(path.rstrip("/")) or path
        if os.path.isdir(path):
            out.append((name, False, "that's a folder; zip it first"))
            continue
        if not os.path.isfile(path):
            out.append((name, False, "no such file"))
            continue
        size = os.path.getsize(path)
        human = fleet_watch._human(size)
        if size == 0:
            out.append((name, False, "the file is empty"))
            continue
        if size > cap:
            out.append((name, False, f"{human}; the hub takes up to {fleet_watch._human(cap)}"))
            continue
        step = f" ({i + 1}/{len(paths)})" if len(paths) > 1 else ""
        tick = lambda sent: card("Sending to " + to + step,  # noqa: E731
                                 f"{name} · {fleet_watch._human(sent)} of {human} · {sent * 100 // size}%", "low", 0)
        if size >= PROGRESS_FROM:
            tick(0)
        ok, err = upload(url, token, path, to, tick)
        out.append((name, ok, human if ok else err))
    return out


def main(argv):
    if "--peek" in argv:
        i = argv.index("--peek")
        print(json.dumps(peek(argv[i + 1] if i + 1 < len(argv) else "")))
        return 0
    to = "phone"
    rest = []
    skip = False
    for i, a in enumerate(argv[1:], 1):
        if skip:
            skip = False
        elif a == "--to":
            to = argv[i + 1] if i + 1 < len(argv) else to
            skip = True
        elif not a.startswith("--"):
            rest.append(a)
    quiet = "--quiet" in argv
    paths = [resolve(a) for a in rest if a.strip()] or pick()
    if not paths:
        return 1
    card_id = "fleet-send-" + hashlib.sha1("\0".join(paths).encode()).hexdigest()[:8]

    def card(title, body, urgency="low", hold=None):
        if quiet:
            return
        try:
            import resident_card
            resident_card.emit(title, body, ICON, urgency, hold, [], "fleet", card_id)
        except Exception:
            pass

    results = send_all(paths, to, card)
    sent = [r for r in results if r[1]]
    failed = [r for r in results if not r[1]]
    lines = [f"{n} · {m}" for n, _, m in sent] + [f"{n}: {m}" for n, _, m in failed]
    if not failed:
        title = "Sent to " + to
    elif not sent:
        title = "Couldn't send to " + to
    else:
        title = f"Sent {len(sent)} of {len(results)} to {to}"
    card(title, "\n".join(lines), "normal" if failed else "low", None if failed else 6)
    print("\n".join(lines), file=sys.stderr if failed else sys.stdout)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
