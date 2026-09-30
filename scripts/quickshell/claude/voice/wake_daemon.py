#!/usr/bin/env python3
"""Always-on wake word listener. Streams the mic through openWakeWord; on a
hit it captures the following utterance via the STT server and drops it into
the agent's FIFO, then flips the resident dot to 'waiting' so the reply blinks.

Respects the mic mute state — if the default source is muted, it idles cheaply
instead of burning CPU on dead audio."""
import os, sys, json, time, subprocess
import numpy as np

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import stt_client

FIFO = "/tmp/qs_claude_in"
SUGGEST = "/tmp/qs_resident_suggestion"
WAKE_FLAG = "/tmp/qs_wake_active"        # presence = wake listening live (for UI)
LISTENING = "/tmp/qs_wake_listening"     # presence = capturing the command right now (for UI)
PIDFILE = "/tmp/qs_wake_daemon.pid"
QS_MANAGER = os.path.expanduser("~/.config/hypr/scripts/qs_manager.sh")
WAKE_MODEL = os.environ.get("QS_WAKE_MODEL", "kandor")
THRESHOLD = float(os.environ.get("QS_WAKE_THRESHOLD", "0.4"))
COOLDOWN = 1.2   # seconds after a wake before listening again — kills repeat-fire on the same utterance
RATE = 16000
CHUNK = 1280     # 80ms @ 16k, openWakeWord's expected frame
CMD_MIN_THRESH = 1700.0   # same floor as stt_server's fast_start path
CMD_WINDOW_S = 2.0        # give up if no speech starts this soon after the wake word
CMD_SILENCE_MS = 500
CMD_MAX_S = 15.0

# the wake phrase (and common STT mis-hearings of it) — stripped from the front
# of the transcript so only the actual command reaches the agent. If nothing is
# left after stripping, the user just said the wake word alone → ignore.
WAKE_TOKENS = ("yo kandor", "hey kandor", "okay kandor", "ok kandor",
               "jo kandor", "jokandör", "yokandor", "kandor", "kandör",
               "kandr", "candor", "condor", "kander")


def strip_wake(txt):
    low = txt.lower().strip(" ,.!?-–—")
    for t in WAKE_TOKENS:
        if low.startswith(t):
            return txt.strip()[len(t):].strip(" ,.!?-–—")
    if low in WAKE_TOKENS or len(low) < 3:
        return ""
    return txt.strip()


def log(*a):
    print("[wake]", *a, file=sys.stderr, flush=True)


def mic_muted():
    try:
        out = subprocess.run(["pactl", "get-source-mute", "@DEFAULT_SOURCE@"],
                             capture_output=True, text=True, timeout=2).stdout
        return "yes" in out
    except Exception:
        return False


def feed_agent(text):
    try:
        with open(FIFO, "w") as f:
            f.write(json.dumps({"text": "[voice] " + text}) + "\n")
    except Exception as e:
        log("fifo write failed:", e)


def nudge_reply(text):
    """Flip resident dot to 'waiting' so the reply lands as a blink."""
    try:
        payload = {"msg": "Voice: " + (text[:60]), "label": "heard",
                   "action_cmd": "", "ts": time.time()}
        with open(SUGGEST, "w") as f:
            json.dump(payload, f)
    except Exception:
        pass


def capture_command(proc):
    """Capture the command directly off the wake-listener's already-open mic —
    no teardown/restart, so there's zero dead-air gap right after the wake word
    (a fresh parec spawn + PulseAudio handshake was eating the opening syllables
    when the command was spoken in the same breath as the wake word)."""
    frame_ms = CHUNK / RATE * 1000
    silence_frames_needed = max(1, round(CMD_SILENCE_MS / frame_ms))
    pcm = bytearray()
    started = False
    silence_frames = 0
    start_t = time.time()
    speech_t = 0
    while True:
        raw = proc.stdout.read(CHUNK * 2)
        if len(raw) < CHUNK * 2:
            break
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32)
        energy = float(np.sqrt(np.mean(samples * samples))) if samples.size else 0.0
        speech = energy > CMD_MIN_THRESH
        if not started:
            if speech:
                started = True
                speech_t = time.time()
                pcm += raw
            elif time.time() - start_t > CMD_WINDOW_S:
                break
        else:
            pcm += raw
            silence_frames = 0 if speech else silence_frames + 1
            if silence_frames >= silence_frames_needed:
                break
            if time.time() - speech_t > CMD_MAX_S:
                break
    return bytes(pcm)


