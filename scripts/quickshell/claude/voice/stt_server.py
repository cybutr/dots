#!/usr/bin/env python3
"""Warm STT server. Holds faster-whisper in VRAM, captures mic via parec,
endpoints with an RMS energy detector, returns transcript over a unix socket.
One model load, many fast listens. Multilingual (Czech + English auto-detected)."""
import os, sys, json, socket, subprocess, threading, time, signal

SOCK = "/run/user/%d/qs_stt.sock" % os.getuid()
MODEL = os.environ.get("QS_STT_MODEL", "medium")   # medium: meaningfully better Czech accuracy than small, still fits the 4GB card int8_float16; falls back to cpu int8 automatically if VRAM is tight
DEVICE = os.environ.get("QS_STT_DEVICE", "cuda")
COMPUTE = os.environ.get("QS_STT_COMPUTE", "int8_float16")
RATE = 16000
FRAME_MS = 30
FRAME_BYTES = int(RATE * FRAME_MS / 1000) * 2     # s16le mono
SILENCE_HANG_MS = 500     # stop after this much trailing silence
MAX_UTTER_S = 15
START_WINDOW_S = 8        # give up if no speech starts within this
SKIP_FRAMES = 10          # ~300ms parec warmup (zero blocks) — discard
CAL_FRAMES = 20           # ~600ms ambient calibration window
PREROLL_FRAMES = 8        # ~240ms kept before trigger so first syllable survives
START_FRAMES = 3          # ~90ms sustained over threshold → real speech
MIN_THRESH = 1700.0       # absolute floor; below this is always ambient
FLOOR_MULT = 2.2          # speech must beat ambient floor by this factor

_model = None
_model_lock = threading.Lock()
_listen_lock = threading.Lock()   # mic is a single resource


def log(*a):
    print("[stt]", *a, file=sys.stderr, flush=True)


def get_model():
    global _model
    with _model_lock:
        if _model is None:
            from faster_whisper import WhisperModel
            log(f"loading {MODEL} on {DEVICE}/{COMPUTE} ...")
            t = time.time()
            try:
                _model = WhisperModel(MODEL, device=DEVICE, compute_type=COMPUTE)
            except Exception as e:
                log(f"cuda load failed ({e}); falling back to cpu/int8")
                _model = WhisperModel(MODEL, device="cpu", compute_type="int8")
            log(f"model ready in {time.time()-t:.1f}s")
    return _model


def _rms(frame_bytes):
    import numpy as np
    a = np.frombuffer(frame_bytes, dtype=np.int16).astype(np.float32)
    if a.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(a * a)))


