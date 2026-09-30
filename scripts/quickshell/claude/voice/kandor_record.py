#!/usr/bin/env python3
"""Fast wake-phrase corpus recorder. Fixed-window capture (no double-enter, no
timing race → no empty takes), auto-skips silent takes, cycles phrase variants.
Records into ~/.local/share/qs_voice_corpus/audio as wake_kw_*.wav so the Colab
fold-in picks them up alongside the old wake_ clips.

Usage: python kandor_record.py            # defaults: 30 per phrase
       python kandor_record.py 50         # 50 per phrase
"""
import os, sys, subprocess, wave
import numpy as np

RATE = 16000
CAP_SECS = 2.0
OUT = os.path.expanduser("~/.local/share/qs_voice_corpus/audio")
# more of the primary phrase, fewer of the variants (synthetic covers variants)
PHRASES = [("yo kandor", 2), ("hey kandor", 1), ("kandor", 1), ("okay kandor", 1)]


def rms(pcm):
    a = np.frombuffer(pcm, dtype=np.int16).astype(np.float32)
    return float(np.sqrt(np.mean(a * a))) if len(a) else 0.0


def record(secs):
    proc = subprocess.Popen(["parec", "--format=s16le", f"--rate={RATE}", "--channels=1"],
                            stdout=subprocess.PIPE)
    need = int(RATE * secs) * 2
    data = b""
    stdout = proc.stdout
    while len(data) < need and stdout is not None:
        chunk = stdout.read(4096)
        if not chunk:
            break
        data += chunk
    proc.terminate()
    return data[:need]


def main():
    base = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    os.makedirs(OUT, exist_ok=True)
    total = sum(base * w for _, w in PHRASES)
    print(f"Fast recorder — {total} takes total. Fixed 2s window per take.")
    print("Flow: ENTER → 'SPEAK NOW' appears → say it immediately. Auto-saves, next.\n")
    for phrase, weight in PHRASES:
        pid = phrase.replace(" ", "_")
        target = base * weight
        done = 0
        # resume: skip indices already on disk
        while os.path.exists(os.path.join(OUT, f"wake_kw_{pid}_{done}.wav")):
            done += 1
        start = done
        while done < start + target:
            try:
                input(f'[{phrase}]  {done - start + 1}/{target}  — ENTER, then say it: ')
            except (EOFError, KeyboardInterrupt):
                print("\nstopped — progress saved.")
                return
            print("   SPEAK NOW", flush=True)
            pcm = record(CAP_SECS)
            if rms(pcm) < 100:
                print("   (too quiet — retry, say it right after ENTER)")
                continue
            path = os.path.join(OUT, f"wake_kw_{pid}_{done}.wav")
            with wave.open(path, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(pcm)
            done += 1
    print(f"\nDone. {total} clips added to {OUT}")


if __name__ == "__main__":
    main()
