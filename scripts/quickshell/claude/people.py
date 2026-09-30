#!/usr/bin/env python3
"""people — list/search/show saved Discord contact profiles.

Usage:
  people                 list all saved profiles (id + header)
  people list            same
  people search <query>  search profiles (username/id/body)
  people show <id|name>  print a full profile
"""
import os
import sys

PEOPLE_DIR = os.path.expanduser("~/.config/discord-autopilot/people")


def _profiles():
    if not os.path.isdir(PEOPLE_DIR):
        return []
    out = []
    for f in sorted(os.listdir(PEOPLE_DIR)):
        if not f.endswith(".md"):
            continue
        uid = f[:-3]
        try:
            with open(os.path.join(PEOPLE_DIR, f)) as fh:
                body = fh.read()
        except OSError:
            continue
        header = (body.split("\n", 1)[0] if body else "").lstrip("# ").strip()
        out.append((uid, header, body))
    return out


def cmd_list():
    profs = _profiles()
    if not profs:
        print("no profiles yet")
        return
    print(f"{len(profs)} saved:")
    for uid, header, _ in profs:
        print(f"  {uid:<20} {header}")


def cmd_search(query):
    q = query.lower()
    hits = [(uid, header, body) for uid, header, body in _profiles()
            if q in body.lower() or q in uid.lower()]
    if not hits:
        print(f"no match for {query!r}")
        return
    print(f"{len(hits)} match {query!r}:")
    for uid, header, body in hits:
        i = body.lower().find(q)
        snip = body[max(0, i - 40):i + 60].replace("\n", " ").strip() if i >= 0 else ""
        print(f"  {uid:<20} {header}")
        if snip:
            print(f"      …{snip}…")


def cmd_show(key):
    k = key.lower()
    for uid, header, body in _profiles():
        if k == uid.lower() or k in header.lower():
            print(body.rstrip())
            return
    print(f"no profile matching {key!r}")


def cmd_json():
    """machine-readable: [{uid, header, username, body, tags}] for widgets."""
    import json
    out = []
    for uid, header, body in _profiles():
        # header like "real_matejj (1005064737689718814)" — strip the trailing id
        uname = header.rsplit(" (", 1)[0].strip() if " (" in header else header
        lines = body.split("\n", 1)
        stripped_body = lines[1].lstrip("\n") if len(lines) > 1 else ""
        out.append({
            "uid": uid, "username": uname, "header": header, "body": stripped_body.rstrip(),
        })
    print(json.dumps(out, ensure_ascii=False))


def main():
    args = sys.argv[1:]
    if not args or args[0] == "list":
        cmd_list()
    elif args[0] == "search" and len(args) > 1:
        cmd_search(" ".join(args[1:]))
    elif args[0] == "show" and len(args) > 1:
        cmd_show(" ".join(args[1:]))
    elif args[0] == "--json":
        cmd_json()
    else:
        print(__doc__.strip())


if __name__ == "__main__":
    main()
