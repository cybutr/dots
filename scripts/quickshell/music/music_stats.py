#!/usr/bin/env python3
# Reads play_history.jsonl (the append-only "what did I actually listen to
# and when" log written by music_info.sh) and song_cache.json (the per-track
# color/bpm lookup, keyed by hash, that music_info.sh already maintained for
# the media pill) and joins them into one stats blob for the Guide's Music
# Stats tab: recently played, most played (all-time / this week), average
# BPM (today vs overall — genuinely novel, nobody else exposes this),
# a listening-by-hour heatmap, and "on this day" (something played roughly
# this time of day N days/weeks/months ago).
#
# One-shot, invoked on demand (Guide tab open / refresh), not a persistent
# process — the history file is small (one line per track change) and this
# runs in well under a second even with years of history.
import json
import os
import time
from collections import defaultdict
from typing import Any

MUSIC_DIR = os.path.dirname(os.path.abspath(__file__))
HISTORY_FILE = os.path.join(MUSIC_DIR, "play_history.jsonl")
CACHE_FILE = os.path.join(MUSIC_DIR, "song_cache.json")

DAY = 86400


def load_history():
    plays = []
    try:
        with open(HISTORY_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    plays.append(json.loads(line))
                except Exception:
                    continue
    except FileNotFoundError:
        pass
    return plays


def load_cache():
    try:
        with open(CACHE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


ART_DIR = "/tmp/eww_covers"


def _art_key(artist, title):
    return (artist or "").strip().lower() + "|" + (title or "").strip().lower()


def enrich(entry, cache, art_lookup=None):
    c = cache.get(entry["hash"], {})
    art_path = os.path.join(ART_DIR, f"{entry['hash']}_art.jpg")
    art = ("file://" + art_path) if os.path.exists(art_path) else ""
    # Local mpris art only exists for tracks played THIS boot session —
    # older history entries commonly have none. Fall back to the locally
    # cached Spotify art for the same artist+title (spotify_fetch.py
    # downloads those permanently to ~/.cache/quickshell/spotify_art/), so
    # "This Machine" doesn't show blank covers for anything Spotify has
    # also seen, which in practice is almost everything.
    if not art and art_lookup:
        art = art_lookup.get(_art_key(entry.get("artist", ""), entry.get("title", "")), "")
    return {
        "artist": entry.get("artist", ""),
        "title": entry.get("title", ""),
        "ts": entry.get("ts", 0),
        "hash": entry.get("hash", ""),
        "grad": c.get("grad", ""),
        "vibrantGrad": c.get("vibrantGrad", ""),
        "bpm": c.get("bpm"),
        "art": art,
    }


SPOTIFY_SNAPSHOT = os.path.join(MUSIC_DIR, "spotify_snapshot.json")
SPOTIFY_HISTORY = os.path.join(MUSIC_DIR, "spotify_history.jsonl")


def load_spotify_history():
    # The PERSISTENT log — spotify_history_daemon.py polls recently-played
    # every 20min and appends anything new, deduped by (track id, played_at).
    # Unlike spotify_snapshot.json (a live 50-track rolling window), this
    # only grows, so it's what makes "how much did I listen this week/month"
    # actually answerable — it just needs time to accumulate from whenever
    # the daemon first started.
    entries = []
    try:
        with open(SPOTIFY_HISTORY) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except Exception:
                    continue
    except FileNotFoundError:
        pass
    return entries


def load_spotify():
    # A point-in-time fetch (spotify_fetch.py), not live — it hits the real
    # Spotify Web API directly (not the MCP server, which can only be called
    # from an active Claude turn and can't run unattended) and covers every
    # device on the account, not just this desktop. Clearly timestamped so
    # the UI can label it "as of <time>" rather than implying it's live.
    try:
        with open(SPOTIFY_SNAPSHOT) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


META_FILE = os.path.expanduser("~/.cache/quickshell/music_meta.json")
SESSION_GAP = 20 * 60


def load_meta():
    try:
        with open(META_FILE) as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    return d.get("tracks", {}), d.get("artists", {})


def _year(released):
    try:
        return int(str(released)[:4])
    except (TypeError, ValueError):
        return None


def merged_stream(local, sp_history):
    sp = sorted((p for p in sp_history if p.get("ts") and p.get("artist")), key=lambda p: p["ts"])
    sp_times: dict[str, list[int]] = defaultdict(list)
    for p in sp:
        sp_times[_art_key(p["artist"], p.get("title", ""))].append(p["ts"])
    out = [dict(p, src="spotify") for p in sp]
    last_local: dict[str, int] = {}
    for p in sorted(local, key=lambda p: p.get("ts", 0)):
        if not p.get("artist") or not p.get("ts"):
            continue
        k = _art_key(p["artist"], p.get("title", ""))
        if k in last_local and p["ts"] - last_local[k] < 90:
            continue
        last_local[k] = p["ts"]
        if any(abs(t - p["ts"]) < 900 for t in sp_times.get(k, ())):
            continue
        out.append(dict(p, src="local"))
    out.sort(key=lambda p: p["ts"])
    return out


def personality(local, sp_history, snapshot):
    stream = merged_stream(local, sp_history)
    n = len(stream)
    if n < 20:
        return None
    track_meta, artist_meta = load_meta()
    id_by_key = {}
    for p in sp_history:
        if p.get("id"):
            id_by_key.setdefault(_art_key(p.get("artist", ""), p.get("title", "")), p["id"])

    def lead(p):
        return p["artist"].split(", ")[0]

    def meta_for(p):
        tid = p.get("id") or id_by_key.get(_art_key(p["artist"], p.get("title", "")))
        m = track_meta.get(tid, {}) if tid else {}
        released = p.get("released") or m.get("released")
        explicit = p.get("explicit") if "explicit" in p else m.get("explicit")
        return _year(released), explicit

    span_days = max(1.0, (stream[-1]["ts"] - stream[0]["ts"]) / DAY)
    hours = [time.localtime(p["ts"]).tm_hour for p in stream]
    night = sum(1 for h in hours if h >= 22 or h < 5) / n
    morning = sum(1 for h in hours if 5 <= h < 10) / n

    track_keys = [_art_key(p["artist"], p.get("title", "")) for p in stream]
    unique_tracks = len(set(track_keys))
    replay = (n - unique_tracks) / n

    artist_counts: dict[str, int] = defaultdict(int)
    for p in stream:
        artist_counts[lead(p)] += 1
    ranked_artists = sorted(artist_counts.items(), key=lambda kv: kv[1], reverse=True)
    unique_artists = len(ranked_artists)
    top3_share = sum(c for _, c in ranked_artists[:3]) / n
    explore = unique_artists / n

    sessions = []
    cur = [stream[0]]
    for p in stream[1:]:
        if p["ts"] - cur[-1]["ts"] > SESSION_GAP:
            sessions.append(cur)
            cur = []
        cur.append(p)
    sessions.append(cur)

    def sess_secs(s):
        return s[-1]["ts"] - s[0]["ts"] + (s[-1].get("durationSec") or 210)

    longest = max(sessions, key=sess_secs)
    longest_secs = sess_secs(longest)
    avg_session_plays = n / len(sessions)

    years = []
    explicit_n = explicit_known = 0
    old = 0
    for p in stream:
        y, ex = meta_for(p)
        if y:
            years.append((y, p))
            if time.localtime(p["ts"]).tm_year - y >= 15:
                old += 1
        if ex is not None:
            explicit_known += 1
            explicit_n += 1 if ex else 0
    dated = len(years)
    old_share = old / dated if dated else 0

    era = None
    if dated >= 10:
        ys = sorted(y for y, _ in years)
        median = ys[len(ys) // 2]
        decades: dict[int, int] = defaultdict(int)
        for y in ys:
            decades[y // 10 * 10] += 1
        oldest_y, oldest_p = min(years, key=lambda t: t[0])
        now_year = time.localtime().tm_year
        era = {
            "medianYear": median,
            "avgAge": round(sum(now_year - y for y in ys) / len(ys), 1),
            "decades": [{"decade": d, "count": c, "share": round(c / len(ys), 3)} for d, c in sorted(decades.items())],
            "oldest": {"year": oldest_y, "artist": oldest_p["artist"], "title": oldest_p.get("title", "")},
            "pre2000Share": round(sum(1 for y in ys if y < 2000) / len(ys), 3),
            "datedPlays": len(ys),
        }

    genre_w: dict[str, float] = defaultdict(float)
    primary: dict[str, int] = defaultdict(int)
    tagged = 0
    tagged_artists = set()
    for p in stream:
        tags = (artist_meta.get(lead(p)) or {}).get("tags") or []
        if not tags:
            continue
        tagged += 1
        tagged_artists.add(lead(p))
        primary[tags[0]] += 1
        for t in tags[:4]:
            genre_w[t] += 1
    taste = None
    if tagged >= 10:
        import math
        total = sum(primary.values())
        k = len(primary)
        entropy = -sum((c / total) * math.log(c / total) for c in primary.values())
        diversity = round(100 * entropy / math.log(k)) if k > 1 else 0
        top = sorted(genre_w.items(), key=lambda kv: kv[1], reverse=True)[:6]
        broad = top[0][0] if top else ""
        signature = next((g for g, _ in top if g != broad and broad in g), None) or next((g for g, _ in top[1:]), broad)
        taste = {
            "genres": [{"name": g, "share": round(w / tagged, 3)} for g, w in top],
            "diversity": diversity,
            "primaryGenres": k,
            "signature": signature,
            "broad": broad,
            "taggedPlays": tagged,
            "taggedArtists": len(tagged_artists),
            "totalArtists": unique_artists,
        }

    def strength(v, base):
        return max(0.0, (v - base) / (1 - base)) if base < 1 else 0.0

    traits = [
        {"key": "night", "label": "Night owl", "value": night, "score": strength(night, 7 / 24),
         "fact": f"{round(night * 100)}% of plays between 10pm and 5am"},
        {"key": "morning", "label": "Early riser", "value": morning, "score": strength(morning, 5 / 24),
         "fact": f"{round(morning * 100)}% of plays between 5am and 10am"},
        {"key": "replay", "label": "Replay", "value": replay, "score": strength(replay, 0.25),
         "fact": f"{round(replay * 100)}% of plays were a track you'd already played"},
        {"key": "loyal", "label": "Loyalty", "value": top3_share, "score": strength(top3_share, 0.3),
         "fact": f"your top 3 artists took {round(top3_share * 100)}% of plays"},
        {"key": "explore", "label": "Range", "value": explore, "score": strength(explore, 0.35),
         "fact": f"{unique_artists} different artists in {n} plays"},
        {"key": "marathon", "label": "Stamina", "value": min(1.0, longest_secs / (4 * 3600)),
         "score": strength(min(1.0, longest_secs / (4 * 3600)), 0.4),
         "fact": f"longest session ran {longest_secs // 3600}h {longest_secs % 3600 // 60}m non-stop"},
    ]
    if dated >= 10:
        traits.append({"key": "vintage", "label": "Vintage", "value": old_share, "score": strength(old_share, 0.35),
                       "fact": f"{round(old_share * 100)}% of plays were 15+ years old when you hit play"})

    archetypes = {
        "night": ("The Night Owl", "󰖔", "Your best listening happens after dark — the queue gets going when everyone else logs off."),
        "morning": ("The Early Riser", "󰖙", "You start the day with a soundtrack before most people start the kettle."),
        "replay": ("The Repeat Offender", "󰑖", "When you find a track you like, you don't let go of it."),
        "loyal": ("The Loyalist", "󰋑", "You've got your artists and you ride with them."),
        "explore": ("The Explorer", "󰆋", "Always somewhere new — your queue barely repeats an artist."),
        "marathon": ("The Marathoner", "󰋋", "You don't dip in — you put the headphones on and stay there."),
        "vintage": ("The Time Traveller", "󰔟", "You've got a time machine and you're using it — your queue lives in another decade."),
    }
    ranked = sorted(traits, key=lambda t: t["score"], reverse=True)
    main_t = ranked[0]
    name, glyph, blurb = archetypes[main_t["key"]]
    if main_t["score"] < 0.08:
        name, glyph, blurb = "The Shapeshifter", "󰒓", "No single habit dominates — you listen a bit of every way."
    for t in traits:
        t["value"] = round(t["value"], 3)
        t["score"] = round(t["score"], 3)

    top_artist, top_count = ranked_artists[0]
    top_share = top_count / n
    streak_len, streak_artist = 1, lead(stream[0])
    run = 1
    for a, b in zip(stream, stream[1:]):
        run = run + 1 if lead(a) == lead(b) else 1
        if run > streak_len:
            streak_len, streak_artist = run, lead(b)

    per_day: dict[tuple, int] = defaultdict(int)
    for p, k in zip(stream, track_keys):
        lt = time.localtime(p["ts"])
        per_day[(lt.tm_year, lt.tm_yday, k)] += 1
    loop_key, loop_n = max(per_day.items(), key=lambda kv: kv[1])
    loop_p = next(p for p, k in zip(stream, track_keys) if k == loop_key[2])

    drift = None
    short = (snapshot or {}).get("topArtistsShort") or []
    long_ = (snapshot or {}).get("topArtistsLong") or []
    if short and long_:
        top_long = long_[:10]
        kept = [a for a in top_long if a in short]
        drift = {"kept": len(kept), "of": len(top_long), "keptNames": kept[:4],
                 "newcomers": [a for a in short if a not in long_][:4]}

    facts = {
        "superfan": {"artist": top_artist, "plays": top_count, "share": round(top_share, 3),
                     "vsEven": round(top_share * unique_artists, 1), "artists": unique_artists},
        "backToBack": {"artist": streak_artist, "count": streak_len},
        "loop": {"artist": loop_p["artist"], "title": loop_p.get("title", ""), "count": loop_n},
        "longestSession": {"secs": longest_secs, "plays": len(longest), "startTs": longest[0]["ts"]},
        "avgSessionPlays": round(avg_session_plays, 1),
        "sessions": len(sessions),
        "explicitShare": round(explicit_n / explicit_known, 3) if explicit_known >= 10 else None,
        "drift": drift,
    }

    return {
        "archetype": {"name": name, "glyph": glyph, "blurb": blurb, "key": main_t["key"],
                      "because": main_t["fact"],
                      "runnersUp": [{"key": t["key"], "label": t["label"], "fact": t["fact"]} for t in ranked[1:3]]},
        "traits": traits,
        "taste": taste,
        "era": era,
        "facts": facts,
        "sample": {"plays": n, "days": round(span_days, 1), "sinceTs": stream[0]["ts"],
                   "spotifyPlays": sum(1 for p in stream if p["src"] == "spotify"),
                   "localPlays": sum(1 for p in stream if p["src"] == "local")},
    }


def main():
    plays = load_history()
    cache = load_cache()
    now = time.time()

    spotify = load_spotify()
    result: dict[str, Any] = {
        "totalPlays": len(plays),
        "uniqueTracks": len({p["hash"] for p in plays}),
        "uniqueArtists": len({p.get("artist", "") for p in plays if p.get("artist")}),
        "spotify": spotify,
    }

    # Real week/month Spotify stats — from the PERSISTENT accumulator log,
    # not the live 50-track snapshot (which can't span more than a few hours
    # for a heavy listener). This only gets more complete over time; it
    # can't be backfilled since Spotify's API has no historical listening
    # data at all, only ever the last 50 plays going forward.
    sp_history = load_spotify_history()

    # Built once, reused by every enrich() call below for the art fallback.
    art_lookup: dict[str, str] = {}
    for pool in (sp_history, (spotify or {}).get("recentlyPlayed", []),
                 (spotify or {}).get("topTracksShort", []), (spotify or {}).get("topTracksLong", [])):
        for p in pool:
            if p.get("art"):
                art_lookup.setdefault(_art_key(p.get("artist", ""), p.get("title", "")), p["art"])

    def sp_window(entries, days):
        cutoff = now - days * DAY
        pool = [p for p in entries if p.get("ts", 0) >= cutoff]
        timed = [p for p in pool if isinstance(p.get("durationSec"), (int, float)) and p["durationSec"] > 0]
        artists: dict[str, int] = {}
        tracks: dict[str, dict] = {}
        for p in pool:
            for name in p.get("artist", "").split(", "):
                if name:
                    artists[name] = artists.get(name, 0) + 1
            key = p.get("id") or (p.get("artist", "") + "|" + p.get("title", ""))
            if key not in tracks:
                tracks[key] = {"artist": p.get("artist", ""), "title": p.get("title", ""), "art": p.get("art", ""), "count": 0}
            tracks[key]["count"] += 1
        top_artists = sorted(artists.items(), key=lambda kv: kv[1], reverse=True)[:8]
        top_tracks = sorted(tracks.values(), key=lambda t: t["count"], reverse=True)[:8]
        return {
            "listenSeconds": sum(p["durationSec"] for p in timed),
            "plays": len(pool),
            "trackedPlays": len(timed),
            "topArtists": top_artists,
            "topTracks": top_tracks,
        }

    if sp_history:
        oldest_ts = min(p.get("ts", now) for p in sp_history if p.get("ts"))
        history_days = round((now - oldest_ts) / DAY, 1)
        result["spotifyWeek"] = sp_window(sp_history, 7)
        result["spotifyWeek"]["spanDays"] = min(7, history_days)
        result["spotifyMonth"] = sp_window(sp_history, 30)
        result["spotifyMonth"]["spanDays"] = min(30, history_days)
        result["spotifyHistoryDays"] = history_days
    elif spotify and spotify.get("recentlyPlayed"):
        # No accumulator data yet (daemon just started / hasn't polled) —
        # fall back to the live snapshot so the UI isn't empty on day one.
        sp_recent = [p for p in spotify["recentlyPlayed"] if p.get("ts")]
        result["spotifyWeek"] = sp_window(sp_recent, 7)
        result["spotifyWeek"]["spanDays"] = round((now - min(p["ts"] for p in sp_recent)) / DAY, 1) if sp_recent else 0
        result["spotifyMonth"] = None
        result["spotifyHistoryDays"] = 0
    else:
        result["spotifyWeek"] = None
        result["spotifyMonth"] = None
        result["spotifyHistoryDays"] = 0

    try:
        result["personality"] = personality(plays, sp_history, spotify)
    except Exception:
        result["personality"] = None

    if not plays:
        result.update({
            "recentlyPlayed": [], "topAllTime": [], "topThisWeek": [],
            "bpmToday": None, "bpmOverall": None,
            "heatmapByHour": [0] * 24, "onThisDay": [],
            "listenSeconds": 0, "listenSecondsToday": 0, "trackedPlays": 0,
            "topHour": None, "firstPlayTs": None, "activeDays": 0,
        })
        print(json.dumps(result))
        return

    plays.sort(key=lambda p: p.get("ts", 0))

    # Recently played — newest first.
    recent = list(reversed(plays))[:25]
    result["recentlyPlayed"] = [enrich(p, cache, art_lookup) for p in recent]

    # Most played — all-time and this-week, by hash (title/artist can repeat
    # across hashes only if metadata changed, which is fine — same intent
    # as everywhere else in this file that keys on the artist+title hash).
    def top_n(pool, n=10):
        counts = defaultdict(int)
        latest = {}
        for p in pool:
            counts[p["hash"]] += 1
            latest[p["hash"]] = p
        ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:n]
        out = []
        for h, count in ranked:
            e = enrich(latest[h], cache, art_lookup)
            e["count"] = count
            out.append(e)
        return out

    result["topAllTime"] = top_n(plays)
    week_ago = now - 7 * DAY
    result["topThisWeek"] = top_n([p for p in plays if p.get("ts", 0) >= week_ago])

    # BPM: today vs overall — only over plays whose track actually has a
    # cached bpm (bpm_detect.py runs async and doesn't cover every track,
    # e.g. skipped/very short plays).
    def avg_bpm(pool):
        bpms = [cache.get(p["hash"], {}).get("bpm") for p in pool]
        bpms = [b for b in bpms if isinstance(b, (int, float)) and b > 0]
        return round(sum(bpms) / len(bpms), 1) if bpms else None

    today_start = now - (now % DAY)
    result["bpmToday"] = avg_bpm([p for p in plays if p.get("ts", 0) >= today_start])
    result["bpmOverall"] = avg_bpm(plays)

    # Listening-by-hour heatmap, local time.
    heatmap = [0] * 24
    for p in plays:
        try:
            heatmap[time.localtime(p["ts"]).tm_hour] += 1
        except Exception:
            pass
    result["heatmapByHour"] = heatmap
    result["topHour"] = heatmap.index(max(heatmap)) if any(heatmap) else None
    # Ranked list instead of a 24-slot grid — with a small history a full
    # hour-of-day chart is almost entirely empty columns, which reads as
    # broken rather than sparse. A top-N ranked list stays dense and
    # informative regardless of how little data exists yet.
    result["topHours"] = sorted(
        ({"hour": h, "count": c} for h, c in enumerate(heatmap) if c > 0),
        key=lambda x: x["count"], reverse=True
    )[:6]

    # Real listening time — only entries logged after durationSec was added
    # (see music_info.sh) carry it, so this is "of the plays we could time",
    # not a full-history estimate. trackedPlays tells the UI how much of
    # totalPlays that actually covers, so it can be honest about it instead
    # of implying full coverage.
    timed = [p for p in plays if isinstance(p.get("durationSec"), (int, float)) and p["durationSec"] > 0]
    result["listenSeconds"] = sum(p["durationSec"] for p in timed)
    result["trackedPlays"] = len(timed)
    result["listenSecondsToday"] = sum(
        p["durationSec"] for p in timed if p.get("ts", 0) >= today_start
    )

    result["firstPlayTs"] = plays[0]["ts"]
    result["activeDays"] = len({time.localtime(p["ts"]).tm_yday * 10000 + time.localtime(p["ts"]).tm_year for p in plays})

    # On this day — plays from a past day whose hour-of-day is within 2h of
    # right now, so it reads as "you were listening to roughly this time",
    # not just "any play from that date". Nearest match per distinct past
    # day, most recent first, capped at 5.
    on_this_day = []
    now_local = time.localtime(now)
    seen_days = set()
    for p in reversed(plays):
        ts = p.get("ts", 0)
        age_days = int((now - ts) // DAY)
        if age_days < 1:
            continue
        lt = time.localtime(ts)
        if lt.tm_mday != now_local.tm_mday or lt.tm_mon != now_local.tm_mon:
            hour_diff = abs(lt.tm_hour - now_local.tm_hour)
            if hour_diff > 2 and hour_diff < 22:
                continue
        day_key = (lt.tm_year, lt.tm_yday)
        if day_key in seen_days:
            continue
        seen_days.add(day_key)
        e = enrich(p, cache, art_lookup)
        e["daysAgo"] = age_days
        on_this_day.append(e)
        if len(on_this_day) >= 5:
            break
    result["onThisDay"] = on_this_day

    print(json.dumps(result))


if __name__ == "__main__":
    main()
