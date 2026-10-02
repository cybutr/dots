#!/usr/bin/env python3
"""Laptop screen to the phone over WebRTC.

qs_remote.py upgrades /api/v1/stream to a WebSocket and hands it to serve(),
which runs one `qs_stream.py worker` per session and relays signaling between
the socket and the worker's stdin/stdout as JSON lines. Only one session runs
at a time; a new one replaces the old.

The worker captures and encodes with wf-recorder (wlr-screencopy, the same
path screenrec.sh uses) and GStreamer's webrtcbin only packetizes and sends.

  python3 qs_stream.py worker [--encoder auto|va|x264|nvenc]
"""
import glob
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time

LOG = "/tmp/qs_stream.log"
IDLE_TIMEOUT = 90
ANSWER_TIMEOUT = 20
CONNECT_TIMEOUT = 20
BITRATE = 6000
GOP = 120
KEYFRAME_GAP = 3
STARTUP_MS = 4000
WATCH_SECS = 2
SDP_MAX = 32 * 1024
# Both ends are always on the tailnet, so only tailnet addresses are gathered
# or accepted: no STUN/TURN, nothing about the session leaves the tailnet.
TAILNET = (ipaddress.ip_network("100.64.0.0/10"), ipaddress.ip_network("fd7a:115c:a1e0::/48"))
ENCODERS = ("va", "x264", "nvenc")
AUTO = ("va", "nvenc", "x264")
# Constrained baseline 4.1. libwebrtc assumes 3.1 when the offer names no
# level, which is too low for 1080p.
PROFILE_LEVEL = "42e029"
RTP_CAPS = ("application/x-rtp,media=video,encoding-name=H264,payload=96,clock-rate=90000,"
            f"packetization-mode=(string)1,profile-level-id=(string){PROFILE_LEVEL}")
CLIENT_TYPES = {"start", "answer", "ice", "stop"}
WORKER_TYPES = {"offer", "ice", "info", "state", "bye"}


def log(*a):
    print("[qs-stream]", *a, file=sys.stderr, flush=True)


def tailnet_ok(addr):
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return False
    return any(ip in n for n in TAILNET)


def candidate_ok(cand):
    parts = cand.removeprefix("a=").split()
    return len(parts) >= 8 and parts[2].lower() == "udp" and tailnet_ok(parts[4])


def tailnet_ips():
    try:
        links = json.loads(subprocess.run(["ip", "-j", "addr", "show", "dev", "tailscale0"], capture_output=True,
                                          text=True, timeout=3).stdout or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    return [a["local"] for link in links for a in link.get("addr_info") or [] if tailnet_ok(a.get("local", ""))]


def pin_to_tailnet(webrtcbin, Nice):
    """Restricts webrtcbin's ICE agent to the tailnet addresses; returns False
    if there are none."""
    import ctypes
    ice = webrtcbin.get_property("ice-agent")
    # webrtcbin never sinks its ICE object, so the first property read sinks
    # webrtcbin's own reference into the Python wrapper; give it back or the
    # agent is freed under webrtcbin as soon as the wrapper is collected.
    gobject = ctypes.CDLL("libgobject-2.0.so.0")
    gobject.g_object_ref.argtypes = [ctypes.c_void_p]
    gobject.g_object_ref.restype = ctypes.c_void_p
    gobject.g_object_ref(hash(ice))
    ice.set_property("ice-tcp", False)
    agent = ice.get_property("agent")
    added = 0
    for ip in tailnet_ips():
        a = Nice.Address()
        if a.set_from_string(ip):
            agent.add_local_address(a)
            added += 1
    return added > 0


def monitors():
    try:
        return json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True,
                                         timeout=3).stdout or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []


def pick_monitor(name=None):
    mons = [m for m in monitors() if isinstance(m, dict) and not m.get("disabled")]
    if name:
        return next((m for m in mons if m.get("name") == name), None)
    return next((m for m in mons if m.get("focused")), mons[0] if mons else None)


def geometry(m):
    """Pixel size the screen is actually shown at; odd transforms are 90/270 rotations."""
    w, h, t = int(m["width"]), int(m["height"]), int(m.get("transform") or 0)
    return (h, w, t) if t % 2 else (w, h, t)


def intel_render_node():
    for node in sorted(glob.glob("/sys/class/drm/renderD*")):
        try:
            with open(os.path.join(node, "device/vendor")) as f:
                if f.read().strip() == "0x8086":
                    return "/dev/dri/" + os.path.basename(node)
        except OSError:
            continue
    return None


