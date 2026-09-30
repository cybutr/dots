#!/usr/bin/env python3
# Applies a resident "update startup workspace" card action — patches the
# matching class entry in startup_apps.json's workspace field. Only ever
# invoked by an explicit card-action click (resident_extras.py's
# tick_startup_drift), never called silently/automatically.
import sys, json, os

CONF = os.path.expanduser("~/.config/hypr/scripts/quickshell/startup_apps.json")


def main():
    if len(sys.argv) != 3:
        print("usage: apply_startup_ws.py <class> <workspace>")
        return 1
    cls, ws = sys.argv[1], sys.argv[2]
    try:
        with open(CONF) as f:
            apps = json.load(f)
    except Exception as e:
        print(f"failed to read {CONF}: {e}")
        return 1
    changed = False
    for a in apps:
        if isinstance(a, dict) and a.get("class") == cls:
            a["workspace"] = ws
            changed = True
    if not changed:
        print(f"no startup_apps.json entry with class {cls!r}")
        return 1
    tmp = CONF + ".tmp"
    with open(tmp, "w") as f:
        json.dump(apps, f, indent=2)
    os.replace(tmp, CONF)
    print(f"updated {cls} startup workspace to {ws}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
