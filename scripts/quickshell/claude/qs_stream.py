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
import select
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
WATCH_SECS = 2
SDP_MAX = 32 * 1024
# Both ends are always on the tailnet, so only tailnet addresses are gathered
# or accepted: no STUN/TURN, nothing about the session leaves the tailnet.
TAILNET = (ipaddress.ip_network("100.64.0.0/10"), ipaddress.ip_network("fd7a:115c:a1e0::/48"))
ENCODERS = ("va", "x264", "nvenc")
AUTO = ("va", "x264")
RTP_CAPS = "application/x-rtp,media=video,encoding-name=H264,payload=96,clock-rate=90000"
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
    common = ["-b", "0", "-p", f"g={GOP}", "-p", f"b={kbps}k"]
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
        # Opt-in only: NVENC wakes the dGPU, which otherwise sleeps for battery,
        # and the iGPU's VA encoder does the same job zero-copy.
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
        self.rec_mu = threading.Lock()
        self.pipe = self.webrtc = None
        self.mon = self.geom = None
        self.kind = None
        self.kbps = BITRATE
        self.frames = 0
        self.answered = self.connected = self.ended = False
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
        log(f"end: {reason} ({self.frames} frames)")
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
        size = None
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and size is None:
            if not select.select([rec.stderr], [], [], 0.5)[0]:
                if rec.poll() is not None:
                    break
                continue
            line = rec.stderr.readline()
            if not line:
                break
            m = re.search(r"Stream #0:0: Video: .*?(\d{2,5})x(\d{2,5})", line)
            if m:
                size = (int(m.group(1)), int(m.group(2)))
        if size is None:
            self.kill(rec)
            log(f"encoder {kind} didn't start")
            return None
        threading.Thread(target=self.drain, args=(rec,), daemon=True).start()
        if size != self.geom[:2]:
            self.kill(rec)
            raise RuntimeError(f"capture is {size[0]}x{size[1]} but the screen is {self.geom[0]}x{self.geom[1]}")
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
    def drain(rec):
        for line in rec.stderr:
            if "rror" in line:
                log("wf-recorder:", line.strip()[:200])

    def start_capture(self):
        order = AUTO if self.encoder_pref == "auto" else (self.encoder_pref,)
        for kind in order:
            rec = self.spawn_recorder(kind)
            if rec is not None:
                self.rec, self.kind = rec, kind
                self.emit({"t": "info", "output": self.mon["name"], "width": self.geom[0], "height": self.geom[1],
                           "transform": self.geom[2], "rotation": 0, "encoder": kind, "codec": "H264"})
                return True
        return False

    def keyframe(self):
        """webrtcbin asks for a keyframe on PLI/FIR; wf-recorder can't be told to
        make one, but a fresh recorder always opens with one."""
        now = time.monotonic()
        if not self.connected or now - self.last_key < KEYFRAME_GAP:
            return False
        self.last_key = now
        with self.rec_mu:
            old = self.rec
            if old is not None:
                self.kill(old)
            try:
                self.rec = self.spawn_recorder(self.kind)
            except RuntimeError as e:
                return self.end(str(e))
        if self.rec is None:
            self.end("capture stopped")
        return False

    def watch(self):
        m = pick_monitor(self.mon["name"])
        if m is None or geometry(m) != self.geom:
            return self.end("display changed")
        with self.rec_mu:
            if self.connected and self.rec is not None and self.rec.poll() is not None:
                return self.end("capture stopped")
        return not self.ended

    # -- pipeline
    def build(self):
        Gst, GstWebRTC = self.Gst, self.GstWebRTC
        r, self.wfd = os.pipe()
        self.pipe = Gst.parse_launch(
            f"fdsrc name=src fd={r} blocksize=1048576 do-timestamp=true ! "
            f"h264parse config-interval=-1 ! video/x-h264,stream-format=byte-stream,alignment=au ! "
            f"rtph264pay name=pay config-interval=-1 aggregate-mode=zero-latency ! {RTP_CAPS} ! "
            f"webrtcbin name=webrtc bundle-policy=max-bundle")
        self.webrtc = self.pipe.get_by_name("webrtc")
        ice = self.webrtc.get_property("ice-agent")
        ice.set_property("ice-tcp", False)
        ips = tailnet_ips()
        if not ips:
            raise RuntimeError("no tailnet address on this laptop")
        agent = ice.get_property("agent")
        for ip in ips:
            a = self.Nice.Address()
            if a.set_from_string(ip):
                agent.add_local_address(a)
        tr = self.webrtc.emit("get-transceiver", 0)
        tr.set_property("direction", GstWebRTC.WebRTCRTPTransceiverDirection.SENDONLY)
        tr.set_property("do-nack", True)
        self.webrtc.connect("on-negotiation-needed", self.on_negotiation)
        self.webrtc.connect("on-ice-candidate", self.on_ice)
        self.webrtc.connect("notify::connection-state", self.on_state)
        pay = self.pipe.get_by_name("pay")
        pay.get_static_pad("sink").add_probe(Gst.PadProbeType.BUFFER, self.on_frame)
        pay.get_static_pad("sink").add_probe(Gst.PadProbeType.EVENT_UPSTREAM, self.on_upstream)
        bus = self.pipe.get_bus()
        bus.add_signal_watch()
        bus.connect("message::error", self.on_error)

    def on_frame(self, pad, info):
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
        self.pipe.set_state(self.Gst.State.PLAYING)
        try:
            ok = self.start_capture()
        except RuntimeError as e:
            ok = not self.end(str(e))
        if not ok:
            self.end("no working encoder")
            self.shutdown()
            return
        threading.Thread(target=self.stdin_reader, daemon=True).start()
        self.GLib.timeout_add_seconds(WATCH_SECS, self.watch)
        self.GLib.timeout_add_seconds(ANSWER_TIMEOUT, self.deadline, "answered", "no answer")
        self.GLib.timeout_add_seconds(ANSWER_TIMEOUT + CONNECT_TIMEOUT, self.deadline, "connected", "couldn't connect")
        try:
            self.loop.run()
        finally:
            self.shutdown()

    def shutdown(self):
        with self.rec_mu:
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
