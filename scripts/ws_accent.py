#!/usr/bin/env python3
import os, sys, json, time, socket, glob, fcntl, subprocess

HOME = os.path.expanduser("~")
SETTINGS = f"{HOME}/.config/hypr/settings.json"
SMARTWS = f"{HOME}/.config/hypr/smartws/rules.json"
LOCK = "/tmp/qs_ws_accent.lock"
PULSE_SESSION = "/tmp/qs_border_pulse.session"
PULSE_ORIG = "/tmp/qs_border_pulse.orig"
BASE_FALLBACK = ("9ccbfb", "9ccbfb")

PALETTE = {
    1: ("89b4fa", "b4befe"),
    2: ("cba6f7", "f5c2e7"),
    3: ("f38ba8", "fab387"),
    4: ("a6e3a1", "94e2d5"),
    5: ("f9e2af", "fab387"),
    6: ("89dceb", "74c7ec"),
    7: ("f5c2e7", "cba6f7"),
    8: ("fab387", "f38ba8"),
    9: ("94e2d5", "89b4fa"),
    10: ("b4befe", "cba6f7"),
}
SPEEDS = {"fast": 0.15, "normal": 0.25, "slow": 0.45}
STEPS = 6


def hyprctl(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return ""


def settings():
    try:
        with open(SETTINGS) as f:
            return json.load(f)
    except Exception:
        return {}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def fmt(c1, c2):
    return "rgba(%02x%02x%02xff) rgba(%02x%02x%02xff) 45deg" % (*c1, *c2)


def raw(c1, c2):
    return "ff%02x%02x%02x ff%02x%02x%02x 45deg" % (*c1, *c2)


def base_colors():
    try:
        with open(f"{HOME}/.config/hypr/colors.conf") as f:
            for line in f:
                if line.startswith("$active_border"):
                    v = line.split("rgba(")[1][:6]
                    return hex_rgb(v), hex_rgb(v)
    except Exception:
        pass
    return hex_rgb(BASE_FALLBACK[0]), hex_rgb(BASE_FALLBACK[1])


def smartws_color(ws):
    try:
        with open(SMARTWS) as f:
            d = json.load(f)
    except Exception:
        return None
    node = d.get("workspaces", d) if isinstance(d, dict) else {}
    ent = node.get(str(ws)) if isinstance(node, dict) else None
    if isinstance(ent, dict):
        for k in ("color", "accent", "hex"):
            v = ent.get(k)
            if isinstance(v, str) and len(v.lstrip("#")) == 6:
                c = hex_rgb(v)
                return c, lerp(c, (255, 255, 255), 0.25)
    return None


def target_for(ws, mode):
    if mode == "off":
        return base_colors()
    if mode == "smartws":
        t = smartws_color(ws)
        if t:
            return t
    p = PALETTE.get((ws - 1) % 10 + 1)
    return hex_rgb(p[0]), hex_rgb(p[1])


class State:
    cur = None


def apply(c1, c2):
    State.cur = (c1, c2)
    if os.path.isdir(PULSE_SESSION):
        try:
            with open(PULSE_ORIG, "w") as f:
                f.write(raw(c1, c2))
        except OSError:
            pass
        return
    hyprctl("keyword", "general:col.active_border", fmt(c1, c2))


def fade_to(t1, t2, dur):
    start = State.cur or base_colors()
    if dur <= 0.02 or start == (t1, t2):
        apply(t1, t2)
        return
    for i in range(1, STEPS + 1):
        k = i / STEPS
        apply(lerp(start[0], t1, k), lerp(start[1], t2, k))
        if i < STEPS:
            time.sleep(dur / STEPS)


def current_ws():
    try:
        return int(json.loads(hyprctl("activeworkspace", "-j")).get("id", 1))
    except Exception:
        return 1


def socket_path():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    rd = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if sig:
        p = f"{rd}/hypr/{sig}/.socket2.sock"
        if os.path.exists(p):
            return p
    c = sorted(glob.glob(f"{rd}/hypr/*/.socket2.sock"), key=os.path.getmtime)
    return c[-1] if c else None


def go(ws):
    s = settings()
    mode = s.get("hyprPolishWsAccent", "palette")
    dur = SPEEDS.get(s.get("hyprPolishWsAccentSpeed", "normal"), 0.25)
    t1, t2 = target_for(ws, mode)
    fade_to(t1, t2, dur)


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    last_mode = None
    ws = current_ws()
    go(ws)
    while True:
        p = socket_path()
        if not p:
            time.sleep(3)
            continue
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(p)
            s.settimeout(2.0)
            buf = b""
            while True:
                try:
                    chunk = s.recv(4096)
                except socket.timeout:
                    mode = settings().get("hyprPolishWsAccent", "palette")
                    if mode != last_mode:
                        last_mode = mode
                        go(ws)
                    continue
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    ev = line.decode(errors="replace")
                    if ev.startswith("workspacev2>>"):
                        try:
                            ws = int(ev.split(">>", 1)[1].split(",", 1)[0])
                        except ValueError:
                            continue
                        go(ws)
        except OSError:
            time.sleep(2)
        finally:
            try:
                s.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
