#!/usr/bin/env python3
"""One-line ambient machine snapshot injected into the widget's first turn."""
import json, os, subprocess

CTX = "/tmp/qs_context.json"
QS = os.path.expanduser("~/.config/hypr/scripts/quickshell")


def load(p, d):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return d


def music():
    try:
        out = subprocess.run(["bash", os.path.join(QS, "music/music_info.sh")],
                             capture_output=True, text=True, timeout=4).stdout.strip()
        d = json.loads(out)
        st = d.get("status", "")
        if st not in ("Playing", "Paused"):
            return ""
        t, a = d.get("title", ""), d.get("artist", "")
        if t and t != "Not Playing":
            return f"{t}" + (f" — {a}" if a else "") + (f" ({st})" if st else "")
    except Exception:
        pass
    return ""


def main():
    c = load(CTX, {})
    s = c.get("system", {})
    b, a, m = s.get("battery", {}), s.get("audio", {}), c.get("mic", {})
    p = c.get("proc", {})
    parts = []
    if b:
        parts.append(f"battery {b.get('percent')}% {b.get('status')}")
    if a:
        parts.append(f"vol {a.get('volume')}%" + (" (muted)" if a.get("is_muted") == "true" else ""))
    parts.append("mic " + ("on" if m.get("on") else "off"))
    if p:
        parts.append(f"cpu {p.get('cpu_pct')}%")
        parts.append(f"mem {p.get('mem', {}).get('used_pct')}%")
    if parts:
        print("Machine right now: " + ", ".join(str(x) for x in parts))

    wl = load("/tmp/qs_workspaces.json", [])
    if isinstance(wl, dict):
        wl = wl.get("workspaces", [])
    if isinstance(wl, list) and wl:
        active = next((w.get("id") for w in wl if w.get("state") == "active"), None)
        used = [w for w in wl if w.get("state") in ("active", "occupied")]
        parts = []
        for w in used:
            label = w.get("tooltip", "") or ""
            parts.append(f"{w.get('id')}:{label}" if label and label != "Empty" else str(w.get("id")))
        if parts:
            line = "Workspaces in use: " + "; ".join(parts)
            if active is not None:
                line += f" — currently on {active}"
            print(line)

    nm = music()
    if nm:
        print("Now playing: " + nm)


if __name__ == "__main__":
    main()
