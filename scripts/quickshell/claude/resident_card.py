#!/usr/bin/env python3
import os, sys, json, time, argparse, uuid

QUEUE = "/tmp/qs_resident_cards.jsonl"
QUEUE_MAX = 60
SETTINGS_FILE = os.path.expanduser("~/.config/hypr/settings.json")
MIN_HOLD = 8
MS_PER_CHAR = 0.06
SHORT_HOLD = 8
MAX_AUTO_HOLD = 90

# ---- pill takeover — a resident finding can briefly tint a specific bar
# pill instead of (or alongside) a card. Single active flag, TopBar.qml
# watches this file the same inotify+cat way it watches qs_eco_state.json.
PILL_FLAG_FILE = "/tmp/qs_resident_pill_flag.json"
PILL_URGENCY_TINT = {"low": "#89dceb", "normal": "#fab387", "high": "#f38ba8"}
PILL_URGENCY_TTL = {"low": 8, "normal": 20, "high": 45}
# Which bar pill a proactive-fix category (see resident_extras.find_fixes)
# most naturally maps to — only wired for keys that map cleanly onto an
# existing named pill in TopBar.qml.
PILL_FOR_FIX_KEY = {
    "bat_health": "battery",
    "disk_full": "cpu",
    "leaks": "cpu",
    "updates": "cpu",
    "failed_units": "cpu",
}


def pill_for_fix_key(key):
    if key.startswith("mem_hog_"):
        return "cpu"
    return PILL_FOR_FIX_KEY.get(key)


def pill_flag(pill, tint=None, urgency="normal", pulse=True, ttl_secs=None, style="wash", open_card=False):
    """Sets the single active pill-takeover flag. `pill` must match one of
    the names TopBar.qml's resident pill watcher recognizes: battery, wifi,
    bt, cpu, gpu, net, uptime, volume, clock, weather, claude, account,
    media, fleet.

    `style` picks how TopBar.qml renders the takeover:
    - "wash" (default) — a soft tinted fill wash, ambient/ongoing-condition
      findings (disk, battery health, updates pending).
    - "border" — a pulsing breathing border ring, reads as more "look here
      now" — better fit for a discrete event (device connect/disconnect,
      network change) than a sustained condition.

    `open_card` (default False) — also force that pill's own hover card
    open for the flag's duration, so the finding is visible without the
    user hovering at all. Backward compatible: omitted/False behaves
    exactly as before (tint/pulse only).
    """
    if not _settings().get("residentPillTakeoverEnabled", True):
        return None
    ttl = ttl_secs if ttl_secs is not None else PILL_URGENCY_TTL.get(urgency, 20)
    flag = {
        "pill": pill,
        "tint": tint or PILL_URGENCY_TINT.get(urgency, "#cba6f7"),
        "pulse": bool(pulse),
        "style": style if style in ("wash", "border") else "wash",
        "urgency": urgency if urgency in ("low", "normal", "high") else "normal",
        "open_card": bool(open_card),
        "expires_ts": time.time() + max(1, ttl),
    }
    try:
        tmp = PILL_FLAG_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(flag, f, ensure_ascii=False)
        os.replace(tmp, PILL_FLAG_FILE)
    except OSError:
        pass
    return flag


def _settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def compute_hold(body, actions, urgency, requested=None, mode=None):
    mode = mode or _settings().get("residentCardHoldMode", "auto")
    if mode == "until-dismissed":
        return 0
    if mode == "short":
        return SHORT_HOLD
    if requested is not None and requested >= 0:
        return requested
    if actions or urgency == "high":
        return 0
    return int(min(MAX_AUTO_HOLD, max(MIN_HOLD, len(body or "") * MS_PER_CHAR + 4)))


def emit(title, body="", icon="", urgency="normal", hold_secs=None, actions=None, source="resident", card_id=None,
         kind=None, data=None):
    actions = [a for a in (actions or []) if a.get("label") and a.get("cmd")]
    card = {
        "id": card_id or uuid.uuid4().hex[:10],
        "ts": int(time.time()),
        "title": title,
        "body": body,
        "icon": icon,
        "urgency": urgency if urgency in ("low", "normal", "high") else "normal",
        "hold_secs": compute_hold(body, actions, urgency, hold_secs),
        "actions": actions,
        "source": source,
    }
    if kind:
        card["kind"] = kind
        card["data"] = data or {}
    try:
        lines = []
        try:
            with open(QUEUE) as f:
                lines = f.read().splitlines()
        except OSError:
            pass
        if card_id:
            lines = [ln for ln in lines if not _has_id(ln, card_id)]
        lines.append(json.dumps(card, ensure_ascii=False))
        lines = lines[-QUEUE_MAX:]
        tmp = QUEUE + ".tmp"
        with open(tmp, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, QUEUE)
    except OSError:
        pass
    return card


OSD_FILE = "/tmp/qs_resident_osd"


