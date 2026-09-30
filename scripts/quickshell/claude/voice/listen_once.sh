#!/usr/bin/env bash
# One-shot voice capture → prints {"text","lang","ok"} JSON. Used by QuickTell
# voice mode. Ensures the warm STT server is up first.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$DIR/stt.sh"          # idempotent: start/warm server
exec "$DIR/venv/bin/python" "$DIR/stt_client.py" "${1:-8}" "${2:-}"
