"""Touchpad and keyboard for qs-remote: a WebSocket the Fleet app streams
pointer moves, clicks, scrolls, keys and gestures into.

Input goes through ydotoold's socket as raw input_event structs, so a moving
finger costs a datagram, not a process. Text is typed with wtype when it is
installed (layout-independent and Unicode-safe), else with `ydotool type`.
Keys are sent as physical evdev codes, exactly like the laptop's own keyboard,
so keybinds behave the same whatever layout is active.

Nothing typed is ever logged: the audit trail gets one line per session.
"""
import base64
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import threading
import time

WS_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_FRAME = 64 * 1024
IDLE_TIMEOUT = 90  # the app pings every 15 s

EV_SYN, EV_KEY, EV_REL = 0x00, 0x01, 0x02
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL = 0x00, 0x01, 0x06, 0x08
REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES = 0x0B, 0x0C
BTN = {"left": 0x110, "right": 0x111, "middle": 0x112}
EVENT = struct.Struct("<qqHHi")  # struct input_event on 64-bit Linux

# Physical evdev key codes (linux/input-event-codes.h).
KEYS = {
    "esc": 1, "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
    "minus": 12, "equal": 13, "backspace": 14, "tab": 15,
    "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22, "i": 23, "o": 24, "p": 25,
    "leftbrace": 26, "rightbrace": 27, "enter": 28, "ctrl": 29,
    "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37, "l": 38,
    "semicolon": 39, "apostrophe": 40, "grave": 41, "shift": 42, "backslash": 43,
    "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49, "m": 50,
    "comma": 51, "dot": 52, "slash": 53, "rightshift": 54, "alt": 56, "space": 57, "capslock": 58,
    "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63, "f6": 64, "f7": 65, "f8": 66, "f9": 67, "f10": 68,
    "f11": 87, "f12": 88, "rightctrl": 97, "print": 99, "rightalt": 100,
    "home": 102, "up": 103, "pageup": 104, "left": 105, "right": 106, "end": 107, "down": 108,
    "pagedown": 109, "insert": 110, "delete": 111, "mute": 113, "volumedown": 114, "volumeup": 115,
    "super": 125, "menu": 139, "nextsong": 163, "playpause": 164, "previoussong": 165,
    "brightnessdown": 224, "brightnessup": 225,
}
MODS = {"super", "ctrl", "alt", "shift"}

GESTURES = {
    "ws_next": ["hyprctl", "dispatch", "workspace", "e+1"],
    "ws_prev": ["hyprctl", "dispatch", "workspace", "e-1"],
    "ws_right": ["hyprctl", "dispatch", "workspace", "+1"],
    "ws_left": ["hyprctl", "dispatch", "workspace", "-1"],
}


def _socket_path():
    uid = os.getuid()
    for p in (os.environ.get("YDOTOOL_SOCKET"), f"/run/user/{uid}/.ydotool_socket", "/tmp/.ydotool_socket"):
        if p and os.path.exists(p):
            return p
    return None


class Injector:
    """One per process. Thread-safe; every session shares it."""

    def __init__(self):
        self.mu = threading.Lock()
        self.sock = None
        self.path = None
        self.held = set()
        self.acc_x = self.acc_y = 0

    def available(self):
        return self._connect() is not None or shutil.which("ydotool") is not None

    def _connect(self):
        if self.sock is not None:
            return self.sock
        path = _socket_path()
        if not path:
            return None
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            s.connect(path)
            self.sock, self.path = s, path
        except OSError:
            self.sock = None
        return self.sock

    def _emit(self, events):
        """events: [(type, code, value), ...]; a SYN is appended."""
        with self.mu:
            s = self._connect()
            if s is None:
                return self._fallback(events)
            try:
                for t, c, v in events + [(EV_SYN, 0, 0)]:
                    s.send(EVENT.pack(0, 0, t, c, v))
                return True
            except OSError:
                self.sock = None
                return self._fallback(events)

    def _fallback(self, events):
        # Slow path: no daemon socket, so drive the CLI. Good enough for keys
        # and clicks; pointer motion will be choppy until ydotoold runs.
        if not shutil.which("ydotool"):
            return False
        env = {**os.environ, "YDOTOOL_SOCKET": self.path or f"/run/user/{os.getuid()}/.ydotool_socket"}
        dx = sum(v for t, c, v in events if t == EV_REL and c == REL_X)
        dy = sum(v for t, c, v in events if t == EV_REL and c == REL_Y)
        wheel = sum(v for t, c, v in events if t == EV_REL and c == REL_WHEEL)
        cmd = None
        if dx or dy:
            cmd = ["ydotool", "mousemove", "-x", str(dx), "-y", str(dy)]
        elif wheel:
            cmd = ["ydotool", "mousemove", "-w", "-x", "0", "-y", str(wheel)]
        else:
            keys = [f"{c}:{v}" for t, c, v in events if t == EV_KEY]
            if keys:
                cmd = ["ydotool", "key"] + keys
        if cmd:
            subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True

    # -- the vocabulary the app speaks
    def move(self, dx, dy):
        dx, dy = _clamp(dx, 2000), _clamp(dy, 2000)
        if dx or dy:
            self._emit([(EV_REL, REL_X, dx), (EV_REL, REL_Y, dy)])

    def scroll(self, dy, dx=0):
        """dy/dx in hi-res units (120 = one notch); positive dy scrolls content up."""
        # Real mice send hi-res units every event and a legacy notch each time
        # 120 of them add up; a device without hi-res bits just drops those.
        ev = []
        dy, dx = _clamp(dy, 2400), _clamp(dx, 2400)
        if dy:
            ev.append((EV_REL, REL_WHEEL_HI_RES, dy))
            self.acc_y += dy
            notches = int(self.acc_y / 120)
            if notches:
                self.acc_y -= notches * 120
                ev.append((EV_REL, REL_WHEEL, notches))
        if dx:
            ev.append((EV_REL, REL_HWHEEL_HI_RES, dx))
            self.acc_x += dx
            notches = int(self.acc_x / 120)
            if notches:
                self.acc_x -= notches * 120
                ev.append((EV_REL, REL_HWHEEL, notches))
        if ev:
            self._emit(ev)

    def button(self, name, state):
        code = BTN.get(name)
        if code is None:
            return
        if state in ("down", "click"):
            self._emit([(EV_KEY, code, 1)])
            self.held.add(code)
        if state in ("up", "click"):
            self._emit([(EV_KEY, code, 0)])
            self.held.discard(code)

    def key(self, name, mods=()):
        code = KEYS.get(name)
        if code is None:
            return False
        mod_codes = [KEYS[m] for m in mods if m in MODS]
        self._emit([(EV_KEY, c, 1) for c in mod_codes] + [(EV_KEY, code, 1)])
        self._emit([(EV_KEY, code, 0)] + [(EV_KEY, c, 0) for c in reversed(mod_codes)])
        return True

    def type_text(self, text):
        text = text[:500]
        if not text:
            return
        if shutil.which("wtype") and os.environ.get("WAYLAND_DISPLAY"):
            cmd = ["wtype", "--", text]
        elif shutil.which("ydotool"):
            cmd = ["ydotool", "type", "--", text]
        else:
            return
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         env={**os.environ, "YDOTOOL_SOCKET": self.path or f"/run/user/{os.getuid()}/.ydotool_socket"})

    def release_all(self):
        """A dropped connection must never leave a button or key stuck down."""
        for code in list(self.held):
            self._emit([(EV_KEY, code, 0)])
        self.held.clear()