def recorder_args(kind, kbps):
    # Pinned to match PROFILE_LEVEL in the SDP. Left alone, x264 and NVENC
    # derive 6.2 from wf-recorder's microsecond timebase.
    common = ["-b", "0", "-p", f"g={GOP}", "-p", f"b={kbps}k", "-p", "level=4.1"]
    if kind == "va":
        node = intel_render_node()
        if not node:
            return None
        return ["-c", "h264_vaapi", "-d", node, "-p", "profile=constrained_baseline", "-p", "rc_mode=CBR",
                "-p", "async_depth=1"] + common
    if kind == "x264":
        return ["-c", "libx264", "-x", "yuv420p", "-p", "preset=ultrafast", "-p", "tune=zerolatency",
                "-p", "profile=baseline"] + common
    if kind == "nvenc":
        # Only when VA fails: NVENC wakes the dGPU, which otherwise sleeps for
        # battery, while the iGPU's VA encoder does the same job zero-copy.
        return ["-c", "h264_nvenc", "-x", "yuv420p", "-p", "preset=p1", "-p", "tune=ull", "-p", "zerolatency=1",
                "-p", "profile=baseline", "-p", "rc=cbr"] + common
    return None


def recorder_env():
    # Hyprland exports LIBVA_DRIVER_NAME=nvidia for the dGPU; the VA encoder
    # has to run on the iGPU that Hyprland renders on, so its dmabufs import as-is.
    return {**os.environ, "LIBVA_DRIVER_NAME": "iHD"}


# ---------------------------------------------------------------- relay (runs inside qs_remote.py)

_active = {"proc": None}
_active_mu = threading.Lock()


