#!/usr/bin/env python3
import fcntl
import json
import os
import sys
import time
import urllib.parse
import urllib.request

MUSIC_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, MUSIC_DIR)

import spotify_fetch  # noqa: E402

META_FILE = os.path.expanduser("~/.cache/quickshell/music_meta.json")
LOCK = "/tmp/qs_music_meta.lock"
MB_UA = "qs-music-stats/1.0 (claude@pixelfields.net)"
MB_RETRY_SECS = 14 * 86400
TRACK_BUDGET = 80
ARTIST_BUDGET = 60


def load_meta():
    try:
        with open(META_FILE) as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    d.setdefault("tracks", {})
    d.setdefault("artists", {})
    return d


def save_meta(d):
    os.makedirs(os.path.dirname(META_FILE), exist_ok=True)
    tmp = META_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, META_FILE)


def history_entries():
    out = []
    try:
        with open(os.path.join(MUSIC_DIR, "spotify_history.jsonl")) as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    continue
    except OSError:
        pass
    return out


def local_entries():
    out = []
    try:
        with open(os.path.join(MUSIC_DIR, "play_history.jsonl")) as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    continue
    except OSError:
        pass
    return out


def fill_tracks(meta, entries):
    for e in entries:
        tid = e.get("id")
        if tid and tid not in meta["tracks"] and e.get("released"):
            meta["tracks"][tid] = {"released": e["released"], "explicit": bool(e.get("explicit"))}
    missing = [e["id"] for e in entries if e.get("id") and e["id"] not in meta["tracks"]]
    missing = list(dict.fromkeys(missing))[:TRACK_BUDGET]
    if not missing:
        return 0
    try:
        cfg = spotify_fetch.refresh_token(spotify_fetch.load_config())
        token = cfg["accessToken"]
    except Exception:
        return 0
    n = 0
    for tid in missing:
        try:
            t = spotify_fetch.api_get(token, "/tracks/" + tid)
        except Exception:
            continue
        meta["tracks"][tid] = {
            "released": (t.get("album") or {}).get("release_date", ""),
            "explicit": bool(t.get("explicit")),
        }
        n += 1
        time.sleep(0.15)
    return n


def mb_get(path, params):
    url = "https://musicbrainz.org/ws/2/" + path + "?" + urllib.parse.urlencode(dict(params, fmt="json"))
    req = urllib.request.Request(url, headers={"User-Agent": MB_UA})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read())
    time.sleep(1.1)
    return data


def mb_artist_id(name, titles):
    for title in titles[:2]:
        data = mb_get("recording/", {"query": f'recording:"{title}" AND artist:"{name}"', "limit": 5})
        for rec in data.get("recordings", []):
            for c in rec.get("artist-credit", []):
                a = c.get("artist") or {}
                if name.lower() in (c.get("name", "").lower(), a.get("name", "").lower()):
                    return a.get("id")
    return None


def mb_genres(name, titles):
    mbid = mb_artist_id(name, titles)
    if not mbid:
        return []
    data = mb_get("artist/" + mbid, {"inc": "genres+tags"})
    pool = data.get("genres") or data.get("tags") or []
    pool = sorted(pool, key=lambda t: -(t.get("count") or 0))
    return [t["name"] for t in pool if (t.get("count") or 0) > 0][:6]


def fill_artists(meta, titles_by_artist):
    now = time.time()
    todo = []
    for n in titles_by_artist:
        rec = meta["artists"].get(n)
        if rec is None or (not rec.get("tags") and now - rec.get("tried", 0) > MB_RETRY_SECS):
            todo.append(n)
    done = 0
    for n in todo[:ARTIST_BUDGET]:
        try:
            tags = mb_genres(n, titles_by_artist[n])
        except Exception:
            time.sleep(1.2)
            continue
        meta["artists"][n] = {"tags": tags, "tried": int(now)}
        done += 1
    return done


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    meta = load_meta()
    entries = history_entries()
    t = fill_tracks(meta, entries)
    titles_by_artist = {}
    for e in entries + local_entries():
        title = e.get("title", "")
        for a in e.get("artist", "").split(", "):
            if a and title:
                lst = titles_by_artist.setdefault(a, [])
                if title not in lst:
                    lst.append(title)
    a = fill_artists(meta, titles_by_artist)
    save_meta(meta)
    print(json.dumps({"tracks": t, "artists": a}))


if __name__ == "__main__":
    main()