def _clamp(v, lim):
    try:
        v = int(v)
    except (TypeError, ValueError):
        return 0
    return max(-lim, min(lim, v))


INJECTOR = Injector()


# ---------------------------------------------------------------- websocket

def accept_key(key):
    return base64.b64encode(hashlib.sha1(key.encode() + WS_GUID).digest()).decode()


def _read_exact(f, n):
    buf = b""
    while len(buf) < n:
        chunk = f.read(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf


def read_frame(f):
    """Returns (opcode, payload). Client frames are always masked."""
    b1, b2 = _read_exact(f, 2)
    opcode = b1 & 0x0F
    masked = b2 & 0x80
    n = b2 & 0x7F
    if n == 126:
        n = struct.unpack(">H", _read_exact(f, 2))[0]
    elif n == 127:
        n = struct.unpack(">Q", _read_exact(f, 8))[0]
    if n > MAX_FRAME or not masked:
        raise ConnectionError("bad frame")
    mask = _read_exact(f, 4)
    data = bytearray(_read_exact(f, n))
    for i in range(n):
        data[i] ^= mask[i % 4]
    return opcode, bytes(data)


def write_frame(sock, opcode, payload=b""):
    n = len(payload)
    if n < 126:
        head = struct.pack(">BB", 0x80 | opcode, n)
    elif n < 65536:
        head = struct.pack(">BBH", 0x80 | opcode, 126, n)
    else:
        head = struct.pack(">BBQ", 0x80 | opcode, 127, n)
    sock.sendall(head + payload)


def serve(handler, allowed):
    """Runs one session on an upgraded connection. `allowed()` is re-checked
    for every message so the kill switch cuts a live session immediately."""
    sock = handler.connection
    sock.settimeout(IDLE_TIMEOUT)
    f = handler.rfile
    hello = {"t": "hello", "inject": INJECTOR.available(),
             "wtype": bool(shutil.which("wtype")), "keys": sorted(KEYS)}
    write_frame(sock, 0x1, json.dumps(hello).encode())
    counts = {}
    try:
        while True:
            opcode, payload = read_frame(f)
            if opcode == 0x8:
                write_frame(sock, 0x8, payload[:2])
                break
            if opcode == 0x9:
                write_frame(sock, 0xA, payload)
                continue
            if opcode != 0x1:
                continue
            if not allowed():
                write_frame(sock, 0x8, struct.pack(">H", 1008) + b"input turned off")
                break
            try:
                msgs = json.loads(payload)
            except ValueError:
                continue
            for m in msgs if isinstance(msgs, list) else [msgs]:
                if isinstance(m, dict):
                    kind = handle(m)
                    if kind:
                        counts[kind] = counts.get(kind, 0) + 1
    except (ConnectionError, OSError, socket.timeout):
        pass
    finally:
        INJECTOR.release_all()
    return counts


def handle(m):
    t = m.get("t")
    if t == "m":
        INJECTOR.move(m.get("dx", 0), m.get("dy", 0))
        return "move"
    if t == "s":
        INJECTOR.scroll(m.get("dy", 0), m.get("dx", 0))
        return "scroll"
    if t == "b":
        INJECTOR.button(str(m.get("b", "left")), str(m.get("s", "click")))
        return "click"
    if t == "k":
        mods = [str(x) for x in (m.get("mods") or [])][:4]
        INJECTOR.key(str(m.get("k", "")).lower(), mods)
        return "key"
    if t == "txt":
        INJECTOR.type_text(str(m.get("s", "")))
        return "text"
    if t == "g":
        cmd = GESTURES.get(str(m.get("g", "")))
        if cmd:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return "gesture"
        if m.get("g") == "overview":
            mgr = os.path.expanduser("~/.config/hypr/scripts/qs_manager.sh")
            subprocess.Popen(["bash", mgr, "toggle", "workspaces"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return "gesture"
    return None
