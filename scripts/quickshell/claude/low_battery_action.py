#!/usr/bin/env python3
"""Card-action backend for the low-battery emergency proposed by
resident_extras.py's tick_low_battery(). Two modes, dispatched from
resident_actions.sh:

  --emergency   snapshot the current ecoFreezeSecs/ecoThrottleSecs (and
                power profile) into a prior-state marker, then push both
                settings to aggressive values and switch to power-saver.
                eco_daemon.py already hot-reloads settings.json, so this
                never needs a daemon restart.
  --restore     put ecoFreezeSecs/ecoThrottleSecs (and profile) back to
                whatever was actually running before --emergency, not
                hardcoded defaults. No-op if there's no prior snapshot.
"""
import json
import os
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
SETTINGS_FILE = os.path.join(HOME, ".config/hypr/settings.json")
PRIOR_FILE = "/tmp/qs_low_battery_prior.json"

EMERGENCY_FREEZE_SECS = 5
EMERGENCY_THROTTLE_SECS = 5
FALLBACK_FREEZE_SECS = 300
FALLBACK_THROTTLE_SECS = 20


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def _save(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)


def _current_profile():
    try:
        out = subprocess.run(["powerprofilesctl", "get"], capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or None
    except Exception:
        return None


def emergency():
    s = _load(SETTINGS_FILE, {})
    if not os.path.exists(PRIOR_FILE):
        prior = {
            "ecoFreezeSecs": s.get("ecoFreezeSecs", FALLBACK_FREEZE_SECS),
            "ecoThrottleSecs": s.get("ecoThrottleSecs", FALLBACK_THROTTLE_SECS),
            "profile": _current_profile(),
            "ts": int(time.time()),
        }
        _save(PRIOR_FILE, prior)
    s["ecoFreezeSecs"] = EMERGENCY_FREEZE_SECS
    s["ecoThrottleSecs"] = EMERGENCY_THROTTLE_SECS
    _save(SETTINGS_FILE, s)
    try:
        subprocess.run(["powerprofilesctl", "set", "power-saver"], timeout=5)
    except Exception:
        pass
    print(f"emergency power-save applied: freeze/throttle -> "
          f"{EMERGENCY_FREEZE_SECS}s/{EMERGENCY_THROTTLE_SECS}s, power-saver profile")


def restore():
    prior = _load(PRIOR_FILE, None)
    s = _load(SETTINGS_FILE, {})
    if prior is None:
        s["ecoFreezeSecs"] = FALLBACK_FREEZE_SECS
        s["ecoThrottleSecs"] = FALLBACK_THROTTLE_SECS
        _save(SETTINGS_FILE, s)
        print("no prior snapshot found — restored to repo defaults "
              f"({FALLBACK_FREEZE_SECS}s/{FALLBACK_THROTTLE_SECS}s)")
        return
    s["ecoFreezeSecs"] = prior.get("ecoFreezeSecs", FALLBACK_FREEZE_SECS)
    s["ecoThrottleSecs"] = prior.get("ecoThrottleSecs", FALLBACK_THROTTLE_SECS)
    _save(SETTINGS_FILE, s)
    profile = prior.get("profile")
    if profile:
        try:
            subprocess.run(["powerprofilesctl", "set", profile], timeout=5)
        except Exception:
            pass
    try:
        os.remove(PRIOR_FILE)
    except OSError:
        pass
    print(f"restored eco settings: freeze={s['ecoFreezeSecs']}s throttle={s['ecoThrottleSecs']}s"
          + (f", profile={profile}" if profile else ""))


def main():
    if "--emergency" in sys.argv:
        emergency()
    elif "--restore" in sys.argv:
        restore()
    else:
        print("usage: low_battery_action.py --emergency | --restore")
        sys.exit(1)


if __name__ == "__main__":
    main()
