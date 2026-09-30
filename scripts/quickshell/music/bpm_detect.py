#!/usr/bin/env python3
# Lightweight local BPM estimator — no Spotify Web API auth exists in this repo
# and no aubio/essentia CLI is installed on this machine, but numpy+scipy are
# already present system-wide. This captures a few seconds of the default
# sink's monitor (i.e. whatever is actually playing) and estimates tempo via
# bass-band onset autocorrelation. Result is cached per track hash by the
# caller (music_info.sh) so this only runs once per song.

import sys
import subprocess
import numpy as np
from scipy import signal

SR = 22050
DURATION = 10  # seconds of audio to sample
MIN_BPM = 60
MAX_BPM = 200


def get_monitor_source():
    try:
        sink = subprocess.run(
            ["pactl", "get-default-sink"], capture_output=True, text=True, timeout=3
        ).stdout.strip()
        if not sink:
            return None
        return f"{sink}.monitor"
    except Exception:
        return None


def capture_audio(monitor):
    cmd = [
        "timeout", str(DURATION + 2),
        "parec",
        f"--device={monitor}",
        "--format=s16le",
        "--rate=" + str(SR),
        "--channels=1",
        "--raw",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=DURATION + 5)
        raw = proc.stdout
    except Exception:
        return None
    if not raw or len(raw) < SR * 2:
        return None
    audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return audio


def estimate_bpm(audio):
    if audio is None or len(audio) < SR * 3:
        return None

    # Silence guard — nothing meaningful to analyze
    if np.sqrt(np.mean(audio ** 2)) < 0.001:
        return None

    # Emphasize kick/bass range where beats are most rhythmically obvious
    sos = signal.butter(4, [50, 200], btype="bandpass", fs=SR, output="sos")
    bass = signal.sosfilt(sos, audio)

    # Onset envelope: frame energy + half-wave rectified derivative
    hop = 256
    n_frames = len(bass) // hop
    if n_frames < 20:
        return None
    frames = bass[: n_frames * hop].reshape(n_frames, hop)
    energy = np.sqrt(np.mean(frames ** 2, axis=1))
    onset = np.diff(energy)
    onset[onset < 0] = 0

    frame_rate = SR / hop  # frames per second

    # Autocorrelation over the lag range corresponding to MIN_BPM..MAX_BPM
    onset = onset - np.mean(onset)
    if np.all(onset == 0):
        return None
    autocorr = np.correlate(onset, onset, mode="full")
    autocorr = autocorr[len(autocorr) // 2:]

    min_lag = int(frame_rate * 60 / MAX_BPM)
    max_lag = int(frame_rate * 60 / MIN_BPM)
    max_lag = min(max_lag, len(autocorr) - 1)
    if min_lag >= max_lag:
        return None

    window = autocorr[min_lag:max_lag]
    if len(window) == 0 or np.max(window) <= 0:
        return None

    peak_lag = min_lag + int(np.argmax(window))
    bpm = 60.0 * frame_rate / peak_lag

    # Octave-correct into a comfortable dance/pop range
    while bpm < 80:
        bpm *= 2
    while bpm > 175:
        bpm /= 2

    return round(bpm, 1)


def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    out_file = sys.argv[1]

    monitor = get_monitor_source()
    if not monitor:
        sys.exit(0)

    audio = capture_audio(monitor)
    bpm = estimate_bpm(audio)

    if bpm:
        with open(out_file, "w") as f:
            f.write(str(bpm))


if __name__ == "__main__":
    main()
