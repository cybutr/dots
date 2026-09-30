#!/usr/bin/env python3
import os, sys, shlex, subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot_action import _vision_call
from resident_card import emit, _settings, log_shot_answer

DEFAULT_PROMPT = (
    "Solve what's in this screenshot correctly. First reason briefly (max 4 short sentences) "
    "about which answer is actually right, checking each option against real domain "
    "knowledge. Then end with a final line starting with 'ANSWER:' followed by only the "
    "answer, max 15 words. Multiple choice: option number plus at most 6 words of that "
    "option (in the question's language). Problem: just the result. Error: the one-line fix."
)
PROMPT = DEFAULT_PROMPT
MODEL = "claude-sonnet-5"


def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        return
    cfg = _settings()
    prompt = cfg.get("residentShotAnswerPrompt") or DEFAULT_PROMPT
    ans = _vision_call(sys.argv[1], prompt, 500, MODEL)
    if ans and "ANSWER:" in ans:
        ans = ans.rsplit("ANSWER:", 1)[1].strip()
    if not ans:
        ans = "no answer (api call failed)"
    log_shot_answer("answer this", ans, sys.argv[1])
    out = cfg.get("screenshotAnswerOutput", "card")
    if not cfg.get("residentCardsEnabled", True) or out not in ("card", "notification", "both"):
        out = "notification"
    if out in ("card", "both"):
        # The answer is already auto-copied to the clipboard below (line ~38)
        # the instant this card appears, so the "Copy" button is a backup,
        # not the only way to consume it — holding the card open forever
        # (the resident_card.emit default when actions are present) just
        # leaves stale answers cluttering the bar. Scale the hold to how
        # long the answer actually takes to read, same idiom as every other
        # auto-dismissing card, instead of the actions-present default.
        hold = min(60, max(15, int(len(ans) * 0.07) + 8))
        emit("Screenshot answer", ans, "camera", "normal", hold, [{"label": "Copy", "cmd": "printf %s " + shlex.quote(ans) + " | wl-copy"}], "screenshot", card_id="screenshot-answer")
    if out in ("notification", "both"):
        subprocess.run(["notify-send", "-a", "Claude", "-u", "normal", "-t", "20000",
                        "-i", "dialog-information", "Claude · answer", ans], check=False)
    subprocess.run(["wl-copy", "--", ans], check=False)


if __name__ == "__main__":
    main()
