#!/usr/bin/env python3
import os, json, glob

HOME = os.path.expanduser("~")


def desc_of(path):
    try:
        with open(path) as f:
            head = f.read(1200)
    except OSError:
        return ""
    if head.startswith("---"):
        end = head.find("---", 3)
        fm = head[3:end] if end > 0 else head
        for line in fm.splitlines():
            line = line.strip()
            if line.lower().startswith("description:"):
                return line.split(":", 1)[1].strip().strip('"\'')[:80]
    for line in head.splitlines():
        line = line.strip()
        if line and not line.startswith("---"):
            return line.lstrip("# ").strip()[:80]
    return ""


def main():
    out = []
    seen = set()

    for base in [os.path.join(HOME, ".claude", "commands"),
                 os.path.join(HOME, ".config", "claude", "commands")]:
        for path in glob.glob(os.path.join(base, "**", "*.md"), recursive=True):
            name = os.path.relpath(path, base)[:-3].replace(os.sep, ":")
            key = "/" + name
            if key in seen:
                continue
            seen.add(key)
            out.append({"name": key, "desc": desc_of(path), "kind": "command"})

    for path in glob.glob(os.path.join(HOME, ".claude", "skills", "*", "SKILL.md")):
        name = os.path.basename(os.path.dirname(path))
        key = "/" + name
        if key in seen:
            continue
        seen.add(key)
        out.append({"name": key, "desc": desc_of(path), "kind": "skill"})

    out.sort(key=lambda x: x["name"])
    print(json.dumps(out))


if __name__ == "__main__":
    main()