def _stop(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(3)
    except subprocess.TimeoutExpired:
        proc.kill()


def serve(handler, allowed, read_frame, write_frame, encoder="auto"):
    """One signaling session on an upgraded connection; returns a summary for
    the audit log. `allowed()` is polled every second: the video runs over UDP,
    so a quiet socket must not keep it alive past the kill switch."""
    sock = handler.connection
    sock.settimeout(IDLE_TIMEOUT)
    with open(LOG, "a") as logf:
        proc = subprocess.Popen(["setpriv", "--pdeathsig", "TERM", sys.executable, os.path.abspath(__file__), "worker",
                                 "--encoder", encoder], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=logf,
                                text=True, bufsize=1)
    with _active_mu:
        old, _active["proc"] = _active["proc"], proc
    _stop(old)
    send_mu = threading.Lock()
    summary = {"encoder": "", "frames": 0, "reason": ""}
    done = threading.Event()

    def send(obj):
        with send_mu:
            write_frame(sock, 0x1, json.dumps(obj).encode())

    def close(code, reason):
        if done.is_set():
            return
        done.set()
        try:
            with send_mu:
                write_frame(sock, 0x8, code.to_bytes(2, "big") + reason.encode()[:100])
        except OSError:
            pass
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def pump():
        for line in proc.stdout:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if not isinstance(m, dict) or m.get("t") not in WORKER_TYPES:
                continue
            if m["t"] == "info":
                summary["encoder"] = m.get("encoder", "")
            if m["t"] == "bye":
                summary.update(frames=m.get("frames", 0), reason=m.get("reason", ""))
            try:
                send(m)
            except OSError:
                break
        close(1000, summary["reason"] or "stream ended")

    def watch():
        while not done.wait(1):
            if not allowed():
                summary["reason"] = "turned off"
                try:
                    send({"t": "bye", "reason": "turned off", "frames": 0})
                except OSError:
                    pass
                _stop(proc)
                close(1008, "stream turned off")

    threading.Thread(target=pump, daemon=True).start()
    threading.Thread(target=watch, daemon=True).start()
    try:
        while not done.is_set():
            opcode, payload = read_frame(handler.rfile)
            if opcode == 0x8:
                break
            if opcode == 0x9:
                with send_mu:
                    write_frame(sock, 0xA, payload)
                continue
            if opcode != 0x1:
                continue
            try:
                m = _clean(json.loads(payload))
            except ValueError:
                continue
            if m is not None:
                proc.stdin.write(json.dumps(m) + "\n")
                proc.stdin.flush()
    except (ConnectionError, OSError, ValueError, socket.timeout):
        pass
    finally:
        done.set()
        _stop(proc)
        with _active_mu:
            if _active["proc"] is proc:
                _active["proc"] = None
    return summary


def _clean(m):
    """Only the fields the worker reads, bounded."""
    if not isinstance(m, dict) or m.get("t") not in CLIENT_TYPES:
        return None
    t = m["t"]
    if t == "start":
        out = {"t": t}
        if isinstance(m.get("output"), str) and re.match(r"^[A-Za-z0-9_-]{1,32}$", m["output"]):
            out["output"] = m["output"]
        if isinstance(m.get("bitrate"), (int, float)):
            out["bitrate"] = int(max(500, min(20000, m["bitrate"])))
        return out
    if t == "answer":
        sdp = m.get("sdp")
        return {"t": t, "sdp": sdp} if isinstance(sdp, str) and 0 < len(sdp) <= SDP_MAX else None
    if t == "ice":
        cand, idx = m.get("candidate"), m.get("sdpMLineIndex", 0)
        if not isinstance(cand, str) or len(cand) > 512 or not isinstance(idx, int) or not 0 <= idx < 4:
            return None
        return {"t": t, "candidate": cand, "sdpMLineIndex": idx}
    return {"t": t}


# ---------------------------------------------------------------- worker (own process; GStreamer lives here)

class Worker:
    def __init__(self, encoder):
        import gi
        gi.require_version("Gst", "1.0")
        gi.require_version("GstWebRTC", "1.0")
        gi.require_version("GstSdp", "1.0")
        gi.require_version("Nice", "0.1")
        from gi.repository import GLib, Gst, GstSdp, GstWebRTC, Nice
        self.GLib, self.Gst, self.GstSdp, self.GstWebRTC, self.Nice = GLib, Gst, GstSdp, GstWebRTC, Nice
        Gst.init(None)
        self.encoder_pref = encoder
        self.loop = GLib.MainLoop()
        self.out_mu = threading.Lock()
        self.rec = None
        self.pipe = self.webrtc = None
        self.mon = self.geom = None
        self.kind = None
        self.order = []
        self.kbps = BITRATE
        self.captured = 0
        self.frames = 0
        self.capturing = self.answered = self.connected = self.ended = False
        self.last_key = 0.0

    def emit(self, obj):
        with self.out_mu:
            try:
                sys.stdout.write(json.dumps(obj) + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, ValueError):
                pass

    def end(self, reason):
        if self.ended:
            return False
        self.ended = True
        log(f"end: {reason} ({self.frames} frames, {self.kind or 'no'} encoder)")
        self.emit({"t": "bye", "reason": reason, "frames": self.frames})
        self.GLib.idle_add(self.loop.quit)
        return False

    # -- capture: wf-recorder writes H.264 into a pipe this process owns, so it
    # can be restarted (for a keyframe) without the pipeline noticing.
    def spawn_recorder(self, kind):
        args = recorder_args(kind, self.kbps)
        if args is None:
            return None
        rec = subprocess.Popen(["setpriv", "--pdeathsig", "TERM", "wf-recorder", "-y", "-o", self.mon["name"]] + args
                               + ["-m", "h264", "-f", f"pipe:{self.wfd}"],
                               pass_fds=(self.wfd,), env=recorder_env(), stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        threading.Thread(target=self.drain, args=(rec, kind), daemon=True).start()
        return rec

    @staticmethod
    def kill(rec):
        if rec.poll() is None:
            rec.send_signal(2)
            try:
                rec.wait(2)
            except subprocess.TimeoutExpired:
                rec.kill()

    @staticmethod
    def drain(rec, kind):
        for line in rec.stderr:
            if "rror" in line or "ailed" in line:
                log(f"wf-recorder ({kind}):", line.strip()[:200])

    def try_next(self):
        while self.order and not self.ended:
            kind = self.order.pop(0)
            rec = self.spawn_recorder(kind)
            if rec is not None:
                self.rec, self.kind = rec, kind
                self.watch_start(rec)
                return False
        self.end("no working encoder")
        return False

    def captured_size(self):
        caps = self.pipe.get_by_name("buf").get_static_pad("sink").get_current_caps()
        s = caps.get_structure(0) if caps is not None else None
        if s is None:
            return None
        ok_w, w = s.get_int("width")
        ok_h, h = s.get_int("height")
        return (w, h) if ok_w and ok_h else None

    def watch_start(self, rec):
        self.GLib.timeout_add(200, self.check_start, rec, self.captured, time.monotonic() + STARTUP_MS / 1000)

    def check_start(self, rec, before, deadline):
        if self.ended or rec is not self.rec:
            return False
        if self.captured <= before:
            if time.monotonic() < deadline and rec.poll() is None:
                return True
            log(f"encoder {self.kind} produced nothing")
            self.kill(rec)
            self.rec = None
            if self.capturing:
                return self.end("capture stopped")
            return self.try_next()
        size = self.captured_size()
        if size != self.geom[:2]:
            got = f"{size[0]}x{size[1]}" if size else "an unknown size"
            return self.end(f"capture is {got} but the screen is {self.geom[0]}x{self.geom[1]}")
        if not self.capturing:
            self.capturing = True
            self.emit({"t": "info", "output": self.mon["name"], "width": self.geom[0], "height": self.geom[1],
                       "transform": self.geom[2], "rotation": 0, "encoder": self.kind, "codec": "H264"})
        return False

    def keyframe(self):
        """webrtcbin asks for a keyframe on PLI/FIR; wf-recorder can't be told to
        make one, but a fresh recorder always opens with one."""
        now = time.monotonic()
        if not self.connected or not self.capturing or self.ended or now - self.last_key < KEYFRAME_GAP:
            return False
        self.last_key = now
        if self.rec is not None:
            self.kill(self.rec)
        self.rec = self.spawn_recorder(self.kind)
        if self.rec is None:
            return self.end("capture stopped")
        self.watch_start(self.rec)
        return False

    def watch(self):
        m = pick_monitor(self.mon["name"])
        if m is None or geometry(m) != self.geom:
            return self.end("display changed")
        if self.capturing and self.rec is not None and self.rec.poll() is not None:
            return self.end("capture stopped")
        return not self.ended

    # -- pipeline
    def build(self):
        Gst, GstWebRTC = self.Gst, self.GstWebRTC
        r, self.wfd = os.pipe()
        # webrtcbin holds buffers back until the peer connects; the leaky queue
        # sheds them instead of letting the pipe fill and stall wf-recorder,
        # and the restart on connect brings a fresh keyframe anyway.
        self.pipe = Gst.parse_launch(
            f"fdsrc fd={r} blocksize=1048576 do-timestamp=true ! "
            f"h264parse config-interval=-1 ! video/x-h264,stream-format=byte-stream,alignment=au ! "
            f"queue name=buf leaky=downstream max-size-buffers=30 max-size-bytes=0 max-size-time=0 ! "
            f"rtph264pay name=pay config-interval=-1 aggregate-mode=zero-latency ! {RTP_CAPS} ! "
            f"webrtcbin name=webrtc bundle-policy=max-bundle")
        self.webrtc = self.pipe.get_by_name("webrtc")
        if not pin_to_tailnet(self.webrtc, self.Nice):
            raise RuntimeError("no tailnet address on this laptop")
        tr = self.webrtc.emit("get-transceiver", 0)
        tr.set_property("direction", GstWebRTC.WebRTCRTPTransceiverDirection.SENDONLY)
        tr.set_property("do-nack", True)
        self.webrtc.connect("on-negotiation-needed", self.on_negotiation)
        self.webrtc.connect("on-ice-candidate", self.on_ice)
        self.webrtc.connect("notify::connection-state", self.on_state)
        self.pipe.get_by_name("buf").get_static_pad("sink").add_probe(Gst.PadProbeType.BUFFER, self.on_captured)
        pay = self.pipe.get_by_name("pay")
        pay.get_static_pad("sink").add_probe(Gst.PadProbeType.BUFFER, self.on_frame)
        pay.get_static_pad("sink").add_probe(Gst.PadProbeType.EVENT_UPSTREAM, self.on_upstream)
        bus = self.pipe.get_bus()
        bus.add_signal_watch()
        bus.connect("message::error", self.on_error)

    def on_captured(self, pad, info):
        self.captured += 1
        return self.Gst.PadProbeReturn.OK

    def on_frame(self, pad, info):
        if self.connected:
            self.frames += 1
        return self.Gst.PadProbeReturn.OK

    def on_upstream(self, pad, info):
        ev = info.get_event()
        s = ev.get_structure() if ev is not None else None
        if s is not None and s.get_name() == "GstForceKeyUnit":
            self.GLib.idle_add(self.keyframe)
        return self.Gst.PadProbeReturn.OK

    # -- signaling
    def on_negotiation(self, element):
        element.emit("create-offer", None, self.Gst.Promise.new_with_change_func(self.on_offer, element, None))

    def on_offer(self, promise, element, _):
        # The reply owns the offer; keep it referenced until webrtcbin has its copy.
        reply = promise.get_reply()
        offer = reply.get_value("offer") if reply else None
        if offer is None:
            self.GLib.idle_add(self.end, "couldn't create an offer")
            return
        element.emit("set-local-description", offer, self.Gst.Promise.new())
        self.emit({"t": "offer", "sdp": offer.sdp.as_text()})

    def on_ice(self, element, mline, cand):
        if candidate_ok(cand):
            self.emit({"t": "ice", "candidate": cand, "sdpMLineIndex": mline})

    def on_state(self, element, _):
        st = element.get_property("connection-state").value_nick
        self.GLib.idle_add(self.on_state_main, st)

    def on_state_main(self, st):
        self.emit({"t": "state", "state": st})
        if st == "connected" and not self.connected:
            self.connected = True
            self.last_key = 0.0
            self.keyframe()
        elif st in ("failed", "closed"):
            self.end(f"connection {st}")
        return False

    def on_message(self, m):
        t = m.get("t")
        if t == "answer" and not self.answered:
            ok, sdp = self.GstSdp.SDPMessage.new_from_text(m["sdp"])
            if ok != self.GstSdp.SDPResult.OK:
                return self.end("bad answer")
            self.answered = True
            ans = self.GstWebRTC.WebRTCSessionDescription.new(self.GstWebRTC.WebRTCSDPType.ANSWER, sdp)
            self.webrtc.emit("set-remote-description", ans, self.Gst.Promise.new())
        elif t == "ice":
            if m["candidate"] and candidate_ok(m["candidate"]):
                self.webrtc.emit("add-ice-candidate", m["sdpMLineIndex"], m["candidate"])
        elif t == "stop":
            self.end("stopped")
        return False

    def on_error(self, bus, msg):
        err, dbg = msg.parse_error()
        log("gst error:", err.message, (dbg or "")[:300])
        self.end("pipeline error")

    def deadline(self, flag, reason):
        if not getattr(self, flag):
            self.end(reason)
        return False

    def stdin_reader(self):
        for line in sys.stdin:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if isinstance(m, dict):
                self.GLib.idle_add(self.on_message, m)
        self.GLib.idle_add(self.end, "signaling closed")

    def run(self):
        start = None
        for line in sys.stdin:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if isinstance(m, dict) and m.get("t") in ("start", "stop"):
                start = m if m["t"] == "start" else None
                break
        if start is None:
            return
        self.mon = pick_monitor(start.get("output"))
        if self.mon is None:
            return self.end("no such screen")
        self.geom = geometry(self.mon)
        self.kbps = int(start.get("bitrate") or BITRATE)
        try:
            self.build()
        except Exception as e:
            log(f"setup failed: {type(e).__name__}: {e}")
            return self.end(str(e)[:160] if isinstance(e, RuntimeError) else "setup failed")
        self.order = list(AUTO if self.encoder_pref == "auto" else (self.encoder_pref,))
        threading.Thread(target=self.stdin_reader, daemon=True).start()
        self.pipe.set_state(self.Gst.State.PLAYING)
        self.GLib.idle_add(self.try_next)
        self.GLib.timeout_add_seconds(WATCH_SECS, self.watch)
        self.GLib.timeout_add_seconds(ANSWER_TIMEOUT, self.deadline, "answered", "no answer")
        self.GLib.timeout_add_seconds(ANSWER_TIMEOUT + CONNECT_TIMEOUT, self.deadline, "connected", "couldn't connect")
        try:
            self.loop.run()
        finally:
            self.shutdown()

    def shutdown(self):
        if self.rec is not None:
            self.kill(self.rec)
        if self.pipe is not None:
            self.pipe.set_state(self.Gst.State.NULL)


def main():
    args = sys.argv[1:]
    enc = args[args.index("--encoder") + 1] if "--encoder" in args[:-1] else "auto"
    if enc != "auto" and enc not in ENCODERS:
        enc = "auto"
    if args[:1] == ["worker"]:
        Worker(enc).run()
    else:
        print(__doc__.strip())


if __name__ == "__main__":
    main()
