#!/usr/bin/env python3
"""#10 screenshot-action. Called at the end of screenshot.sh with the saved
PNG path. A vision-capable Haiku call classifies the shot (error/text/ui/
none) with a short summary (and an OCR transcript if it's mostly text), then
surfaces exactly one matching action card. Silent if nothing's actionable."""
import os, sys, json, base64, subprocess, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import resident_card
except Exception:
    resident_card = None

try:
    from claude_say import _read_key, _call, _PROVIDERS, DEFAULT_MODEL
except Exception:
    _PROVIDERS = []
    DEFAULT_MODEL = "claude-haiku-4-5-20251001"

    def _read_key(name): return ""

    def _call(*a, **k): return ""

try:
    from claude_resident import save, load, notify, SUGGEST, QS_MANAGER
except Exception:
    def load(path, default):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            return default

    def save(path, obj):
        try:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(obj, f)
            os.replace(tmp, path)
        except OSError:
            pass

    def notify(title, body, urgency):
        try:
            subprocess.run(["notify-send", "-a", "Claude", "-u", urgency,
                            "-i", "dialog-information", title, body], timeout=5, check=False)
        except Exception:
            pass

    SUGGEST = "/tmp/qs_resident_suggestion"
    HOME = os.path.expanduser("~")
    QS_MANAGER = os.path.join(HOME, ".config/hypr/scripts/qs_manager.sh")

DEFAULT_PROMPT = (
    "Classify this screenshot into exactly one category: 'error' (visible error message, "
    "stacktrace, crash dialog, failed command), 'text' (mostly readable text worth "
    "extracting — a document, chat, code, terminal output), 'ui' (a UI/design worth "
    "annotating or discussing), or 'none' (nothing actionable — a game, a video, a blank "
    "desktop, etc). Reply with ONLY compact JSON, no markdown fence: "
    '{"category":"error|text|ui|none","summary":"one short line","text_content":"transcribed '
    'text if category is text, else empty string"}'
)
PROMPT = DEFAULT_PROMPT

SETTINGS_FILE = os.path.expanduser("~/.config/hypr/settings.json")


def _settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _vision_call(image_path, prompt=None, max_tokens=400, model=None):
    if prompt is None:
        prompt = _settings().get("residentShotClassifyPrompt") or DEFAULT_PROMPT
    try:
        with open(image_path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode()
    except OSError:
        return None
    body = {"model": model or DEFAULT_MODEL, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                              "data": b64}},
                {"type": "text", "text": prompt}]}]}
    for keyfile, base_url in _PROVIDERS:
        key = _read_key(keyfile)
        if not key:
            continue
        try:
            import urllib.request
            req = urllib.request.Request(
                base_url, data=json.dumps(body).encode(),
                headers={"content-type": "application/json", "x-api-key": key,
                         "anthropic-version": "2023-06-01"}, method="POST")
            with urllib.request.urlopen(req, timeout=25) as r:
                data = json.loads(r.read())
            text = "".join(b.get("text", "") for b in data.get("content", [])
                           if b.get("type") == "text").strip()
            if text:
                return text
        except Exception:
            continue
    return None


def _parse(raw):
    if not raw:
        return None
    s = raw.strip()
    if s.startswith("```"):
        s = s.strip("`")
        s = s[s.find("{"):]
    try:
        return json.loads(s)
    except Exception:
        return None


def main():
    if len(sys.argv) < 2:
        return
    path = sys.argv[1]
    if not os.path.exists(path):
        return
    raw = _vision_call(path)
    d = _parse(raw)
    if not d:
        return
    category = d.get("category", "none")
    summary = d.get("summary", "")
    if category == "none" or not summary:
        return

    now = int(time.time())
    if category == "error":
        prefill = (f"I just took a screenshot of an error: {summary!r}. Look at the image at "
                   f"{path} if you need to (or reason from the summary) and explain what's "
                   f"wrong and how to fix it.")
        cmd = (f"bash -c \"printf '%s' {json.dumps(prefill)} > /tmp/qs_claude_prefill; "
               f"bash {QS_MANAGER} open claudeask\"")
        label = "explain"
    elif category == "text":
        text_content = d.get("text_content", "")
        if text_content:
            cmd = f"wl-copy -- {json.dumps(text_content)}"
            label = "copy text"
        else:
            prefill = f"I just took a screenshot with text in it: {summary!r}. OCR it for me."
            cmd = (f"bash -c \"printf '%s' {json.dumps(prefill)} > /tmp/qs_claude_prefill; "
                   f"bash {QS_MANAGER} open claudeask\"")
            label = "ocr"
    else:  # ui
        cmd = f"satty --filename {path} --output-filename {path} --copy-command wl-copy"
        label = "annotate"

    if resident_card is not None:
        # Has an action, so resident_card.emit's default (None) would hold
        # forever — same class of bug as shot_answer.py/shot_ask.py, fixed
        # there earlier this session. Scale to how long the summary takes
        # to read instead.
        hold = min(60, max(15, int(len(summary) * 0.07) + 8))
        resident_card.emit("Claude · screenshot", summary, "camera-photo", "low", hold,
                           [{"label": label, "cmd": cmd}], "resident", "shot-action-" + str(now))
    else:
        notify("Claude · screenshot", summary, "low")
    save(SUGGEST, {"key": "shot_action_" + str(now), "msg": summary, "urgency": "low",
                   "ts": now, "action_label": label, "action_cmd": cmd, "label": "shot"})


if __name__ == "__main__":
    main()