def osd(text, icon="", tint=""):
    """Fires the lightweight ResidentOsd.qml flash — for the shortest-lived
    single facts only (celebration/resolve-confirmation moments), NOT a
    replacement for the card queue. See resident_extras._celebrate_resolved."""
    try:
        with open(OSD_FILE, "w") as f:
            json.dump({"text": text, "icon": icon, "tint": tint}, f, ensure_ascii=False)
    except OSError:
        pass


SHOT_ANSWER_LOG = os.path.expanduser("~/.cache/quickshell/claude/shot_answers.jsonl")
SHOT_ANSWER_LOG_MAX = 200


def log_shot_answer(question_or_mode, answer, image_path=""):
    """Append-only history for the SUPER+CTRL+Z / SUPER+ALT+Z screenshot
    answer flows (shot_answer.py, shot_ask.py) — read back by the Guide's
    resident tab. Best-effort, never raises into the caller."""
    try:
        os.makedirs(os.path.dirname(SHOT_ANSWER_LOG), exist_ok=True)
        lines = []
        if os.path.exists(SHOT_ANSWER_LOG):
            with open(SHOT_ANSWER_LOG) as f:
                lines = f.read().splitlines()
        entry = {"ts": int(time.time()), "question": question_or_mode, "answer": answer,
                 "image_path": image_path}
        lines.append(json.dumps(entry, ensure_ascii=False))
        lines = lines[-SHOT_ANSWER_LOG_MAX:]
        tmp = SHOT_ANSWER_LOG + ".tmp"
        with open(tmp, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, SHOT_ANSWER_LOG)
    except OSError:
        pass


def _queue_cards():
    try:
        with open(QUEUE) as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    out = []
    for ln in lines:
        try:
            out.append((ln, json.loads(ln)))
        except Exception:
            out.append((ln, None))
    return out


def clear_kinds(kinds):
    kinds = set(kinds)
    cards = _queue_cards()
    keep = [ln for ln, c in cards if not (c and c.get("kind") in kinds)]
    removed = len(cards) - len(keep)
    if removed:
        tmp = QUEUE + ".tmp"
        with open(tmp, "w") as f:
            f.write("\n".join(keep) + ("\n" if keep else ""))
        os.replace(tmp, QUEUE)
    return removed


def count_kinds():
    counts = {}
    for _, c in _queue_cards():
        if c and c.get("kind"):
            counts[c["kind"]] = counts.get(c["kind"], 0) + 1
    return counts


def _has_id(line, card_id):
    try:
        return json.loads(line).get("id") == card_id
    except Exception:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", default=None)
    ap.add_argument("--body", default="")
    ap.add_argument("--icon", default="")
    ap.add_argument("--urgency", default="normal")
    ap.add_argument("--hold", type=int, default=None)
    ap.add_argument("--source", default="cli")
    ap.add_argument("--id", default=None)
    ap.add_argument("--action", action="append", default=[], help="label=cmd")
    ap.add_argument("--kind", default=None, help="custom renderer kind, see CARD_KINDS.md")
    ap.add_argument("--data", default=None, help="JSON payload for --kind")
    # Pill-takeover CLI mode — lets non-Python callers (e.g. BatteryAlarm.qml's
    # integrated battery alert) drive pill_flag() without duplicating its
    # schema/gating logic in a raw file write.
    ap.add_argument("--pill", default=None, help="pill name — presence switches to pill-flag mode")
    ap.add_argument("--tint", default=None)
    ap.add_argument("--style", default="wash")
    ap.add_argument("--ttl", type=int, default=None)
    ap.add_argument("--no-pulse", action="store_true")
    ap.add_argument("--open-card", action="store_true", help="also force the pill's hover card open for the flag's duration")
    ap.add_argument("--clear-kind", action="append", default=[], help="remove queued cards of this kind (repeatable)")
    ap.add_argument("--count-kinds", action="store_true", help="print queued card count per kind as JSON")
    a = ap.parse_args()
    if a.count_kinds:
        print(json.dumps(count_kinds()))
        return
    if a.clear_kind:
        print(json.dumps({"removed": clear_kinds(a.clear_kind)}))
        return
    if a.pill:
        flag = pill_flag(a.pill, tint=a.tint, urgency=a.urgency, pulse=not a.no_pulse,
                         ttl_secs=a.ttl, style=a.style, open_card=a.open_card)
        print(json.dumps(flag, ensure_ascii=False))
        return
    if not a.title:
        ap.error("--title is required unless --pill is given")
    actions = []
    for spec in a.action:
        if "=" in spec:
            label, cmd = spec.split("=", 1)
            actions.append({"label": label, "cmd": cmd})
    card = emit(a.title, a.body, a.icon, a.urgency, a.hold, actions, a.source, a.id,
                kind=a.kind, data=json.loads(a.data) if a.data else None)
    print(json.dumps(card, ensure_ascii=False))


if __name__ == "__main__":
    main()
