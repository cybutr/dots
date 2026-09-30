#!/usr/bin/env python3
"""Active USB / Bluetooth connect alerts. Passive polling of both already
exists for the clock hover card (TopBar.qml's clockWiredReader/clockBtReader)
— this is the "notice a NEW connection and surface a low-urgency card"
counterpart, same PID-guard autostart pattern as net_watch.py/focus_insight.py.

USB reuses list_wired_devices.sh (the exact filter TopBar.qml's hover card
uses) rather than reimplementing lsusb parsing a second time. Bluetooth
reuses bluetooth_panel_logic.sh --status's connected list the same way.

Connect-only by design — a disconnect note for every USB stick unplug or
Bluetooth drop would be noisy for little benefit; skipped per the brief's
own bias-toward-connect-only guidance."""
import os, sys, json, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import resident_card
except Exception:
    resident_card = None

HOME = os.path.expanduser("~")
QS = os.path.join(HOME, ".config/hypr/scripts/quickshell")
SETTINGS_FILE = os.path.join(HOME, ".config/hypr/settings.json")
WIRED_SH = os.path.join(HERE, "list_wired_devices.sh")
BT_SH = os.path.join(QS, "network/bluetooth_panel_logic.sh")
PID = "/tmp/qs_device_watch.pid"
POLL = 12
MAILBOX = "/tmp/qs_claude_mailbox.json"


def mailbox_post(to, msg, frm="device_watch"):
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


def settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _run_json(cmd, timeout=6):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
        return json.loads(out.strip() or "{}")
    except Exception:
        return {}


def _wired_ids():
    d = _run_json(["bash", WIRED_SH])
    out = {}
    for w in d.get("wired") or []:
        key = w.get("id") or w.get("name")
        if key:
            out[key] = w.get("name", key)
    return out


def _bt_ids():
    d = _run_json(["bash", BT_SH, "--status"])
    out = {}
    for c in d.get("connected") or []:
        key = c.get("mac") or c.get("id") or c.get("name")
        if key:
            out[key] = c.get("name", key)
    return out


def main():
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read().strip()), 0)
            sys.exit(0)
        except (OSError, ValueError):
            pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))

    known_wired = set(_wired_ids())
    known_bt = set(_bt_ids())
    first = True

    while True:
        if not settings().get("residentDeviceAlerts", True):
            time.sleep(POLL)
            continue

        wired = _wired_ids()
        bt = _bt_ids()

        if not first:
            for key, name in wired.items():
                if key in known_wired:
                    continue
                if resident_card is not None:
                    resident_card.emit("USB device connected", name, "drive-removable-media",
                                       "low", None, [], "resident", "usb-connect-" + str(int(time.time())))
            for key, name in bt.items():
                if key in known_bt:
                    continue
                if resident_card is not None:
                    resident_card.emit("Bluetooth connected", name, "bluetooth-active",
                                       "low", None, [], "resident", "bt-connect-" + str(int(time.time())))
                mailbox_post("user", f"Bluetooth connected: {name}")

        known_wired, known_bt, first = set(wired), set(bt), False
        time.sleep(POLL)


if __name__ == "__main__":
    main()
