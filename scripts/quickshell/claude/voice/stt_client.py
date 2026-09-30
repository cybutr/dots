#!/usr/bin/env python3
"""Tiny client for the STT server. Used by the MCP listen tool and the wake
daemon. Ensures the server is up, sends a request, returns the dict."""
import os, sys, json, socket, subprocess, time

SOCK = "/run/user/%d/qs_stt.sock" % os.getuid()
BASE = os.path.dirname(os.path.abspath(__file__))


def server_up():
    if not os.path.exists(SOCK):
        return False
    try:
        return request({"cmd": "ping"}, timeout=2).get("ok", False)
    except Exception:
        return False


def ensure_server():
    if server_up():
        return True
    subprocess.Popen(["bash", os.path.join(BASE, "stt.sh")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(30):
        time.sleep(0.5)
        if server_up():
            return True
    return False


def request(req, timeout=30):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(SOCK)
    s.sendall((json.dumps(req) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.split(b"\n", 1)[0].decode())


def listen(timeout=8, language=None, fast_start=False):
    if not ensure_server():
        return {"ok": False, "error": "stt server unavailable"}
    return request({"cmd": "listen", "timeout": timeout, "language": language,
                    "fast_start": fast_start}, timeout=timeout + 40)


def transcribe_pcm(pcm, language=None, timeout=30):
    """Send raw s16le mono 16kHz PCM captured by the caller's own mic stream
    (e.g. wake_daemon, which keeps its mic open across the wake trigger) —
    skips the server's own capture step entirely, no restart gap."""
    if not ensure_server():
        return {"ok": False, "error": "stt server unavailable"}
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(SOCK)
    header = json.dumps({"cmd": "transcribe_pcm", "language": language, "bytes": len(pcm)})
    s.sendall(header.encode() + b"\n" + pcm)
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.split(b"\n", 1)[0].decode())


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "ping":
        try:
            print(json.dumps(request({"cmd": "ping"}, timeout=2)))
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)}))
        sys.exit(0)
    # CLI: print transcript JSON (used by QuickTell voice mode)
    tmo = float(sys.argv[1]) if len(sys.argv) > 1 else 8
    lang = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
    print(json.dumps(listen(tmo, lang), ensure_ascii=False))
