#!/usr/bin/env python3
"""Watches for wifi (SSID) changes and, when the machine joins a wifi the user has
marked as an auto-VPN spot (via vpn_control autolearn, or 3 observed connected
sessions), connects ProtonVPN automatically. Otherwise stays idle — it never
connects on an unknown network, and never disconnects on its own.

Reuses the exact logic in qs_mcp.t_vpn_control so there's one source of truth.
Reacts to NetworkManager events via `nmcli monitor` (no polling loop)."""
import os, sys, time, subprocess, signal

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
PIDFILE = "/tmp/qs_vpn_autoconnect.pid"

import importlib.util
spec = importlib.util.spec_from_file_location("qs_mcp", os.path.join(BASE, "qs_mcp.py"))
qs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qs)


def log(*a):
    print("[vpn-auto]", *a, file=sys.stderr, flush=True)


def already_running():
    if os.path.exists(PIDFILE):
        try:
            os.kill(int(open(PIDFILE).read().strip()), 0)
            return True
        except (OSError, ValueError):
            pass
    open(PIDFILE, "w").write(str(os.getpid()))
    return False


def handle_ssid_change():
    ssid = qs._current_ssid()
    if not ssid:
        return
    # observe (bumps the learn counter) then autocheck (connects if learned + off)
    qs.t_vpn_control({"action": "observe"})
    res = qs.t_vpn_control({"action": "autocheck"})
    if res.get("action") == "connected":
        log(f"joined learned wifi '{ssid}' → connected ProtonVPN")
        try:
            subprocess.run(["notify-send", "-a", "Claude", "-u", "low",
                            "-i", "network-vpn", "ProtonVPN",
                            f"Auto-connected on {ssid}"], timeout=5)
        except Exception:
            pass


def main():
    if already_running():
        sys.exit(0)
    signal.signal(signal.SIGTERM, lambda *_: (os.path.exists(PIDFILE) and os.unlink(PIDFILE), sys.exit(0)))

    # act once on startup for the current network
    handle_ssid_change()

    last = qs._current_ssid()
    # nmcli monitor emits a line on any connectivity/device change; debounce + diff SSID
    proc = subprocess.Popen(["nmcli", "monitor"], stdout=subprocess.PIPE, text=True)
    try:
        for _ in proc.stdout:
            time.sleep(1.5)  # let the connection settle before reading SSID
            cur = qs._current_ssid()
            if cur != last:
                last = cur
                if cur:
                    handle_ssid_change()
    finally:
        if os.path.exists(PIDFILE):
            os.unlink(PIDFILE)
        proc.terminate()


if __name__ == "__main__":
    main()
