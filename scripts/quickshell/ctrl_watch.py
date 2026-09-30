#!/usr/bin/env python3
import sys, selectors
import evdev
from evdev import ecodes

CTRL = (ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL)
devs = []
for path in evdev.list_devices():
    try:
        d = evdev.InputDevice(path)
        if ecodes.EV_KEY in d.capabilities() and ecodes.KEY_LEFTCTRL in d.capabilities()[ecodes.EV_KEY]:
            devs.append(d)
    except OSError:
        pass

def held():
    for d in devs:
        try:
            if any(k in d.active_keys() for k in CTRL):
                return True
        except OSError:
            pass
    return False

last = None
def emit(v):
    global last
    if v != last:
        last = v
        print("1" if v else "0", flush=True)

emit(held())
sel = selectors.DefaultSelector()
for d in devs:
    sel.register(d, selectors.EVENT_READ)
while True:
    for key, _ in sel.select():
        try:
            for e in key.fileobj.read():
                if e.type == ecodes.EV_KEY and e.code in CTRL:
                    emit(held())
        except OSError:
            pass
