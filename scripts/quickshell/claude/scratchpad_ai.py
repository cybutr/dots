#!/usr/bin/env python3
"""Scratchpad AI backend. Raw Messages API via claude_say (no CLI, no hooks).
  scratchpad_ai.py edit <instruction> <text> <selStart> <selEnd>
      -> {"ok", "start", "end", "replacement"}  (range to replace in <text>)
  scratchpad_ai.py complete <before> <after>
      -> {"ok", "completion"}
Always prints one JSON line; ok:false never carries a replacement."""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from claude_say import say, DEFAULT_MODEL  # noqa: E402

EDIT_SYSTEM = (
    "You edit notes inside a student's markdown scratchpad. Follow the user's instruction "
    "precisely and put ONLY the resulting text inside <result></result> tags, nothing else "
    "inside them. No code fences inside the result. Keep the note's language (do not "
    "translate unless asked) and its markdown style. A paragraph is a block of text separated "
    "by blank lines; 'last paragraph' means that whole block. Keep every part of the note the "
    "instruction does not refer to byte-for-byte unchanged."
)

COMPLETE_SYSTEM = (
    "You are an inline autocomplete engine for a markdown notes editor, like code completion "
    "in VS Code. Given the text before and after the cursor, output ONLY the text that should "
    "be inserted at the cursor: a natural continuation of the current sentence or line, at most "
    "one sentence, max ~20 words. Match language, tone and markdown (continue a list item as a "
    "list item). Do not repeat text already before the cursor. Start with a space if one is "
    "needed.\n\n"
    "Only complete text that is unfinished: a sentence cut off mid-way, a dangling clause, a "
    "list item or heading still being typed. If the text before the cursor already ends a "
    "complete thought (a finished sentence ending in . ! ? or a closing ), a finished list "
    "item, a finished paragraph), do NOT start a new sentence or add a follow-up fact: output "
    "exactly <none>. When in doubt, output <none>. Never output explanations."
)

NONE_RE = re.compile(r"^\s*<\s*none\s*/?\s*>\s*$", re.I)
FINISHED_RE = re.compile(r"[.!?…)\"”]\s*$")


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))


def strip_fences(s):
    t = s.strip("\n")
    if t.startswith("```") and t.rstrip().endswith("```"):
        lines = t.splitlines()
        if len(lines) >= 2:
            return "\n".join(lines[1:-1])
    return s


def do_edit(instruction, text, sel_start, sel_end):
    sel_start = max(0, min(sel_start, len(text)))
    sel_end = max(sel_start, min(sel_end, len(text)))
    has_sel = sel_end > sel_start
    if not instruction.strip():
        return out({"ok": False, "error": "no instruction"})
    if not text.strip() and not has_sel:
        prompt = (f"The note is empty.\n\nINSTRUCTION: {instruction}\n\n"
                  "Write the note content inside <result></result>.")
        start, end = 0, len(text)
    elif has_sel:
        marked = text[:sel_start] + "<target>" + text[sel_start:sel_end] + "</target>" + text[sel_end:]
        prompt = (f"<note>\n{marked}\n</note>\n\nINSTRUCTION (applies only to the text inside "
                  f"<target>): {instruction}\n\nReturn ONLY the rewritten target text inside "
                  "<result></result>, without the surrounding note and without the target tags.")
        start, end = sel_start, sel_end
    else:
        prompt = (f"<note>\n{text}\n</note>\n\nINSTRUCTION: {instruction}\n\n"
                  "Return the COMPLETE updated note inside <result></result>.")
        start, end = 0, len(text)
    res = say(prompt, DEFAULT_MODEL, EDIT_SYSTEM, timeout=60, max_tokens=4096)
    if not res:
        return out({"ok": False, "error": "no response from Claude"})
    m = re.search(r"<result>\n?(.*?)\n?</result>", res, re.S)
    if not m:
        return out({"ok": False, "error": "malformed response"})
    res = strip_fences(m.group(1))
    if not res.strip() and text.strip():
        return out({"ok": False, "error": "empty result"})
    if text[start:end].endswith("\n") and not res.endswith("\n"):
        res += "\n"
    out({"ok": True, "start": start, "end": end, "replacement": res})


def do_complete(before, after, manual=False):
    if len(before.strip()) < 8:
        return out({"ok": False, "error": "too little context"})
    line = before.rsplit("\n", 1)[-1]
    # Manual (Ctrl+Space) means the user explicitly asked for a suggestion —
    # skip the "already reads finished" pre-check and let the model itself
    # decide (it can still answer <none> below). Auto-suggest keeps the
    # pre-check so it doesn't nag after every finished sentence.
    if not manual and FINISHED_RE.search(line) and not after.split("\n", 1)[0].strip() and not re.match(r"^\s*(\d+\.)\s*$", line):
        return out({"ok": False, "error": "complete thought"})
    prompt = (f"<before_cursor>{before[-3000:]}</before_cursor>"
              f"<after_cursor>{after[:600]}</after_cursor>")
    res = say(prompt, DEFAULT_MODEL, COMPLETE_SYSTEM, timeout=12, max_tokens=60)
    res = res.replace("\n", " ").rstrip() if res else ""
    if NONE_RE.match(res) or "<none" in res.lower():
        return out({"ok": False, "error": "complete thought"})
    if before.endswith((" ", "\n")):
        res = res.lstrip()
    if not res:
        return out({"ok": False, "error": "no completion"})
    out({"ok": True, "completion": res})


def main():
    a = sys.argv[1:]
    if len(a) == 5 and a[0] == "edit":
        try:
            s, e = int(a[3]), int(a[4])
        except ValueError:
            s = e = 0
        return do_edit(a[1], a[2], s, e)
    if len(a) == 3 and a[0] == "complete":
        return do_complete(a[1], a[2])
    if len(a) == 4 and a[0] == "complete":
        return do_complete(a[1], a[2], manual=(a[3] == "manual"))
    out({"ok": False, "error": "usage: edit <instr> <text> <s> <e> | complete <before> <after>"})


if __name__ == "__main__":
    try:
        main()
    except Exception as ex:
        out({"ok": False, "error": str(ex)[:200]})
