#!/usr/bin/env python3
"""Live wake-word test. Captures mic, prints the 'yo kandor' score in real time.
Run under venv_wake_train (openwakeword 0.6.0). Say the phrase a few times."""
import numpy as np, subprocess, os
from openwakeword.model import Model

BASE = os.path.dirname(os.path.abspath(__file__))
m = Model(wakeword_models=[os.path.join(BASE, "models", "kandor.onnx")],
          inference_framework="onnx")
RATE, CHUNK = 16000, 1280
proc = subprocess.Popen(["parec", "--format=s16le", f"--rate={RATE}", "--channels=1"],
                        stdout=subprocess.PIPE)
print('LISTENING — say "yo kandor" clearly a few times. Ctrl-C to stop.', flush=True)
print("(anything above ~0.5 = would trigger)", flush=True)
peak = 0.0
try:
    while True:
        raw = proc.stdout.read(CHUNK * 2)
        if len(raw) < CHUNK * 2:
            break
        s = list(m.predict(np.frombuffer(raw, dtype=np.int16)).values())[0]
        if s > 0.03:
            peak = max(peak, s)
            bar = "#" * int(s * 40)
            print(f"{s:5.3f} |{bar:<40}| peak {peak:.3f}", flush=True)
finally:
    proc.terminate()
    print(f"\nHighest score seen: {peak:.3f}", flush=True)
