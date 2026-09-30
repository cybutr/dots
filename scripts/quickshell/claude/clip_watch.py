#!/usr/bin/env python3
"""#7 clip-smart-transform + #8 clip-error-explain.
Watches the clipboard via `wl-paste --watch` (same idiom as the cliphist
store hook in exec.conf). Classifies new text content locally — no Haiku
call except for the rare error/stacktrace case, which gets an immediate
one-line cause+fix. Everything else surfaces a click-to-open 'paste+' card
whose prefill tells the live agent what transform buttons to offer."""
import os, sys, json, subprocess, time, re, hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from claude_say import say
except Exception:
    def say(*a, **k): return ""

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import resident_card
except Exception:
    resident_card = None

try:
    from claude_resident import save, load, notify, SUGGEST, PERSONA, QS_MANAGER, propose_task_card
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
    PERSONA = ("You are the user's ambient desktop assistant living in their Hyprland shell. "
               "Reply with ONE short line, warm and practical, under 20 words. "
               "No greeting, no sign-off, no quotes, no markdown.")
    HOME = os.path.expanduser("~")
    QS_MANAGER = os.path.join(HOME, ".config/hypr/scripts/qs_manager.sh")

    def propose_task_card(key, prefill, notified):
        save(SUGGEST, {"key": key, "msg": prefill, "urgency": "normal", "ts": int(time.time()),
                       "action_label": "open", "action_cmd": "open", "label": "wants act"})

PID = "/tmp/qs_clip_watch.pid"
LAST_HASH = "/tmp/qs_clip_last_hash"
MIN_LEN, MAX_LEN = 24, 20000
NOTIFIED = "/tmp/qs_clip_notified"
COOLDOWN = 20
PENDING = "/tmp/qs_clip_pending"
GLOBAL_LAST = "/tmp/qs_clip_global_last"
DEBOUNCE_SECS = 1.5
RATE_LIMIT_SECS = 720  # max ~1 clipboard-triggered card per 12 minutes
SETTINGS_FILE = os.path.expanduser("~/.config/hypr/settings.json")


def _settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

STACKTRACE_RE = re.compile(
    r"Traceback \(most recent call last\)|Exception in thread|"
    r"^\s*at [\w.$]+\([\w.]+:\d+\)|"
    r'File "[^"]+", line \d+|'
    r"panicked at|Unhandled exception|returned non-zero exit status|"
    r"\b[A-Za-z.]+(Error|Exception):\s", re.M)
URL_RE = re.compile(r"^https?://\S+$")
CODE_HINTS_RE = re.compile(r"[{};]|=>|^\s*(def|class|function|const|let|var|import|#include)\s", re.M)


def classify(text):
    stripped = text.strip()
    if STACKTRACE_RE.search(text):
        return "stacktrace"
    if URL_RE.match(stripped) and " " not in stripped:
        return "url"
    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, (dict, list)):
            return "json"
    except Exception:
        pass
    if CODE_HINTS_RE.search(text) and "\n" in text:
        return "code"
    letters = re.findall(r"[A-Za-z]", text)
    non_ascii_letters = [c for c in text if c.isalpha() and ord(c) > 127]
    if non_ascii_letters and len(non_ascii_letters) > len(letters):
        return "foreign-language"
    words = stripped.split()
    if len(words) >= 60:
        return "long-prose"
    return None


TRANSFORM_HINTS = {
    "json": "Format/pretty-print, or explain what this JSON represents",
    "code": "Explain what this code does, or format/lint it",
    "foreign-language": "Translate to English, or summarize",
    "long-prose": "Summarize, or explain the key point",
    "url": "Explain what this link is / summarize the page",
}


def _global_rate_ok(now):
    return now - load(GLOBAL_LAST, 0) >= RATE_LIMIT_SECS


