#!/usr/bin/env python3
# Real per-band FFT spectrum stream of the default sink's monitor — the
# "fft" mediaVisualizerMode alternative to audio_level.py's single overall
# RMS scalar. Bins the spectrum into ~14 log-spaced frequency bands. Log
# spacing (not linear) is what makes this read as a real spectrum analyzer
# instead of a bass-only meter — most musical energy sits under 1kHz, so a
# linear split would starve every treble bar while a handful of bass bars
# max out.
#
# Runs as a PERSISTENT process (started once while "fft" mode is active,
# killed when it isn't) rather than one-shot-per-poll. A one-shot design
# was tried first and was real but felt choppy — measured ~0.5-0.7s wall
# time per invocation, almost all of it numpy import + interpreter startup
# (the actual capture window is only ~0.12s), which put a hard floor on
# poll rate no timer tuning could fix. Importing numpy once and keeping
# parec open removes that floor entirely: this streams a fresh 14-band
# line every EMIT_INTERVAL over a persistent stdout pipe (TopBar.qml reads
# it with a SplitParser, not a one-shot StdioCollector), matching the
# update rate of the "pulse" mode's per-frame animation.
#
# Perceptual + frequency-dependent gain (see the comment at the line that
# computes `level`) — measured live, without it treble bands (i=8-13) sat
# at 0.03-0.09 versus bass (i=0-3) swinging 0.15-0.77, visually reading as
# a dead flat line for most of the row even with the pipeline working.

import json
import os
import subprocess
import sys
import time
import numpy as np

SR = 22050
BANDS = 14
MIN_FREQ = 40
MAX_FREQ = 10000
WINDOW_SEC = 0.15
EMIT_INTERVAL = 0.1
SETTINGS_PATH = os.path.expanduser("~/.config/hypr/settings.json")
SETTINGS_REREAD_INTERVAL = 1.0  # settings.json is small, but no need to open it every 100ms


class IntensityReader:
    # Hot-reads the intensity slider from settings.json rather than taking it
    # as a launch argument — this process is long-lived (see module docstring),
    # so a launch argument would mean restarting audio capture on every drag
    # of the slider. Same settings.json-watching convention already used
    # throughout this rice, just polled here instead of inotify since this
    # script has no QML event loop to hang a watcher off of.
    def __init__(self):
        self.value = 1.0
        self.last_read = 0.0

    def get(self):
        now = time.monotonic()
        if now - self.last_read < SETTINGS_REREAD_INTERVAL:
            return self.value
        self.last_read = now
        try:
            with open(SETTINGS_PATH) as f:
                data = json.load(f)
            v = float(data.get("topBarFftIntensity", 1.0))
            self.value = max(0.3, min(3.0, v))
        except Exception:
            pass
        return self.value


def get_monitor_source():
    try:
        sink = subprocess.run(
            ["pactl", "get-default-sink"], capture_output=True, text=True, timeout=1
        ).stdout.strip()
        return f"{sink}.monitor" if sink else None
    except Exception:
        return None


def zeros():
    print(",".join(["0.0"] * BANDS))
    sys.stdout.flush()


def main():
    monitor = get_monitor_source()
    if not monitor:
        zeros()
        return

    frame_samples = int(SR * WINDOW_SEC)
    frame_bytes = frame_samples * 2  # s16le mono
    hann = np.hanning(frame_samples)
    nyquist = SR / 2.0 - 1
    edges = np.geomspace(MIN_FREQ, min(MAX_FREQ, nyquist), BANDS + 1)

    proc = subprocess.Popen(
        [
            "parec",
            f"--device={monitor}",
            "--format=s16le",
            f"--rate={SR}",
            "--channels=1",
            "--raw",
            "--latency-msec=30",
        ],
        stdout=subprocess.PIPE,
    )
    assert proc.stdout is not None

    buf = b""
    last_emit = 0.0
    intensity = IntensityReader()
    try:
        while True:
            chunk = proc.stdout.read(4096)
            if not chunk:
                break
            buf += chunk
            if len(buf) > frame_bytes * 4:
                buf = buf[-frame_bytes * 4 :]

            now = time.monotonic()
            if now - last_emit < EMIT_INTERVAL or len(buf) < frame_bytes:
                continue
            last_emit = now

            sample = buf[-frame_bytes:]
            audio = np.frombuffer(sample, dtype=np.int16).astype(np.float32) / 32768.0
            spectrum = np.abs(np.fft.rfft(audio * hann))
            freqs = np.fft.rfftfreq(frame_samples, d=1.0 / SR)
            gain_mult = intensity.get()

            levels = []
            for i in range(BANDS):
                lo, hi = edges[i], edges[i + 1]
                mask = (freqs >= lo) & (freqs < hi)
                if not np.any(mask):
                    levels.append(0.0)
                    continue
                band_energy = float(np.mean(spectrum[mask])) / frame_samples
                # Frequency-dependent pre-emphasis — see module docstring.
                # gain_mult is the user-facing "intensity" slider (Guide →
                # Settings → Media & Audio), hot-read from settings.json.
                freq_gain = 1.0 + (i / (BANDS - 1)) * 3.0
                level = min(1.0, (band_energy ** 0.5) * 9.0 * freq_gain * gain_mult)
                levels.append(round(level, 3))

            print(",".join(str(v) for v in levels))
            sys.stdout.flush()
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
