#!/usr/bin/env python3
"""Send a file from this laptop to another fleet device through the hub's relay.

  fleet_send.py FILE [--to phone]

The phone's Fleet app shows it under "From laptop" until it's saved or the
hub expires it (48 h). Uses the same hub address and laptop token as
fleet_watch.py.
"""
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request
from urllib.parse import quote

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet_watch  # noqa: E402


def send(path, to="phone"):
    cfg = fleet_watch.env()
    token = cfg.get("FLEET_TOKEN_LAPTOP")
    up, peer = fleet_watch.tailnet()
    url = fleet_watch.hub_url(peer, cfg)
    if not up or not url:
        return False, "the hub isn't reachable (tailnet down?)"
    if not token:
        return False, "no laptop token in " + fleet_watch.TOKENS_ENV
    size = os.path.getsize(path)
    name = os.path.basename(path)
    with open(path, "rb") as f:
        req = urllib.request.Request(f"{url}/relay/{to}", data=f, method="POST", headers={
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
    return True, f"{name} · {fleet_watch._human(size)}"


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    to = "phone"
    if "--to" in argv:
        i = argv.index("--to")
        to = argv[i + 1] if i + 1 < len(argv) else to
        args = [a for a in args if a != to]
    if len(args) != 1 or not os.path.isfile(os.path.expanduser(args[0])):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path = os.path.abspath(os.path.expanduser(args[0]))
    ok, msg = send(path, to)
    try:
        import resident_card
        resident_card.emit("Sent to " + to if ok else "Couldn't send to " + to, msg,
                           "document-send", "low" if ok else "normal", 6, [], "fleet")
    except Exception:
        pass
    print(msg, file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
