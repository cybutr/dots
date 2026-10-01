#!/usr/bin/env bash
if [ -z "$QS_LIFELINE" ]; then
    export QS_LIFELINE=1
    exec setpriv --pdeathsig TERM setsid "$0" "$@"
fi
setpriv --pdeathsig TERM bash -c "$1" &
trap 'trap - TERM INT HUP; kill -TERM -- -$$' TERM INT HUP
wait $!
rc=$?
trap 'exit $rc' TERM
kill -TERM -- -$$
