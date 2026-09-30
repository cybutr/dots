#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

VENV=../venv_wake_train
export LD_LIBRARY_PATH="$(pwd)/local/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$(pwd)/openwakeword_repo:${PYTHONPATH:-}"

# CPU-only torch training pegs every core otherwise — leave 2 of 12 free and
# drop scheduling priority so the desktop stays responsive while this runs.
RUN="nice -n 15 taskset -c 0-9"

step="${1:-all}"

case "$step" in
  generate)
    $RUN "$VENV/bin/python" openwakeword_repo/openwakeword/train.py --training_config kandor.yaml --generate_clips
    ;;
  augment)
    $RUN "$VENV/bin/python" openwakeword_repo/openwakeword/train.py --training_config kandor.yaml --augment_clips --overwrite
    ;;
  train)
    $RUN "$VENV/bin/python" openwakeword_repo/openwakeword/train.py --training_config kandor.yaml --train_model
    ;;
  all)
    $RUN "$VENV/bin/python" openwakeword_repo/openwakeword/train.py --training_config kandor.yaml --generate_clips
    $RUN "$VENV/bin/python" openwakeword_repo/openwakeword/train.py --training_config kandor.yaml --augment_clips
    $RUN "$VENV/bin/python" openwakeword_repo/openwakeword/train.py --training_config kandor.yaml --train_model
    ;;
  *)
    echo "usage: run_pipeline.sh [generate|augment|train|all]" >&2
    exit 1
    ;;
esac
