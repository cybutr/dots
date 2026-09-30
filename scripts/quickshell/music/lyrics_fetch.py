#!/usr/bin/env python3
# Fetches lyrics for the current track from lrclib.net (free, no API key,
# the same open lyrics source most third-party "now playing" lyrics
# overlays use). Two-tier lookup: /api/get first (fast, exact match via
# artist+title+duration), falling back to /api/search (fuzzy match) when
# the exact lookup 404s — artist/title strings from playerctl frequently
# don't match the canonical metadata lrclib indexes under (e.g. "Bush
# Babees" vs the actual "Da Bush Babees"), so the fuzzy fallback matters
# for real coverage, not just an edge case.
#
# Prefers synced lyrics (LRC [mm:ss.xx] tags, parsed into a list of
# {time, text}) when available, falls back to plain unsynced lyrics
# otherwise — not every track has word/line-synced lyrics submitted.
#
# Cached per artist+title (including negative "not found" results, so a
# track with no lyrics available doesn't get re-queried every time its
# hover card opens) to keep this from hammering lrclib on every hover.
import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/quickshell/lyrics")
CACHE_TTL_NOTFOUND = 6 * 3600  # re-try a "not found" after 6h, not forever
TIMEOUT = 4


def cache_path(artist, title):
    key = hashlib.sha1(f"{artist.lower()}|{title.lower()}".encode()).hexdigest()
    return os.path.join(CACHE_DIR, key + ".json")


def load_cache(path):
    try:
        with open(path) as f:
            d = json.load(f)
        if not d.get("found") and (time_now() - d.get("cachedAt", 0)) > CACHE_TTL_NOTFOUND:
            return None
        return d
    except Exception:
        return None


def time_now():
    import time
    return time.time()


def save_cache(path, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        data["cachedAt"] = time_now()
        with open(path, "w") as f:
            json.dump(data, f)
    except Exception:
        pass


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-lyrics/1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


LRC_TAG = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def parse_synced(lrc_text):
    # LRC allows more than one leading timestamp tag sharing a single line
    # of text — standard for a repeated chorus/hook
    # ("[00:12.00][00:45.00]Same line"). A single-tag match here previously
    # kept only the first tag and left every subsequent one as literal
    # "[mm:ss.xx]" garbage prepended to the visible text, and the repeat
    # occurrence later in the song never got its own timed entry at all —
    # this is the actual cause of "not every lyric syncs right": whole
    # repeated sections had no synced entry to advance to, so the highlight
    # just sat on the earlier line until the next singly-tagged one came
    # along. Consume every consecutive leading tag, then emit one entry per
    # tag with the shared text.
    lines = []
    for raw in lrc_text.splitlines():
        pos = 0
        times = []
        while True:
            m = LRC_TAG.match(raw, pos)
            if not m:
                break
            mins, secs = m.groups()
            times.append(int(mins) * 60 + float(secs))
            pos = m.end()
        if not times:
            continue
        text = raw[pos:].strip()
        if not text:
            continue
        for t in times:
            lines.append({"time": round(t, 2), "text": text})
    lines.sort(key=lambda x: x["time"])
    return lines


def fetch_get(artist, title, duration):
    params = {"track_name": title, "artist_name": artist}
    if duration:
        params["duration"] = str(int(duration))
    url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
    try:
        return http_json(url)
    except Exception:
        return None


def fetch_search(artist, title):
    params = {"track_name": title, "artist_name": artist}
    url = "https://lrclib.net/api/search?" + urllib.parse.urlencode(params)
    try:
        results = http_json(url)
        return results[0] if results else None
    except Exception:
        return None


def build_result(entry):
    if not entry:
        return {"found": False}
    synced = entry.get("syncedLyrics")
    plain = entry.get("plainLyrics")
    if synced:
        parsed = parse_synced(synced)
        if parsed:
            return {"found": True, "synced": parsed, "plain": plain or ""}
    if plain:
        return {"found": True, "synced": [], "plain": plain}
    return {"found": False}


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"found": False, "error": "usage: lyrics_fetch.py <artist> <title> [duration]"}))
        return
    artist, title = sys.argv[1], sys.argv[2]
    duration = sys.argv[3] if len(sys.argv) > 3 else None

    path = cache_path(artist, title)
    cached = load_cache(path)
    if cached is not None:
        print(json.dumps(cached))
        return

    entry = fetch_get(artist, title, duration)
    if entry is None or entry.get("statusCode") == 404:
        entry = fetch_search(artist, title)

    result = build_result(entry)
    save_cache(path, result)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
