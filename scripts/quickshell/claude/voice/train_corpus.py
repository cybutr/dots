#!/usr/bin/env python3
"""Guided recording session for a personal STT/wake-word training corpus.
Prompts one line at a time (wake word / commands / reading / noisy / Czech),
captures mic via the same parec chain as stt_server.py (16kHz s16le mono),
writes WAV + a manifest.jsonl with known ground-truth text — no
transcribe-then-correct pass needed, the prompt text IS the label.

Controls per prompt: ENTER starts recording, ENTER again stops it.
  r = redo last take    s = skip this prompt    q = quit (progress saved)

Resumable: re-run any time, already-recorded prompts (by id) are skipped
unless --redo-all is passed.
"""
import argparse, json, os, subprocess, time, wave

RATE = 16000
BASE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.expanduser("~/.local/share/qs_voice_corpus")
AUDIO_DIR = os.path.join(OUT_DIR, "audio")
MANIFEST = os.path.join(OUT_DIR, "manifest.jsonl")

WAKE_CUES = [
    "normal voice, mic distance", "quiet/soft", "from across the room",
    "in a hurry, clipped", "slightly annoyed", "casual/relaxed",
    "with music playing in the background", "right after waking up (low energy)",
]

COMMANDS_EN = [
    "yo kandor, what's my battery at",
    "yo kandor, open the calendar",
    "yo kandor, mute the mic",
    "yo kandor, what's on my schedule today",
    "yo kandor, add a task, call the dentist tomorrow",
    "yo kandor, open the music popup",
    "yo kandor, what's using all the CPU right now",
    "yo kandor, switch to power saver",
    "yo kandor, mark that task done",
    "yo kandor, what's the weather like",
    "yo kandor, open the network popup",
    "yo kandor, remind me about the meeting",
    "yo kandor, lock the screen",
    "yo kandor, turn the volume down",
    "yo kandor, what notifications did I miss",
    "yo kandor, open the wallpaper picker",
    "yo kandor, how's my focus time looking today",
    "yo kandor, snooze that",
    "yo kandor, what's next on my calendar",
    "yo kandor, connect to the VPN",
]

READING_EN = [
    "So I've been meaning to clean up this config for a while now, "
    "there's a bunch of half-finished scripts sitting around that either "
    "need to get wired in properly or just deleted.",
    "The thing that annoys me most about notifications is that ninety "
    "percent of them don't actually need me to do anything, they just "
    "want to be seen and then forgotten.",
    "Honestly the wallpaper picker is one of my favorite parts of this "
    "whole setup, watching the whole palette shift live across every "
    "widget is still satisfying every single time.",
    "If the battery's draining fast and I'm not near a charger, just "
    "flip it to power saver automatically, I don't need to be asked "
    "about that one.",
    "I want this thing to feel like it's actually paying attention, not "
    "like a chatbot I have to remember to open a window for.",
]

NOISY_EN = [
    "yo kandor, what's my battery at",
    "yo kandor, mute the mic",
    "yo kandor, open the calendar",
    "yo kandor, what's next on my schedule",
    "yo kandor, add a task, pick up the package",
    "yo kandor, turn the volume down",
    "yo kandor, lock the screen",
    "yo kandor, what's using all the CPU",
    "yo kandor, connect to the VPN",
    "yo kandor, snooze that",
]

COMMANDS_CS = [
    "hej kandore, kolik mam baterie",
    "hej kandore, otevri kalendar",
    "hej kandore, ztlum mikrofon",
    "hej kandore, co mam dneska na programu",
    "hej kandore, pridej ukol, zavolat zubarovi zitra",
    "hej kandore, jak si stoji moje soustredeni dneska",
    "hej kandore, zamkni obrazovku",
    "hej kandore, uloz to jako hotove",
    "hej kandore, jake je pocasi",
    "hej kandore, pripoj se na VPN",
]