def open_quicktell_voice():
    """Pop the QuickTell voice widget for interactive input (same as the
    SUPER+ALT+G keybind). Uses 'open', not 'toggle' - safe to call even if
    it's already open, never accidentally closes it."""
    try:
        subprocess.Popen(["bash", QS_MANAGER, "open", "quicktell", "voice"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def close_quicktell_voice():
    try:
        subprocess.Popen(["bash", QS_MANAGER, "close"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def main():
    if os.path.exists(PIDFILE):
        try:
            os.kill(int(open(PIDFILE).read().strip()), 0)
            sys.exit(0)        # already running
        except (OSError, ValueError):
            pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    import openwakeword
    from openwakeword.model import Model
    import numpy as np
    custom_dir = os.path.join(BASE, "models")
    stock_dir = os.path.join(os.path.dirname(openwakeword.__file__), "resources", "models")
    candidates = [
        os.path.join(custom_dir, WAKE_MODEL + ("" if WAKE_MODEL.endswith(".onnx") else ".onnx")),
        os.path.join(stock_dir, WAKE_MODEL + ("" if WAKE_MODEL.endswith(".onnx") else "_v0.1.onnx")),
        os.path.join(stock_dir, "hey_jarvis_v0.1.onnx"),   # last-resort fallback until a custom model is trained
    ]
    model_path = next((p for p in candidates if os.path.exists(p)), candidates[-1])
    # openwakeword 0.6.x renamed the kwarg and needs an explicit onnx framework;
    # 0.4.x uses the old kwarg. Support both so the daemon runs on either venv.
    try:
        oww = Model(wakeword_models=[model_path], inference_framework="onnx")
    except TypeError:
        oww = Model(wakeword_model_paths=[model_path])
    log(f"wake model '{os.path.basename(model_path)}' ready, threshold {THRESHOLD}")

    open(WAKE_FLAG, "w").close()
    proc = None

    def open_mic():
        return subprocess.Popen(
            ["parec", "--format=s16le", f"--rate={RATE}", "--channels=1",
             "--latency-msec=20"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    try:
        while True:
            if mic_muted():
                if proc:
                    proc.terminate(); proc = None
                time.sleep(1.0)
                continue
            if proc is None:
                proc = open_mic()
                oww.reset()
            raw = proc.stdout.read(CHUNK * 2)
            if len(raw) < CHUNK * 2:
                proc.terminate(); proc = None
                continue
            samples = np.frombuffer(raw, dtype=np.int16)
            scores = oww.predict(samples)
            if any(v >= THRESHOLD for v in scores.values()):
                log("wake!", {k: round(v, 2) for k, v in scores.items()})
                open_quicktell_voice()               # instant visual ack, before capture/STT
                pcm = capture_command(proc)         # same mic stream, no restart gap
                res = stt_client.transcribe_pcm(pcm) if pcm else {"text": ""}
                cmd = strip_wake((res.get("text") or "").strip())
                if cmd:
                    # command spoken right after the wake word → interpret it and
                    # reply as a desktop notification (agent handles the [voice] tag).
                    # Close the widget we popped for the ack - hands-free flow doesn't need it.
                    log("heard:", cmd, "(", res.get("lang"), ")")
                    close_quicktell_voice()
                    feed_agent(cmd)
                    nudge_reply(cmd)
                else:
                    log("wake only → quicktell voice already open")
                oww.reset()
                time.sleep(COOLDOWN)   # don't re-trigger on the residual wake-word audio
    finally:
        for f in (WAKE_FLAG, PIDFILE):
            if os.path.exists(f):
                os.unlink(f)
        if proc:
            proc.terminate()


if __name__ == "__main__":
    main()
