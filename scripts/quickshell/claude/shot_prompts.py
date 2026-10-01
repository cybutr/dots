#!/usr/bin/env python3
import json, os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.join(HERE, "shot_prompts.json")
SETTINGS = os.path.expanduser("~/.config/hypr/settings.json")
SETTING_KEY = "residentShotAnswerPrompt"

SOLVE_PROMPT = (
    "Solve what's in this screenshot correctly. First reason briefly (max 4 short sentences) "
    "about which answer is actually right, checking each option against real domain "
    "knowledge. Then end with a final line starting with 'ANSWER:' followed by only the "
    "answer, max 15 words. Multiple choice: option number plus at most 6 words of that "
    "option (in the question's language). Problem: just the result. Error: the one-line fix."
)


def _read_json(path, fallback):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return fallback


def _write_json(path, data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".shotprompts-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def _setting():
    return (_read_json(SETTINGS, {}).get(SETTING_KEY) or "").strip()


def _push_setting(text):
    cfg = _read_json(SETTINGS, None)
    if not isinstance(cfg, dict) or cfg.get(SETTING_KEY) == text:
        return
    cfg[SETTING_KEY] = text
    _write_json(SETTINGS, cfg)


def load():
    data = _read_json(STORE, None)
    if not isinstance(data, dict) or not data.get("prompts"):
        legacy = _setting()
        prompts = {}
        if legacy:
            prompts["geoguessr"] = legacy
        prompts["solve"] = SOLVE_PROMPT
        data = {"active": next(iter(prompts)), "prompts": prompts, "syncedSetting": legacy}
        _write_json(STORE, data)
    if data.get("active") not in data["prompts"]:
        data["active"] = next(iter(data["prompts"]))
    return data


def save(data, sync=True):
    text = data["prompts"][data["active"]]
    if sync:
        data["syncedSetting"] = text
    _write_json(STORE, data)
    if sync:
        _push_setting(text)


def active_text():
    data = load()
    edited = _setting()
    if edited and edited != data.get("syncedSetting") and edited not in data["prompts"].values():
        data["prompts"][data["active"]] = edited
        data["syncedSetting"] = edited
        _write_json(STORE, data)
    return data["prompts"][data["active"]]


def _clean_name(name):
    return " ".join((name or "").split())[:32]


def activate(name):
    data = load()
    if name not in data["prompts"]:
        return False
    data["active"] = name
    save(data)
    return True


def add(name, text, make_active=True):
    name, text = _clean_name(name), (text or "").strip()
    if not name or not text:
        return False
    data = load()
    data["prompts"][name] = text
    if make_active:
        data["active"] = name
    save(data)
    return True


def delete(name):
    data = load()
    if name not in data["prompts"] or len(data["prompts"]) < 2:
        return False
    del data["prompts"][name]
    if data["active"] == name:
        data["active"] = next(iter(data["prompts"]))
    save(data)
    return True


def as_view():
    data = load()
    return {
        "active": data["active"],
        "prompts": [{"name": k, "text": v} for k, v in data["prompts"].items()],
    }


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "json"
    ok = True
    if cmd == "activate" and len(argv) > 2:
        ok = activate(argv[2])
    elif cmd == "add" and len(argv) > 3:
        ok = add(argv[2], argv[3])
    elif cmd == "delete" and len(argv) > 2:
        ok = delete(argv[2])
    elif cmd == "active":
        print(active_text())
        return 0
    elif cmd != "json":
        print("usage: shot_prompts.py [json|active|activate NAME|add NAME TEXT|delete NAME]", file=sys.stderr)
        return 2
    print(json.dumps(as_view(), ensure_ascii=False))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
