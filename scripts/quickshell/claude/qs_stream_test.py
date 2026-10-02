#!/usr/bin/env python3
"""End-to-end check for /api/v1/stream: signals like the phone will, receives
the WebRTC video, decodes it and reports frames, size and orientation.

  python3 qs_stream_test.py [--url URL] [--seconds N] [--login LOGIN] [--save PNG]

--url defaults to the local qs-remote; --login fakes the Tailscale identity
header, which only `tailscale serve` adds for real. Exit code 0 = pass.
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstWebRTC", "1.0")
gi.require_version("GstSdp", "1.0")
gi.require_version("Nice", "0.1")
from gi.repository import GLib, Gst, GstSdp, GstWebRTC, Nice  # noqa: E402
from websockets.sync.client import connect  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qs_stream import candidate_ok, geometry, pick_monitor, pin_to_tailnet  # noqa: E402

TOKEN_FILE = os.path.expanduser("~/.local/state/qs-remote/token")


class Client:
    def __init__(self, ws, seconds, save):
        self.ws = ws
        self.seconds = seconds
        self.save = save
        self.loop = GLib.MainLoop()
        self.frames = 0
        self.sizes = set()
        self.first_at = None
        self.info = {}
        self.bye = None
        self.states = []
        self.cands = []
        self.sample = None
        self.snap = None
        self.send_mu = threading.Lock()
        self.pipe = Gst.Pipeline()
        self.webrtc = Gst.ElementFactory.make("webrtcbin")
        self.webrtc.set_property("bundle-policy", GstWebRTC.WebRTCBundlePolicy.MAX_BUNDLE)
        self.pipe.add(self.webrtc)
        pin_to_tailnet(self.webrtc, Nice)
        self.webrtc.connect("on-ice-candidate", self.on_ice)
        self.webrtc.connect("pad-added", self.on_pad)
        self.webrtc.connect("notify::connection-state",
                            lambda e, _: self.states.append(e.get_property("connection-state").value_nick))

    def send(self, obj):
        with self.send_mu:
            self.ws.send(json.dumps(obj))

    def on_ice(self, _, mline, cand):
        if candidate_ok(cand):
            self.send({"t": "ice", "candidate": cand, "sdpMLineIndex": mline})

    def on_pad(self, _, pad):
        if pad.direction != Gst.PadDirection.SRC:
            return
        # Software decode on purpose: decodebin would pick nvh264dec and wake the dGPU.
        dec = Gst.parse_bin_from_description(
            "queue ! rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! video/x-raw,format=RGB ! "
            "appsink name=sink emit-signals=true sync=false max-buffers=2 drop=true", True)
        self.pipe.add(dec)
        dec.sync_state_with_parent()
        pad.link(dec.get_static_pad("sink"))
        dec.get_by_name("sink").connect("new-sample", self.on_sample)

    def on_sample(self, sink):
        sample = sink.emit("pull-sample")
        s = sample.get_caps().get_structure(0)
        w, h = s.get_value("width"), s.get_value("height")
        self.frames += 1
        self.sizes.add((w, h))
        if self.first_at is None:
            self.first_at = time.monotonic()
        self.sample = sample
        if self.frames <= 3 or self.frames % 30 == 0:
            print(f"received frame {self.frames}, {w}x{h}", flush=True)
        return Gst.FlowReturn.OK

    def on_message(self, m):
        t = m.get("t")
        if t == "info":
            self.info = m
            print("info:", json.dumps(m), flush=True)
        elif t == "offer":
            self.cands += [ln for ln in m["sdp"].splitlines() if ln.startswith("a=candidate")]
            ok, sdp = GstSdp.SDPMessage.new_from_text(m["sdp"])
            offer = GstWebRTC.WebRTCSessionDescription.new(GstWebRTC.WebRTCSDPType.OFFER, sdp)
            self.webrtc.emit("set-remote-description", offer, Gst.Promise.new_with_change_func(self.on_remote, None))
        elif t == "ice":
            if m.get("candidate"):
                self.cands.append(m["candidate"])
                self.webrtc.emit("add-ice-candidate", m.get("sdpMLineIndex", 0), m["candidate"])
        elif t == "state":
            print("laptop state:", m.get("state"), flush=True)
        elif t == "bye":
            self.bye = m
            print("bye:", json.dumps(m), flush=True)
            self.loop.quit()
        return False

    def on_remote(self, promise, _):
        self.webrtc.emit("create-answer", None, Gst.Promise.new_with_change_func(self.on_answer, None))

    def on_answer(self, promise, _):
        # The reply owns the answer; keep it referenced until webrtcbin has its copy.
        reply = promise.get_reply()
        answer = reply.get_value("answer") if reply else None
        if answer is None:
            print("couldn't create an answer", flush=True)
            GLib.idle_add(self.loop.quit)
            return
        self.webrtc.emit("set-local-description", answer, Gst.Promise.new())
        self.send({"t": "answer", "sdp": answer.sdp.as_text()})

    def reader(self):
        try:
            for raw in self.ws:
                GLib.idle_add(self.on_message, json.loads(raw))
        except Exception as e:
            print("socket closed:", type(e).__name__, flush=True)
        GLib.idle_add(self.loop.quit)

    def run(self):
        self.pipe.set_state(Gst.State.PLAYING)
        threading.Thread(target=self.reader, daemon=True).start()
        self.send({"t": "start"})
        GLib.timeout_add_seconds(self.seconds, self.finish)
        self.loop.run()
        self.pipe.set_state(Gst.State.NULL)

    def finish(self):
        self.snap = subprocess.run(["grim", "-t", "ppm", "-o", self.info.get("output", ""), "-"],
                                   capture_output=True).stdout
        try:
            self.send({"t": "stop"})
        except Exception:
            pass
        GLib.timeout_add(1500, self.loop.quit)
        return False


def orientation(sample, snap, path):
    """Compares a received frame against grim's view of the same screen under
    each flip/rotation; the untouched frame has to be the closest match."""
    import io

    import numpy as np
    from PIL import Image
    buf = sample.get_buffer()
    s = sample.get_caps().get_structure(0)
    w, h = s.get_value("width"), s.get_value("height")
    ok, info = buf.map(Gst.MapFlags.READ)
    stride = len(info.data) // h
    arr = np.frombuffer(info.data, np.uint8).reshape(h, stride)[:, :w * 3].reshape(h, w, 3).copy()
    buf.unmap(info)
    got = Image.fromarray(arr)
    if path:
        got.save(path)
    ref = Image.open(io.BytesIO(snap)).convert("RGB")
    small = (96, 54) if w >= h else (54, 96)
    g = np.asarray(got.convert("L").resize(small), float)
    r = np.asarray(ref.convert("L").resize(small), float)
    variants = {"as-is": g, "vflip": g[::-1], "hflip": g[:, ::-1], "rot180": g[::-1, ::-1]}
    scores = {k: float(np.abs(v - r).mean()) for k, v in variants.items()}
    return ref.size, scores


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="ws://127.0.0.1:8790/api/v1/stream")
    ap.add_argument("--seconds", type=int, default=10)
    ap.add_argument("--login", default="")
    ap.add_argument("--save", default="")
    a = ap.parse_args()
    Gst.init(None)
    with open(TOKEN_FILE) as f:
        headers = {"Authorization": "Bearer " + f.read().strip()}
    if a.login:
        headers["Tailscale-User-Login"] = a.login
    with connect(a.url, additional_headers=headers, open_timeout=10) as ws:
        c = Client(ws, a.seconds, a.save)
        c.run()
    secs = time.monotonic() - c.first_at if c.first_at else 0
    print(f"\nframes received: {c.frames} over {secs:.1f}s; sizes seen: {sorted(c.sizes)}")
    print(f"connection states: {' > '.join(dict.fromkeys(c.states))}")
    tailnet = bool(c.cands) and all(candidate_ok(x) for x in c.cands)
    print(f"laptop ICE candidates: {len(c.cands)}, {'all on the tailnet' if tailnet else 'NOT all on the tailnet'}")
    mon = pick_monitor(c.info.get("output"))
    want = geometry(mon)[:2] if mon else None
    passed = tailnet and c.frames > 0 and len(c.sizes) == 1 and next(iter(c.sizes)) == want
    print(f"screen is {want}, transform {mon.get('transform') if mon else '?'}; size check {'ok' if passed else 'FAILED'}")
    if c.sample is not None and c.snap:
        ref_size, scores = orientation(c.sample, c.snap, a.save)
        best = min(scores, key=scores.get)
        print(f"grim reference {ref_size}; mean abs diff per orientation: "
              + ", ".join(f"{k} {v:.1f}" for k, v in scores.items()))
        upright = best == "as-is" and tuple(ref_size) == want
        print(f"orientation check {'ok' if upright else 'FAILED'}")
        passed = passed and upright
    else:
        print("orientation check skipped (no frame to compare)")
        passed = False
    print("PASS" if passed else "FAIL")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