def handle_content(text):
    if not _settings().get("residentClipboardAware", True):
        return
    if not (MIN_LEN <= len(text) <= MAX_LEN):
        return
    digest = hashlib.sha1(text.encode("utf-8", "ignore")).hexdigest()
    if load(LAST_HASH, "") == digest:
        return

    # debounce — only act once the clipboard has been stable for a couple
    # seconds, so rapid copy-paste bursts don't each try to fire a card.
    # This process (one `wl-paste --watch` invocation per change) sleeps;
    # if a newer copy supersedes PENDING meanwhile, that newer invocation's
    # own sleep will be the one that actually commits.
    save(PENDING, {"digest": digest, "ts": time.time()})
    time.sleep(DEBOUNCE_SECS)
    if load(PENDING, {}).get("digest") != digest:
        return
    save(LAST_HASH, digest)

    kind = classify(text)
    if not kind:
        return
    now = int(time.time())
    notified = load(NOTIFIED, {})
    if now - notified.get(kind, 0) < COOLDOWN:
        return
    if not _global_rate_ok(now):
        return

    if kind == "url":
        # low-key, no chat detour — just an open/copy-as-markdown-link offer
        url = text.strip()
        if resident_card is None:
            return
        notified[kind] = now
        save(NOTIFIED, notified)
        save(GLOBAL_LAST, now)
        resident_card.emit(
            "Link copied", url, "insert-link", "low", None,
            [{"label": "open", "cmd": f"xdg-open {json.dumps(url)}"},
             {"label": "copy as markdown", "cmd": f"wl-copy -- {json.dumps('[' + url + '](' + url + ')')}"}],
            "resident", "clip-url-" + digest[:10])
        return

    notified[kind] = now
    save(NOTIFIED, notified)

    if kind == "stacktrace":
        # #8 clip-error-explain — immediate one-line cause+fix, no chat detour
        save(GLOBAL_LAST, now)
        out = say(f"This looks like an error/stacktrace from the clipboard:\n{text[:1500]}\n"
                  f"In ONE short line, say the likely cause and fix. Under 20 words, no "
                  f"greeting, no markdown.", system=PERSONA, timeout=20).strip()
        msg = out or "copied something that looks like an error — want me to take a look?"
        explain_cmd = (f"bash -c \"printf '%s' {json.dumps(text[:1500])} > "
                       f"/tmp/qs_claude_prefill; bash {QS_MANAGER} open claudeask\"")
        if resident_card is not None:
            resident_card.emit("Claude", msg, "dialog-error", "normal", None,
                               [{"label": "explain this", "cmd": explain_cmd}],
                               "resident", "clip-error-" + digest[:10])
        else:
            notify("Claude", msg, "normal")
        save(SUGGEST, {"key": "clip_error", "msg": msg, "urgency": "normal",
                       "ts": now, "action_label": "explain this",
                       "action_cmd": explain_cmd,
                       "label": "error"})
        return

    # #7 clip-smart-transform — cheap local classification only; the actual
    # transform (and its own small model call) happens inside the chat turn,
    # triggered when the user opens the card.
    save(GLOBAL_LAST, now)
    hint = TRANSFORM_HINTS.get(kind, "Summarize or explain this")
    prefill = (f"I just copied something classified locally as '{kind}'. Here it is "
               f"(truncated if long):\n\n{text[:2000]}\n\nShow me a 'paste+' card (title "
               f"'Clipboard — {kind}') with a buttons block offering 3-4 relevant transforms "
               f"for this content ({hint}), each a plain string so I can pick one. When I "
               f"pick one, do that transform yourself and wl-copy the result via "
               f"clipboard_control, then confirm in one line.")
    propose_task_card("clip_" + kind, prefill, notified)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--on-change":
        text = sys.stdin.read()
        try:
            handle_content(text)
        except Exception:
            pass
        return

    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))

    subprocess.run(["wl-paste", "--type", "text", "--watch",
                    "python3", os.path.abspath(__file__), "--on-change"])


if __name__ == "__main__":
    main()
