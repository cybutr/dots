#!/usr/bin/env python3
import evdev, sys, subprocess, time

devs = [evdev.InputDevice(p) for p in evdev.list_devices()]
kbds = [d for d in devs if evdev.ecodes.KEY_LEFTALT in (d.capabilities().get(evdev.ecodes.EV_KEY) or [])]
if not kbds:
    sys.exit(1)

start = time.monotonic()
kbd = kbds[0]
ALT_KEYS = {evdev.ecodes.KEY_LEFTALT, evdev.ecodes.KEY_RIGHTALT}

try:
    if ALT_KEYS & set(kbd.active_keys()):
        for event in kbd.read_loop():
            if event.type == evdev.ecodes.EV_KEY:
                kev = evdev.categorize(event)
                if kev.keycode in ('KEY_LEFTALT', 'KEY_RIGHTALT') and kev.keystate == 0:
                    break
except Exception:
    pass

elapsed = time.monotonic() - start
if elapsed < 0.35:
    time.sleep(0.35 - elapsed)

subprocess.run(['bash', '-c', 'echo confirm > /tmp/qs_alttab_nav'])
subprocess.run(['hyprctl', 'dispatch', 'submap', 'reset'])
