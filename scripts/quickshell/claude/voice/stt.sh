#!/usr/bin/env bash
# Ensure the warm STT server is running (detached, idempotent).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCK="/run/user/$(id -u)/qs_stt.sock"

if [ -S "$SOCK" ] && "$DIR/venv/bin/python" "$DIR/stt_client.py" ping 2>/dev/null | grep -q '"ok": true'; then
    exit 0
fi

# nvidia cudnn/cublas wheels live inside the venv — expose them to the loader
SP="$("$DIR/venv/bin/python" -c 'import site;print(site.getsitepackages()[0])')"
EXTRA=""
for d in "$SP"/nvidia/*/lib; do [ -d "$d" ] && EXTRA="$EXTRA:$d"; done
export LD_LIBRARY_PATH="${EXTRA#:}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

setsid -f "$DIR/venv/bin/python" "$DIR/stt_server.py" >/tmp/qs_stt.log 2>&1
