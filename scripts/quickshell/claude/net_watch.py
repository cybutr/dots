#!/usr/bin/env python3
"""#15 unknown-wifi.
Polls the connected SSID; the first time it sees one that isn't in the
known set, asks Haiku for a one-line risk note (open/public/captive-portal
guess from nmcli security info) and surfaces a card with a VPN-connect
action. Known SSIDs persist to a state file so this only ever fires once
per network."""
import os, sys, json, subprocess, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import resident_card
except Exception:
    resident_card = None

try:
    from claude_say import say
except Exception:
    def say(*a, **k): return ""

try:
    from claude_resident import save, load, notify, SUGGEST, PERSONA, QS_MANAGER, settings
except Exception:
    def load(path, default):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:
            return default

    def save(path, obj):
        try:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(obj, f)
            os.replace(tmp, path)
        except OSError:
            pass

    def notify(title, body, urgency):
        try:
            subprocess.run(["notify-send", "-a", "Claude", "-u", urgency,
                            "-i", "dialog-information", title, body], timeout=5, check=False)
        except Exception:
            pass

    SUGGEST = "/tmp/qs_resident_suggestion"
    PERSONA = ("You are the user's ambient desktop assistant living in their Hyprland shell. "
               "Reply with ONE short line, warm and practical, under 20 words. "
               "No greeting, no sign-off, no quotes, no markdown.")
    QS_MANAGER = os.path.join(os.path.expanduser("~"), ".config/hypr/scripts/qs_manager.sh")
    SETTINGS_FILE = os.path.join(os.path.expanduser("~"), ".config/hypr/settings.json")

    def settings():
        return load(SETTINGS_FILE, {})

PID = "/tmp/qs_net_watch.pid"
STATE = "/tmp/qs_net_watch_known.json"
POLL = 30
MAILBOX = "/tmp/qs_claude_mailbox.json"


def mailbox_post(to, msg, frm="net_watch"):
    try:
        try:
            with open(MAILBOX) as f:
                msgs = json.load(f)
        except Exception:
            msgs = []
        msgs.append({"id": int(time.time() * 1000), "from": frm, "to": to, "msg": msg,
                     "ts": int(time.time()), "read": False})
        tmp = MAILBOX + ".tmp"
        with open(tmp, "w") as f:
            json.dump(msgs[-100:], f)
        os.replace(tmp, MAILBOX)
    except OSError:
        pass


def _current_ssid():
    try:
        r = subprocess.run(["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"],
                            capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            parts = line.split(":", 1)
            if len(parts) == 2 and parts[0] == "yes" and parts[1]:
                return parts[1]
    except Exception:
        pass
    return ""


def _security(ssid):
    try:
        r = subprocess.run(["nmcli", "-t", "-f", "ssid,security", "dev", "wifi"],
                            capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            parts = line.split(":", 1)
            if len(parts) == 2 and parts[0] == ssid:
                return parts[1] or "open (no security advertised)"
    except Exception:
        pass
    return "unknown"


def main():
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))

    known = set(load(STATE, []))
    last_ssid = ""

    while True:
        time.sleep(POLL)
        ssid = _current_ssid()
        if not ssid or ssid == last_ssid:
            continue
        prev_ssid, last_ssid = last_ssid, ssid

        if ssid in known:
            # Known network, just a switch (not first-ever-seen) — a plain,
            # low-urgency "switched networks" note, gated by the same device
            # alerts toggle as the USB/BT connect cards (#3 device alerts).
            if prev_ssid and settings().get("residentDeviceAlerts", True) and resident_card is not None:
                resident_card.emit("Switched wifi network", f"Now on '{ssid}' (was '{prev_ssid}')",
                                   "network-wireless", "low", None, [], "resident",
                                   "wifi-switch-" + str(int(time.time())))
            continue
        known.add(ssid)
        save(STATE, sorted(known))
        security = _security(ssid)
        out = say(f"Just connected to wifi network '{ssid}', security: {security!r}. In ONE "
                  f"short line, note any risk — is it likely open/public/a captive portal, "
                  f"and is a VPN worth it here. Under 20 words, no greeting.",
                  system=PERSONA, timeout=15).strip()
        msg = out or f"connected to '{ssid}' ({security}) for the first time"
        # No raw notify here when resident_card is available — the emit()
        # below already surfaces this (with the connect-vpn action attached),
        # so a notify-send here would just be a duplicate popup for the same
        # event. Only fall back to notify-send if the card queue is missing.
        if resident_card is None:
            notify("Claude", msg, "low")
        save(SUGGEST, {"key": "unknown_wifi_" + ssid, "msg": msg, "urgency": "low",
                       "ts": int(time.time()), "action_label": "connect vpn",
                       "action_cmd": "protonvpn connect", "label": "new wifi"})
        if resident_card is not None:
            resident_card.emit(
                f"New network: {ssid}", msg, "network-wireless", "low", None,
                [{"label": "open network", "cmd": f"bash {QS_MANAGER} open network"},
                 {"label": "connect vpn", "cmd": "protonvpn connect"}],
                "resident", "wifi-" + ssid)
            # Discrete connect event, not an ongoing condition — border-pulse
            # reads as "look here now" better than the ambient wash.
            resident_card.pill_flag("wifi", urgency="low", style="border")
        mailbox_post("user", f"First-time network: {ssid} — {msg}")


if __name__ == "__main__":
    main()
