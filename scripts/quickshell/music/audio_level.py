#!/usr/bin/env python3
# Single-shot RMS amplitude sample of the default sink's monitor.
# Mirrors bpm_detect.py's capture approach but much shorter (one poll's worth,
# ~150ms) since this is called repeatedly (every ~700ms while Playing) to
# drive a subtle breathing glow in MusicPopup.qml, not a one-time analysis.
# No numpy here on purpose — the sample is tiny and this runs on a fast
# timer, so avoiding numpy's import cost keeps each poll cheap.

import subprocess
import array
import math

SR = 11025
CAPTURE_SEC = 0.15


def get_monitor_source():
    try:
        sink = subprocess.run(
            ["pactl", "get-default-sink"], capture_output=True, text=True, timeout=1
        ).stdout.strip()
        if not sink:
            return None
        return f"{sink}.monitor"
    except Exception:
        return None


def main():
    monitor = get_monitor_source()
    if not monitor:
        print(0.0)
        return

    cmd = [
        "timeout", str(CAPTURE_SEC + 0.1),
        "parec",
        f"--device={monitor}",
        "--format=s16le",
        f"--rate={SR}",
        "--channels=1",
        "--raw",
        # Default parec buffering (fragsize ~ a couple hundred ms) never
        # flushes a fragment within our short capture window, so stdout
        # stayed empty the whole time and every sample read back as 0.0.
        # Forcing a small latency makes parec flush well inside 150ms.
        "--latency-msec=30",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=1)
        raw = proc.stdout
    except Exception:
        print(0.0)
        return

    if not raw or len(raw) < 200:
        print(0.0)
        return

    if len(raw) % 2:
        raw = raw[:-1]
    samples = array.array("h")
    samples.frombytes(raw)

    sq_sum = sum(s * s for s in samples)
    rms = math.sqrt(sq_sum / len(samples)) / 32768.0

    # Typical music RMS sits well under full scale — scale up so normal
    # playback lands in a usable 0..1 range, then clamp.
    level = min(1.0, rms * 6.0)
    print(round(level, 3))


if __name__ == "__main__":
    main()
