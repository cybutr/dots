#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MUSIC = os.path.join(os.path.dirname(HERE), "music")
sys.path.insert(0, MUSIC)

import spotify_fetch  # noqa: E402

CACHE = os.path.expanduser("~/.cache/quickshell/palette/spotify_peek.json")
HISTORY = os.path.join(MUSIC, "play_history.jsonl")
COVERS = "/tmp/eww_covers"
TTL = 45


def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""


def api(token, path, params=""):
    req = urllib.request.Request(spotify_fetch.API + path + params, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=4) as r:
        body = r.read()
    return json.loads(body) if body else {}


def token():
    cfg = spotify_fetch.load_config()
    if cfg.get("expiresAt", 0) < time.time() * 1000 + 60000:
        cfg = spotify_fetch.refresh_token(cfg)
    return cfg["accessToken"]


def entry(t):
    if not t:
        return None
    imgs = (t.get("album") or {}).get("images") or []
    big = [im for im in imgs if (im.get("width") or 0) >= 280]
    url = min(big, key=lambda im: im["width"])["url"] if big else (imgs[0]["url"] if imgs else "")
    art = spotify_fetch.cache_art(url, t.get("id", "") + "_l") if url and t.get("id") else url
    return {"title": t.get("name", ""), "artist": ", ".join(a["name"] for a in t.get("artists", [])), "art": art}


def previous(title, artist):
    try:
        lines = open(HISTORY).read().splitlines()[-40:]
    except OSError:
        return None
    for ln in reversed(lines):
        try:
            e = json.loads(ln)
        except ValueError:
            continue
        if e.get("title") == title and e.get("artist") == artist:
            continue
        art = os.path.join(COVERS, (e.get("hash") or "") + "_art.jpg")
        return {"title": e.get("title", ""), "artist": e.get("artist", ""), "art": "file://" + art if os.path.isfile(art) else "", "hash": e.get("hash", "")}
    return None


def main():
    if sh(["playerctl", "--player=spotify", "status"]) not in ("Playing", "Paused"):
        print("{}")
        return
    meta = sh(["playerctl", "--player=spotify", "metadata", "--format", "{{mpris:trackid}}\t{{title}}\t{{artist}}"]).split("\t")
    if len(meta) < 3 or not meta[0]:
        print("{}")
        return
    track, title, artist = meta[0], meta[1], meta[2]
    try:
        c = json.load(open(CACHE))
        if c.get("track") == track and time.time() - c.get("ts", 0) < TTL:
            print(json.dumps(c))
            return
    except (OSError, ValueError):
        pass
    out = {"track": track, "now": title, "ts": int(time.time()), "next": None, "prev": previous(title, artist)}
    try:
        tok = token()
        q = api(tok, "/me/player/queue").get("queue") or []
        out["next"] = entry(q[0]) if q else None
        p = out["prev"]
        if p and not p["art"]:
            for it in api(tok, "/me/player/recently-played", "?limit=20").get("items") or []:
                t = it.get("track") or {}
                if t.get("name") == p["title"]:
                    p["art"] = (entry(t) or {}).get("art", "")
                    break
    except Exception:
        print(json.dumps(out))
        return
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE + ".tmp", "w") as f:
        json.dump(out, f)
    os.replace(CACHE + ".tmp", CACHE)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
