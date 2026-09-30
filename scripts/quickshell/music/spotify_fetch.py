#!/usr/bin/env python3
# Fetches top tracks/artists + recently played DIRECTLY from the Spotify Web
# API, using the same stored credentials as spotify-mcp
# (~/.local/share/spotify-mcp/spotify-config.json) — no MCP server involved.
# Two reasons this exists instead of just using the spotify-mcp tools:
#   1. It needs to run unattended (a cron-able refresh for the Music Stats
#      tab), and MCP tools can only be called from an active Claude turn.
#   2. Direct API access returns real album art URLs; the MCP server's tool
#      output is pre-formatted text with no image data at all.
# Refreshes the access token via the refresh token when expired (normal,
# expected mutation for an actual fetch — unlike resident_extras.py's
# health check, which deliberately does NOT do this to avoid a redundant
# process needlessly consuming/rotating a token another session might need
# just to answer "is this healthy").
import calendar
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.local/share/spotify-mcp/spotify-config.json")
OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spotify_snapshot.json")
API = "https://api.spotify.com/v1"

# Local album-art cache — Spotify's CDN URLs are used directly as the art
# field by default, but those can 404 or just feel wrong to depend on for
# something as core as "does this track show its cover at all". Downloaded
# once per track id, reused forever after (cover art doesn't change), same
# on-disk idiom as music_info.sh's local mpris art cache (/tmp/eww_covers).
ART_CACHE_DIR = os.path.expanduser("~/.cache/quickshell/spotify_art")
os.makedirs(ART_CACHE_DIR, exist_ok=True)


def cache_art(url, track_id):
    if not url or not track_id:
        return url
    path = os.path.join(ART_CACHE_DIR, track_id + ".jpg")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return "file://" + path
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = resp.read()
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        return "file://" + path
    except Exception:
        return url  # best-effort — fall back to the remote URL if the download fails


def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def save_config(cfg):
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, CONFIG_PATH)


def refresh_token(cfg):
    import base64
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": cfg["refreshToken"],
    }).encode()
    auth = base64.b64encode(f"{cfg['clientId']}:{cfg['clientSecret']}".encode()).decode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token", data=data,
        headers={"Authorization": f"Basic {auth}",
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        result = json.loads(resp.read())
    cfg["accessToken"] = result["access_token"]
    cfg["expiresAt"] = int(time.time() * 1000) + result.get("expires_in", 3600) * 1000
    if "refresh_token" in result:  # Spotify doesn't always rotate it, but honor it if given
        cfg["refreshToken"] = result["refresh_token"]
    save_config(cfg)
    return cfg


def api_get(token, path, params=None):
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def track_entry(t, ts=None):
    art = ""
    images = (t.get("album") or {}).get("images") or []
    if images:
        art = images[-1]["url"]  # smallest image — this is for thumbnails, not the popup's hero art
        for im in images:
            if im.get("width") and im["width"] <= 200:
                art = im["url"]
    large = ""
    if images:
        big = [im for im in images if (im.get("width") or 0) >= 280]
        large = min(big, key=lambda im: im["width"])["url"] if big else images[0]["url"]
    track_id = t.get("id", "")
    e = {
        "artist": ", ".join(a["name"] for a in t.get("artists", [])) or "Unknown",
        "title": t.get("name", "Unknown"),
        "id": track_id,
        "art": cache_art(art, track_id),
        "artLarge": cache_art(large, track_id + "_l") if large else "",
        "durationSec": round(t.get("duration_ms", 0) / 1000) if t.get("duration_ms") else 0,
        "released": (t.get("album") or {}).get("release_date", ""),
        "explicit": bool(t.get("explicit")),
    }
    if ts is not None:
        e["ts"] = ts
    return e


def main():
    try:
        cfg = load_config()
    except (OSError, ValueError) as e:
        print(json.dumps({"error": f"no spotify config: {e}"}))
        sys.exit(1)

    try:
        # Always refresh — simplest correct behavior for an on-demand/cron
        # fetch, and avoids trusting a possibly-stale expiresAt from a
        # different process's last write (see resident_extras.py's comment
        # on the same multi-session staleness class of problem).
        cfg = refresh_token(cfg)
        token = cfg["accessToken"]

        top_short = [track_entry(t) for t in api_get(token, "/me/top/tracks", {"limit": 15, "time_range": "short_term"}).get("items", [])]
        top_long = [track_entry(t) for t in api_get(token, "/me/top/tracks", {"limit": 15, "time_range": "long_term"}).get("items", [])]
        recent_raw = api_get(token, "/me/player/recently-played", {"limit": 50}).get("items", [])
        recent = []
        for item in recent_raw:
            ts = 0
            played_at = item.get("played_at", "")
            if played_at:
                try:
                    ts = calendar.timegm(time.strptime(played_at[:19], "%Y-%m-%dT%H:%M:%S"))
                except ValueError:
                    ts = 0
            recent.append(track_entry(item.get("track", {}), ts))

        top_artists = {}
        for entries in (top_short, top_long, recent):
            for e in entries:
                for name in e["artist"].split(", "):
                    top_artists[name] = top_artists.get(name, 0) + 1

        def top_artist_names(time_range):
            try:
                items = api_get(token, "/me/top/artists", {"limit": 15, "time_range": time_range}).get("items", [])
            except Exception:
                return []
            return [a.get("name", "") for a in items if a.get("name")]

        snapshot = {
            "fetchedAt": int(time.time()),
            "topTracksShort": top_short,
            "topTracksLong": top_long,
            "recentlyPlayed": recent,
            "topArtistsDerived": sorted(top_artists.items(), key=lambda kv: kv[1], reverse=True)[:12],
            "topArtistsShort": top_artist_names("short_term"),
            "topArtistsLong": top_artist_names("long_term"),
        }
        tmp = OUT_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(snapshot, f)
        os.replace(tmp, OUT_PATH)
        print(json.dumps({"ok": True, "recentlyPlayed": len(recent)}))
    except urllib.error.HTTPError as e:
        print(json.dumps({"error": f"HTTP {e.code}: {e.read().decode(errors='replace')[:200]}"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