def capture_utterance(source=None, timeout=START_WINDOW_S, fast_start=False):
    """Record from mic until trailing silence, using an energy (RMS) endpointer.
    Calibrates the noise floor from the opening frames, then waits for speech and
    stops once it drops back to ambient. Returns raw s16le PCM bytes or b''.

    fast_start skips the ~600ms ambient calibration (used right after a wake-word
    trigger, where speech may already be underway and calibration would otherwise
    eat the opening syllables and skew the floor)."""
    cmd = ["parec", "--format=s16le", f"--rate={RATE}", "--channels=1"]
    if source:
        cmd += [f"--device={source}"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    pcm = bytearray()
    from collections import deque
    preroll = deque(maxlen=PREROLL_FRAMES)   # keep run-up so first syllable isn't clipped
    started = False
    silence_ms = 0
    voiced_run = 0
    start_t = time.time()
    speech_t = 0
    floor = MIN_THRESH if fast_start else None
    floor_frames = []
    seen = 0
    peak = 0.0
    try:
        while True:
            frame = proc.stdout.read(FRAME_BYTES)
            if len(frame) < FRAME_BYTES:
                break
            energy = _rms(frame)
            seen += 1

            if floor is None:
                if seen <= SKIP_FRAMES:
                    continue
                floor_frames.append(energy)
                if len(floor_frames) >= CAL_FRAMES:
                    s = sorted(floor_frames)
                    floor = s[int(len(s) * 0.75)]      # p75 of ambient
                    start_t = time.time()              # only start the no-speech clock now
                continue

            thresh = MIN_THRESH if fast_start else max(MIN_THRESH, floor * FLOOR_MULT)
            speech = energy > thresh
            if not started and energy > peak:
                peak = energy

            if not started:
                preroll.append(frame)
                if speech:
                    voiced_run += 1
                    if voiced_run >= START_FRAMES:
                        started = True
                        speech_t = time.time()
                        for f in preroll:            # prepend the run-up
                            pcm += f
                else:
                    voiced_run = 0
                    if time.time() - start_t > timeout:
                        break                    # nobody spoke
            else:
                pcm += frame
                silence_ms = 0 if speech else silence_ms + FRAME_MS
                if silence_ms >= SILENCE_HANG_MS:
                    break
                if time.time() - speech_t > MAX_UTTER_S:
                    break
    finally:
        proc.terminate()
        try: proc.wait(timeout=1)
        except Exception: proc.kill()
    dur = len(pcm) / 2 / RATE
    log(f"capture: floor={floor or 0:.0f} thresh={(max(MIN_THRESH,(floor or 0)*FLOOR_MULT)):.0f} "
        f"peak={peak:.0f} started={started} dur={dur:.1f}s")
    return bytes(pcm) if started else b""


def transcribe(pcm, language=None):
    import numpy as np
    if not pcm:
        return {"text": "", "lang": "", "ok": True, "empty": True}
    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
    model = get_model()
    segments, info = model.transcribe(audio, language=language, beam_size=2,
                                      vad_filter=False, condition_on_previous_text=False)
    segs = list(segments)
    text = " ".join(s.text.strip() for s in segs).strip()
    # confidence: mean avg_logprob across segments (closer to 0 = better; < -1 = shaky)
    logp = [s.avg_logprob for s in segs if s.avg_logprob is not None]
    conf = sum(logp) / len(logp) if logp else -2.0
    nosp = max((s.no_speech_prob for s in segs), default=1.0)
    # autosend if the model is confident AND it's a real, complete-ish utterance
    words = len(text.split())
    autosend = bool(text) and conf > -0.55 and nosp < 0.5 and words >= 2 \
        and text[-1] not in ",-–—" and not text.endswith("...")
    return {"text": text, "lang": info.language, "ok": True,
            "conf": round(conf, 3), "no_speech": round(nosp, 3), "autosend": autosend}


def handle_cmd(req):
    cmd = req.get("cmd", "listen")
    if cmd == "ping":
        return {"ok": True, "ready": _model is not None, "model": MODEL}
    if cmd == "warm":
        get_model()
        return {"ok": True, "ready": True}
    if cmd == "listen":
        with _listen_lock:
            lang = req.get("language") or None     # None = auto (cs/en/...)
            tmo = float(req.get("timeout", START_WINDOW_S))
            pcm = capture_utterance(req.get("source"), tmo, fast_start=bool(req.get("fast_start")))
            return transcribe(pcm, lang)
    return {"ok": False, "error": f"unknown cmd {cmd}"}


def handle_transcribe_pcm(req, pcm):
    """Transcribe PCM captured by a caller's own mic stream (e.g. wake_daemon,
    which keeps its mic open across the wake trigger to avoid a restart gap)."""
    lang = req.get("language") or None
    return transcribe(pcm, lang)


def serve():
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    os.chmod(SOCK, 0o600)
    srv.listen(8)
    log(f"listening on {SOCK}")
    threading.Thread(target=get_model, daemon=True).start()   # warm now

    def client(conn):
        try:
            conn.settimeout(60)
            data = b""
            while b"\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    return
                data += chunk
            line, rest = data.split(b"\n", 1)
            req = json.loads(line.decode())
            if req.get("cmd") == "transcribe_pcm":
                need = int(req.get("bytes", 0))
                buf = bytearray(rest)
                while len(buf) < need:
                    chunk = conn.recv(min(65536, need - len(buf)))
                    if not chunk:
                        break
                    buf += chunk
                resp = handle_transcribe_pcm(req, bytes(buf[:need]))
            else:
                resp = handle_cmd(req)
        except Exception as e:
            resp = {"ok": False, "error": str(e)}
        try:
            conn.sendall((json.dumps(resp) + "\n").encode())
        except Exception:
            pass
        finally:
            conn.close()

    while True:
        conn, _ = srv.accept()
        threading.Thread(target=client, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    serve()