def build_prompts(categories):
    prompts = []
    if "wake" in categories:
        for i, cue in enumerate(WAKE_CUES):
            for rep in range(1, 8):   # ~8 reps per cue = ~56 total
                prompts.append({
                    "id": f"wake_{i}_{rep}", "category": "wake", "lang": "en",
                    "text": "yo kandor", "cue": cue,
                })
    if "commands" in categories:
        for i, c in enumerate(COMMANDS_EN):
            prompts.append({"id": f"cmd_{i}", "category": "commands", "lang": "en", "text": c, "cue": ""})
    if "reading" in categories:
        for i, p in enumerate(READING_EN):
            prompts.append({"id": f"read_{i}", "category": "reading", "lang": "en", "text": p, "cue": "natural pace, like talking to a person"})
    if "noisy" in categories:
        for i, c in enumerate(NOISY_EN):
            prompts.append({"id": f"noisy_{i}", "category": "noisy", "lang": "en", "text": c, "cue": "turn on music/typing/some background noise first"})
    if "czech" in categories:
        for i, c in enumerate(COMMANDS_CS):
            prompts.append({"id": f"cs_{i}", "category": "czech", "lang": "cs", "text": c, "cue": ""})
    return prompts


def load_done():
    done = set()
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            for line in f:
                try:
                    done.add(json.loads(line)["id"])
                except Exception:
                    pass
    return done


def append_manifest(entry):
    with open(MANIFEST, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def record_take(wav_path):
    proc = subprocess.Popen(
        ["parec", "--format=s16le", f"--rate={RATE}", "--channels=1"],
        stdout=subprocess.PIPE)
    t0 = time.time()
    chunks = []
    import threading
    stop = threading.Event()

    stdout = proc.stdout
    assert stdout is not None

    def pump():
        while not stop.is_set():
            chunk = stdout.read(4096)
            if not chunk:
                break
            chunks.append(chunk)

    th = threading.Thread(target=pump, daemon=True)
    th.start()
    input()   # second ENTER stops
    # parec has connection/startup latency (~100-300ms) — for short utterances
    # (e.g. the wake phrase alone) stopping immediately could terminate it before
    # any audio has flowed at all, yielding a silent/empty take. Floor the total
    # capture at 600ms and give a short grace period so in-flight audio lands.
    MIN_CAPTURE_S = 0.6
    elapsed = time.time() - t0
    if elapsed < MIN_CAPTURE_S:
        time.sleep(MIN_CAPTURE_S - elapsed)
    time.sleep(0.15)
    stop.set()
    proc.terminate()
    th.join(timeout=1)
    try:
        proc.wait(timeout=1)
    except Exception:
        proc.kill()
    dur = time.time() - t0
    pcm = b"".join(chunks)
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)
    return dur


def run(prompts, redo_all):
    os.makedirs(AUDIO_DIR, exist_ok=True)
    done = set() if redo_all else load_done()
    todo = [p for p in prompts if p["id"] not in done]
    if not todo:
        print(f"Nothing left to record ({len(prompts)} prompts already done). "
              f"Pass --redo-all to re-record everything.")
        return
    print(f"{len(todo)} prompts to go (of {len(prompts)} total). "
          f"ENTER starts recording, ENTER again stops. 'r'=redo, 's'=skip, 'q'=quit.\n")
    i = 0
    while i < len(todo):
        p = todo[i]
        wav_path = os.path.join(AUDIO_DIR, p["id"] + ".wav")
        print(f"[{i+1}/{len(todo)}] ({p['category']}/{p['lang']}"
              f"{', ' + p['cue'] if p['cue'] else ''})")
        print(f'  say: "{p["text"]}"')
        choice = input("  [ENTER=record, s=skip, q=quit] ").strip().lower()
        if choice == "q":
            print("Stopped. Progress saved, re-run to resume.")
            return
        if choice == "s":
            i += 1
            continue
        print("  recording... (ENTER to stop)")
        dur = record_take(wav_path)
        if os.path.getsize(wav_path) <= 44:   # bare WAV header, no audio captured
            print("  got nothing (empty take) — recording again automatically")
            continue
        print(f"  captured {dur:.1f}s -> {wav_path}")
        redo = input("  [ENTER=keep, r=redo this line] ").strip().lower()
        if redo == "r":
            continue   # re-record same prompt, don't advance
        append_manifest({**p, "wav": wav_path, "duration": round(dur, 2),
                          "ts": int(time.time())})
        i += 1
    print(f"\nDone. Manifest: {MANIFEST}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--categories", default="wake,commands,reading",
                     help="comma list: wake,commands,reading,noisy,czech,all (default: wake,commands,reading)")
    ap.add_argument("--redo-all", action="store_true")
    args = ap.parse_args()
    cats = set(args.categories.split(","))
    if "all" in cats:
        cats = {"wake", "commands", "reading", "noisy", "czech"}
    prompts = build_prompts(cats)
    run(prompts, args.redo_all)
