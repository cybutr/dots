#!/usr/bin/env bash
set -uo pipefail

WT=/home/czeddaru/.config/hypr/scripts/quickshell/claude/voice/wake_train
LOG="$WT/driver.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "driver started — augment already complete, resuming at train (fixed num_workers pickling bug)"
cd "$WT" || exit 1

log "starting train step (steps=8000, CPU, will take a while)"
if ! nice -n 15 taskset -c 0-9 bash -c './run_pipeline.sh train' >> "$LOG" 2>&1; then
  log "TRAIN STEP FAILED — see log above. aborting."
  exit 1
fi
log "train step complete"

ONNX_CANDIDATE=$(find "$WT/build" -iname "kandor.onnx" | head -1)
if [ -z "$ONNX_CANDIDATE" ]; then
  log "could not locate kandor.onnx — searching build tree"
  find "$WT/build" -iname "*.onnx" >> "$LOG" 2>&1
  log "TRAIN COMPLETED BUT MODEL FILE NOT FOUND — manual check needed"
  exit 1
fi
log "found model at $ONNX_CANDIDATE"

mkdir -p "$WT/../models"
cp "$ONNX_CANDIDATE" "$WT/../models/kandor.onnx"
log "copied to $WT/../models/kandor.onnx ($(stat -c%s "$WT/../models/kandor.onnx") bytes)"

log "running validation"
"$WT/../venv/bin/python" -c "
import sys
sys.path.insert(0, '$WT/openwakeword_repo')
from openwakeword.model import Model
m = Model(wakeword_model_paths=['$WT/../models/kandor.onnx'])
print('model loaded OK, keys:', list(m.models.keys()))
" >> "$LOG" 2>&1

log "DRIVER COMPLETE"
