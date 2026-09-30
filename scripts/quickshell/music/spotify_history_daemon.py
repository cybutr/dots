#!/usr/bin/env python3
# Fixes the real limitation behind "can't fetch last month's listening" —
# Spotify's API only ever exposes the last 50 recently-played tracks, and
# has no historical listening-time endpoint at all (that's Wrapped-only,
# computed server-side, never public). The only way to ever have "last
# month" data is to start accumulating it locally, continuously, starting
# now — this daemon polls recently-played every POLL_SECS and merges any
# NEW plays into a persistent, unbounded-by-Spotify's-window JSONL log.
#
# Single-instance via flock (same idiom as leak_reaper.py). Started from
# exec.conf as `setsid -f python3 spotify_history_daemon.py`.
import fcntl
import calendar
import json
import os
import sys
import time

MUSIC_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, MUSIC_DIR)

import spotify_fetch  # noqa: E402 — reuses load_config/refresh_token/api_get/track_entry

HISTORY_FILE = os.path.join(MUSIC_DIR, "spotify_history.jsonl")
SEEN_IDS_CAP = 5000  # dedup window; a play is uniquely (track id, played_at)
LOCK = "/tmp/qs_spotify_history_daemon.lock"
LOG = "/tmp/qs_spotify_history_daemon.log"
POLL_SECS = 20 * 60  # recently-played holds 50 tracks; frequent enough that
# even a very heavy listening session (50 tracks in under 20min) rarely
# fully rolls over between polls, so we very rarely miss a play.


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + msg + "\n")
        if os.path.getsize(LOG) > 200000:
            os.replace(LOG, LOG + ".old")
    except OSError:
        pass


def load_seen():
    seen = set()
    try:
        with open(HISTORY_FILE) as f:
            for line in f:
                try:
                    e = json.loads(line)
                    seen.add((e.get("id", ""), e.get("ts", 0)))
                except Exception:
                    continue
    except FileNotFoundError:
        pass
    return seen


def poll_once():
    try:
        cfg = spotify_fetch.load_config()
        cfg = spotify_fetch.refresh_token(cfg)
        token = cfg["accessToken"]
        recent_raw = spotify_fetch.api_get(token, "/me/player/recently-played", {"limit": 50}).get("items", [])
    except Exception as e:
        log(f"fetch error: {e!r}")
        return 0

    seen = load_seen()
    new_entries = []
    for item in recent_raw:
        ts = 0
        played_at = item.get("played_at", "")
        if played_at:
            try:
                ts = calendar.timegm(time.strptime(played_at[:19], "%Y-%m-%dT%H:%M:%S"))
            except ValueError:
                ts = 0
        e = spotify_fetch.track_entry(item.get("track", {}), ts)
        key = (e.get("id", ""), e.get("ts", 0))
        if key not in seen:
            new_entries.append(e)
            seen.add(key)

    if new_entries:
        with open(HISTORY_FILE, "a") as f:
            for e in new_entries:
                f.write(json.dumps(e) + "\n")
        log(f"appended {len(new_entries)} new play(s)")

    return len(new_entries)


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    if "--once" in sys.argv:
        poll_once()
        return
    while True:
        try:
            poll_once()
        except Exception as e:
            log(f"error {e!r}")
        try:
            import subprocess
            subprocess.run([sys.executable, os.path.join(MUSIC_DIR, "music_meta.py")],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
        except Exception as e:
            log(f"meta error {e!r}")
        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
