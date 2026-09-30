#!/usr/bin/env python3
"""Backend for the SUPER+ALT+Z screenshot + custom-question flow. Distinct
from shot_action.py's auto-classify flow and shot_answer.py's fixed-prompt
"answer this" flow — this one takes a free-form question typed live via
evdev (see shot_listen.py, driven from the Claude pill in TopBar.qml) and
hits shot_action's _vision_call() directly, a raw urllib POST to the
Anthropic Messages API using a key file, not the `claude` CLI. That's the
point: it keeps answering screenshots even when the Claude Code
subscription/session has no tokens left.

Usage: shot_ask.py <image_path> <question...>
Output goes through resident_card.emit()/notify-send exactly like
shot_answer.py, respecting the screenshotAnswerOutput setting.
"""
import os, sys, shlex, subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot_action import _vision_call
from resident_card import emit, _settings, log_shot_answer

PROMPT_PREFIX = (
    "Answer the user's question about this screenshot directly and concisely. "
    "Plain text only, no markdown fences, no preamble. Question: "
)


def main():
    if len(sys.argv) < 3 or not os.path.exists(sys.argv[1]):
        return
    image_path = sys.argv[1]
    question = " ".join(sys.argv[2:]).strip()
    if not question:
        return

    ans = _vision_call(image_path, prompt=PROMPT_PREFIX + question, max_tokens=800)
    ans = ans.strip() if ans else "no answer (api call failed — check ~/.config/anthropic/accounts/backup.key)"
    log_shot_answer(question, ans, image_path)

    cfg = _settings()
    out = cfg.get("screenshotAnswerOutput", "card")
    if not cfg.get("residentCardsEnabled", True) or out not in ("card", "notification", "both"):
        out = "notification"
    if out in ("card", "both"):
        # Already auto-copied to clipboard below the instant this fires, so
        # don't hold forever waiting for a "Copy" click — see shot_answer.py
        # for the same fix and the full reasoning.
        hold = min(60, max(15, int(len(ans) * 0.07) + 8))
        emit("Screenshot answer", ans, "camera", "normal", hold,
             [{"label": "Copy", "cmd": "printf %s " + shlex.quote(ans) + " | wl-copy"}], "screenshot")
    if out in ("notification", "both"):
        subprocess.run(["notify-send", "-a", "Claude", "-u", "normal", "-t", "20000",
                        "-i", "dialog-information", "Claude · answer", ans], check=False)
    subprocess.run(["wl-copy", "--", ans], check=False)


if __name__ == "__main__":
    main()
