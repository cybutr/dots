import sys
sys.path.insert(0, "./piper-sample-generator")
import numpy as np
from generate_samples import generate_samples
from openwakeword.model import Model

generate_samples(
    text=["yo kandor"], max_samples=1, batch_size=1,
    output_dir="/tmp/kandor_validate_pos", auto_reduce_batch_size=True,
)
generate_samples(
    text=["turn off the lights"], max_samples=1, batch_size=1,
    output_dir="/tmp/kandor_validate_neg", auto_reduce_batch_size=True,
)

import glob, scipy.io.wavfile as wavfile

oww = Model(wakeword_model_paths=["models/kandor.onnx"])

for label, folder in [("positive", "/tmp/kandor_validate_pos"), ("negative", "/tmp/kandor_validate_neg")]:
    wav = glob.glob(folder + "/*.wav")[0]
    sr, data = wavfile.read(wav)
    oww.reset()
    scores = []
    for i in range(0, len(data) - 1280, 1280):
        chunk = data[i:i + 1280]
        preds = oww.predict(chunk)
        scores.append(list(preds.values())[0])
    print(label, wav, "max score:", max(scores))
