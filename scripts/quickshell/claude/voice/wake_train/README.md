# kandor wake word training

Trains `voice/models/kandor.onnx` for "yo kandor" using openWakeWord's own
automatic training pipeline (`openwakeword_repo/openwakeword/train.py`),
adapted to run locally instead of in Colab.

## Layout

- `openwakeword_repo/` — shallow clone of dscripka/openWakeWord (has `train.py`,
  `data.py`, `utils.py` used for training; not pip-installed over the venv's
  runtime openwakeword==0.4.0, kept separate via `PYTHONPATH` so the wake
  daemon's installed package is untouched).
- `piper-sample-generator/` — dscripka's fork (the one with a flat
  `generate_samples.py`, matches what `train.py` imports — the current
  rhasspy/piper-sample-generator was restructured and no longer exposes this).
- `local/` — user-space build of espeak-ng (system had classic `espeak`, not
  `espeak-ng`; no root available, so built from source into this prefix
  instead of `pacman -S espeak-ng`). `run_pipeline.sh` points
  `LD_LIBRARY_PATH` at `local/lib` so piper's phonemizer can `dlopen` it.
- `data/` — `mit_rirs/` (room impulse responses, for reverb augmentation),
  `openwakeword_features_ACAV100M_2000_hrs_16bit.npy` (precomputed negative
  features, ~17GB) and `validation_set_features.npy` (~185MB), both from
  huggingface.co/datasets/davidscripka/openwakeword_features.
- `kandor.yaml` — training config (target phrase, sample counts, steps).
- `build/` — output dir; `train.py` writes `positive_train/`, `negative_train/`,
  etc. here, plus the final `kandor.onnx`.
- `run_pipeline.sh` — thin wrapper that sets `PYTHONPATH`/`LD_LIBRARY_PATH`
  and calls `train.py` with the right flags.

## Rerunning / fine-tuning

```
./run_pipeline.sh generate   # synthesize positive + adversarial-negative clips with piper
./run_pipeline.sh augment    # augment clips (reverb/EQ/pitch/noise), compute embeddings
./run_pipeline.sh train      # train the classifier head, export build/kandor.onnx
```

Copy `build/kandor.onnx` to `../models/kandor.onnx` when satisfied.

To add real recorded "yo kandor" samples later (e.g. from `train_corpus.py`'s
corpus): drop the real WAVs (16kHz mono s16le) into
`build/kandor/positive_train/` and `build/kandor/positive_test/` before
running `augment`+`train` again — `train.py` treats everything in those dirs
as positives regardless of origin, so real and synthetic clips mix
automatically. Increasing the real:synthetic ratio there is how you'd bias
the model toward the user's actual voice.

## Notable deviations from the notebook

- Skipped the AudioSet/FMA background-noise download — the notebook's
  `bal_train09.tar` path 404s (HF restructured that dataset to parquet
  shards). `background_paths: []` in `kandor.yaml`; `augment_clips` degrades
  gracefully to EQ/distortion/pitch/bandstop/colored-noise/gain/reverb
  without background-mixing, per `openwakeword/data.py`'s `augment_clips`
  (background mixing is skipped cleanly when `background_clip_paths == []`).
- No tflite export — `wake_daemon.py` loads onnx, so `--convert_to_tflite`
  is never passed, and `tensorflow-cpu`/`onnx_tf` (only needed for that
  conversion) are not installed.
- espeak-ng built from source to a local prefix instead of `pacman -S
  espeak-ng` — no passwordless sudo available in this session. If the user
  wants a slightly cleaner setup later: `sudo pacman -S espeak-ng` then
  drop `local/` and the `LD_LIBRARY_PATH` line in `run_pipeline.sh`.
