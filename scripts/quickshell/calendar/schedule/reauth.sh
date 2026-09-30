#!/usr/bin/env bash

DIR="$(dirname "$(readlink -f "$0")")"

kitty --title "Calendar Re-auth" bash -c "
    python3 '$DIR/setup_auth.py'
    rm -f '$HOME/.local/share/qs_schedule_cache.json'
    echo
    echo 'Done. Reopen the calendar widget.'
    sleep 3
"
