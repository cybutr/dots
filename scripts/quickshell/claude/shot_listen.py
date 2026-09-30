#!/usr/bin/env python3
"""Evdev key capture for the SUPER+ALT+Z "listening" question field. Modeled
on ../ctrl_watch.py's pattern (raw evdev, no X/Wayland keyboard focus
needed — the bar window never gets real keyboard focus, see hypr/CLAUDE.md)
plus alttab_monitor.py's "ignore whatever was already held when we started"
guard, extended here to any key (not just a modifier) so a Z key that's
somehow still physically down from the SUPER+ALT+Z keybind press doesn't
leak into the typed buffer.

Started by TopBar.qml's ClaudeStatus.qml via `sg input -c` (same permission
requirement as alttab_monitor.py) once /tmp/qs_shot_listen_trigger is
written by shot_ask.sh. Reads the screenshot path from that trigger file
(not argv) so the QML side never has to shell-quote a path into the Process
command array.

Streams the live typed buffer to /tmp/qs_shot_listen.json, polled by
TopBar.qml via the standard inotify+cat idiom (same one used for
/tmp/qs_timer.json etc). On Enter: finalizes the buffer as the question and
hands off to shot_ask.py (kept as a separate process so a slow vision call
doesn't hold this evdev listener, and so the listener's own exit is what
tells TopBar.qml to leave the listening state). On Escape or 180s of no
input: cancels silently, no API call.
"""
import os, json, time, fcntl, selectors, subprocess, signal
import evdev
from evdev import ecodes

HOME = os.path.expanduser("~")
TRIGGER = "/tmp/qs_shot_listen_trigger"
STATE = "/tmp/qs_shot_listen.json"
LOCK = "/tmp/qs_shot_listen.lock"
IDLE_TIMEOUT = 180
SELF_DIR = os.path.dirname(os.path.abspath(__file__))

LETTERS = "abcdefghijklmnopqrstuvwxyz"
KEYMAP = {}
for ch in LETTERS:
    KEYMAP[getattr(ecodes, "KEY_" + ch.upper())] = (ch, ch.upper())

DIGIT_ROW = [
    (ecodes.KEY_1, "1", "!"), (ecodes.KEY_2, "2", "@"), (ecodes.KEY_3, "3", "#"),
    (ecodes.KEY_4, "4", "$"), (ecodes.KEY_5, "5", "%"), (ecodes.KEY_6, "6", "^"),
    (ecodes.KEY_7, "7", "&"), (ecodes.KEY_8, "8", "*"), (ecodes.KEY_9, "9", "("),
    (ecodes.KEY_0, "0", ")"),
]
PUNCT = [
    (ecodes.KEY_MINUS, "-", "_"), (ecodes.KEY_EQUAL, "=", "+"),
    (ecodes.KEY_LEFTBRACE, "[", "{"), (ecodes.KEY_RIGHTBRACE, "]", "}"),
    (ecodes.KEY_BACKSLASH, "\\", "|"), (ecodes.KEY_SEMICOLON, ";", ":"),
    (ecodes.KEY_APOSTROPHE, "'", '"'), (ecodes.KEY_COMMA, ",", "<"),
    (ecodes.KEY_DOT, ".", ">"), (ecodes.KEY_SLASH, "/", "?"),
    (ecodes.KEY_GRAVE, "`", "~"),
]
for code, lo, hi in DIGIT_ROW + PUNCT:
    KEYMAP[code] = (lo, hi)

SHIFT_KEYS = {ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT}
ENTER_KEYS = {ecodes.KEY_ENTER, ecodes.KEY_KPENTER}


def write_state(text):
    tmp = STATE + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump({"text": text, "ts": time.time()}, f)
        os.replace(tmp, STATE)
    except OSError:
        pass


def main():
    # single-instance guard — if a second bar/monitor's ClaudeStatus.qml
    # also spun one of these up for the same trigger, the loser exits
    # immediately rather than double-typing or double-answering
    lockf = open(LOCK, "w")
    try:
        fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return

    try:
        with open(TRIGGER) as f:
            image_path = f.read().strip()
    except OSError:
        return
    if not image_path or not os.path.exists(image_path):
        return

    devs = []
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
            caps = d.capabilities().get(ecodes.EV_KEY) or []
            if ecodes.KEY_A in caps:
                devs.append(d)
        except OSError:
            pass
    if not devs:
        return

    caps_on = False
    for d in devs:
        try:
            if ecodes.LED_CAPSL in d.leds():
                caps_on = True
                break
        except Exception:
            pass

    # ignore any key that's already physically held when we start (eg a Z
    # still down from the SUPER+ALT+Z press) until it's released
    ignore_initial = set()
    for d in devs:
        try:
            ignore_initial |= set(d.active_keys())
        except OSError:
            pass

    write_state("")

    # exclusive grab — while listening, these devices deliver events ONLY to
    # this process (EVIOCGRAB), not to whatever window has real focus
    # underneath. Must be released on every exit path or the keyboard stays
    # dead system-wide, so grabbing happens right before the try/finally
    # that guarantees ungrab, and a SIGTERM/SIGINT handler (lifeline.sh
    # sends a plain kill, not SIGKILL, so this runs) turns those signals
    # into a normal exception so the same finally still fires.
    grabbed = []

    def _signal_exit(signum, frame):
        raise SystemExit(0)

    old_term = signal.signal(signal.SIGTERM, _signal_exit)
    old_int = signal.signal(signal.SIGINT, _signal_exit)

    try:
        for d in devs:
            try:
                d.grab()
                grabbed.append(d)
            except OSError:
                pass

        sel = selectors.DefaultSelector()
        for d in devs:
            sel.register(d.fileno(), selectors.EVENT_READ, d)

        buf = []
        shift_held = False
        finalize_question = None

        while True:
            events = sel.select(timeout=IDLE_TIMEOUT)
            if not events:
                return  # idle timeout — cancel silently, same as Escape

            for key, _ in events:
                try:
                    evs = key.data.read()
                except OSError:
                    continue
                for e in evs:
                    if e.type != ecodes.EV_KEY:
                        continue
                    code, value = e.code, e.value

                    if code in ignore_initial:
                        if value == 0:
                            ignore_initial.discard(code)
                        continue

                    if code in SHIFT_KEYS:
                        shift_held = value != 0
                        continue

                    if code == ecodes.KEY_CAPSLOCK:
                        if value == 1:
                            caps_on = not caps_on
                        continue

                    if value == 0:
                        continue  # only act on keydown(1)/repeat(2)

                    if code == ecodes.KEY_ESC:
                        return  # cancel silently, no API call

                    if code in ENTER_KEYS:
                        finalize_question = "".join(buf).strip()
                        break

                    if code == ecodes.KEY_BACKSPACE:
                        if buf:
                            buf.pop()
                        write_state("".join(buf))
                        continue

                    if code == ecodes.KEY_SPACE:
                        buf.append(" ")
                        write_state("".join(buf))
                        continue

                    if code in KEYMAP:
                        lo, hi = KEYMAP[code]
                        use_shift = (shift_held != caps_on) if lo.isalpha() else shift_held
                        buf.append(hi if use_shift else lo)
                        write_state("".join(buf))
                        continue

                if finalize_question is not None:
                    break
            if finalize_question is not None:
                break

        if finalize_question:
            subprocess.Popen(
                ["python3", os.path.join(SELF_DIR, "shot_ask.py"), image_path, finalize_question],
                start_new_session=True,
            )
    finally:
        for d in grabbed:
            try:
                d.ungrab()
            except OSError:
                pass
        signal.signal(signal.SIGTERM, old_term)
        signal.signal(signal.SIGINT, old_int)


if __name__ == "__main__":
    main()
