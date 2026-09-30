#!/usr/bin/env python3
"""
qs_probe.py — safe, precise screen interaction for Claude Code on this Hyprland/
Wayland desktop, so verifying/demoing UI changes never needs blind coordinate
guessing again. Built after a guessed ydotool click landed on the topbar and
stole focus to an unrelated window.

Loop this is built for:
  1. shot              — full screenshot, prints path + monitor size
  2. crop X Y W H      — crop+2x-zoom a region of the LATEST screenshot, prints
                          the crop path and the origin/zoom needed to convert a
                          pixel you read off the crop back to real screen coords
  3. (read the crop image, pick a point, convert: real = origin + displayed/zoom)
  4. click X Y         — move+click at that real, absolute coordinate — refuses
                          anything inside the topbar's reserved strip unless
                          --force is passed, since that's the one band that's
                          never part of a card and the one mistake already made
  5. shot again to confirm the result

Never guess Y from "looks about right" — always crop wide, read the actual
pixel position off the image, then click exactly there.

For QML cards: manifest/find/clickel read CardRenderer.qml's own self-reported
element geometry+state (QS_PROBE_DEBUG=1) — zero screenshots, zero vision tokens.

For the browser: bfind/bclick/btype talk to Vivaldi's CDP debug port (:9222,
already used by qs_mcp.py's browser_eval) and click natively inside the page via
Input.dispatchMouseEvent at exact viewport coordinates from getBoundingClientRect —
no OS-level coordinate translation, no window-focus race, immune to the ydotool
scale-factor bug that affects real desktop clicks.
"""
import os, json, subprocess, argparse, time
import qs_mcp

SCREENSHOT_SH = os.path.expanduser("~/.config/hypr/scripts/screenshot.sh")
SHOTS_DIR = os.path.expanduser("~/Images/Screenshots")
PINNED = os.path.expanduser("~/.cache/quickshell/claude/pinned_cards.json")
SETTINGS = os.path.expanduser("~/.config/hypr/settings.json")

TOPBAR_BASE_HEIGHT = 48 + 4  # barHeight + exclusiveZone margin, at scale 1 — TopBar.qml


def monitor_geometry():
    out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, check=True).stdout
    mons = json.loads(out)
    m = mons[0]
    return m["width"], m["height"]


def ui_scale():
    try:
        return float(json.load(open(SETTINGS)).get("uiScale", 1.0))
    except Exception:
        return 1.0


def scale_factor():
    mw, _ = monitor_geometry()
    r = mw / 1920.0
    base = max(0.35, r ** 0.85) if r <= 1.0 else r ** 0.5
    return base * ui_scale()


def topbar_height():
    return round(TOPBAR_BASE_HEIGHT * scale_factor())


def latest_screenshot():
    files = [os.path.join(SHOTS_DIR, f) for f in os.listdir(SHOTS_DIR) if f.endswith(".png")]
    if not files:
        raise SystemExit("no screenshots found in " + SHOTS_DIR)
    return max(files, key=os.path.getmtime)


def ensure_special_workspace_closed():
    """This very Claude Code session runs in a kitty terminal on Hyprland's special
    scratchpad workspace ('magic') — when that's toggled open it renders above
    everything, including layer-shell overlays, so a screenshot taken while it's
    open captures this terminal instead of the actual desktop. Close it first,
    every time, since there's no cheap way to check "is it currently open" — closing
    an already-closed special workspace is a harmless no-op."""
    aw = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True)
    try:
        info = json.loads(aw.stdout)
        if info.get("workspace", {}).get("name") == "special:magic":
            subprocess.run(["hyprctl", "dispatch", "togglespecialworkspace", "magic"], check=True)
            time.sleep(0.3)
    except Exception:
        pass


def take_shot():
    ensure_special_workspace_closed()
    before = set(os.listdir(SHOTS_DIR)) if os.path.isdir(SHOTS_DIR) else set()
    subprocess.run(["bash", SCREENSHOT_SH, "--full"], check=True)
    # screenshot.sh can background itself — poll briefly for the new file to land
    for _ in range(40):
        after = set(os.listdir(SHOTS_DIR)) if os.path.isdir(SHOTS_DIR) else set()
        new = after - before
        if new:
            return os.path.join(SHOTS_DIR, sorted(new)[-1])
        time.sleep(0.25)
    return latest_screenshot()


def crop(x, y, w, h, zoom=2, out="/tmp/qs_probe_crop.png"):
    from PIL import Image
    path = take_shot()
    im = Image.open(path)
    mw, mh = im.size
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(mw, int(x + w)), min(mh, int(y + h))
    c = im.crop((x0, y0, x1, y1))
    c = c.resize((c.width * zoom, c.height * zoom))
    c.save(out)
    return {"crop_path": out, "source": path, "origin_x": x0, "origin_y": y0, "zoom": zoom,
            "note": "real_x = origin_x + displayed_x/zoom, real_y = origin_y + displayed_y/zoom"}


MANIFEST = os.path.expanduser("~/.cache/quickshell/claude/ui_manifest.json")


def manifest_lookup(selector):
    """selector is 'card_key:element_name', e.g. 'probe_test_1:block0_select'. Requires
    QS_PROBE_DEBUG=1 to have been set when the card's process was spawned — CardRenderer.qml
    only writes this file when that's set, zero overhead otherwise."""
    if ":" not in selector:
        raise SystemExit("selector must be 'card_key:element_name' — see 'qs_probe.py manifest' for what's available")
    card_key, el = selector.split(":", 1)
    try:
        m = json.load(open(MANIFEST))
    except Exception:
        raise SystemExit(f"{MANIFEST} missing/unreadable — is QS_PROBE_DEBUG=1 set for the card's process?")
    if card_key not in m:
        raise SystemExit(f"no card {card_key!r} in manifest — known: {list(m.keys())}")
    if el not in m[card_key]:
        raise SystemExit(f"no element {el!r} on {card_key!r} — known: {list(m[card_key].keys())}")
    return m[card_key][el]


def browser_active_tab(tab_id=""):
    try:
        tabs = json.loads(qs_mcp._cdp("/json/list"))
    except Exception as e:
        raise SystemExit(f"Vivaldi CDP not reachable on :9222 ({e}) — is Vivaldi running with --remote-debugging-port=9222?")
    pages = [t for t in tabs if t.get("type") == "page"]
    if not pages:
        raise SystemExit("no open browser tabs")
    tab = next((t for t in pages if t["id"] == tab_id), None) if tab_id else pages[0]
    if tab is None:
        raise SystemExit(f"tab {tab_id!r} not found — known: {[t['id'] for t in pages]}")
    if not tab.get("webSocketDebuggerUrl"):
        raise SystemExit(f"tab {tab['id']!r} has no debugger websocket url")
    return tab


def browser_rect(selector, tab_id=""):
    tab = browser_active_tab(tab_id)
    expr = (
        "(function(){var e=document.querySelector(%s); if(!e) return null; "
        "e.scrollIntoView({block:'center', inline:'center'}); "
        "var r=e.getBoundingClientRect(); "
        "return JSON.stringify({x:r.x,y:r.y,w:r.width,h:r.height,"
        "text:(e.innerText||e.value||'').slice(0,80),tag:e.tagName});})()"
    ) % json.dumps(selector)
    resp = qs_mcp._cdp_ws_eval(tab["webSocketDebuggerUrl"], expr)
    if resp.get("result", {}).get("exceptionDetails"):
        raise SystemExit("JS exception: " + resp["result"]["exceptionDetails"].get("text", "?"))
    val = resp.get("result", {}).get("result", {}).get("value")
    if val is None:
        raise SystemExit(f"selector {selector!r} matched nothing on tab {tab['id']!r}")
    return json.loads(val), tab


def browser_click(selector, tab_id=""):
    rect, tab = browser_rect(selector, tab_id)
    cx, cy = rect["x"] + rect["w"] / 2, rect["y"] + rect["h"] / 2
    results = qs_mcp._cdp_ws_send(tab["webSocketDebuggerUrl"], [
        {"method": "Input.dispatchMouseEvent", "params": {"type": "mouseMoved", "x": cx, "y": cy}},
        {"method": "Input.dispatchMouseEvent", "params": {"type": "mousePressed", "x": cx, "y": cy, "button": "left", "clickCount": 1}},
        {"method": "Input.dispatchMouseEvent", "params": {"type": "mouseReleased", "x": cx, "y": cy, "button": "left", "clickCount": 1}},
    ])
    for r in results:
        if r.get("error"):
            raise SystemExit("CDP error: " + json.dumps(r["error"]))
    return {"selector": selector, "rect": rect, "clicked": [cx, cy]}


def browser_type(selector, text, tab_id=""):
    click_result = browser_click(selector, tab_id)
    tab = browser_active_tab(tab_id)
    results = qs_mcp._cdp_ws_send(tab["webSocketDebuggerUrl"], [
        {"method": "Input.insertText", "params": {"text": text}},
    ])
    for r in results:
        if r.get("error"):
            raise SystemExit("CDP error: " + json.dumps(r["error"]))
    return {"selector": selector, "typed": text, "clicked_rect": click_result["rect"]}


def atspi_init():
    """GTK/Qt only export their accessibility tree when toolkit-accessibility is on.
    With it off, app nodes report children=0 and this whole tier is dead — so fail
    loud with the exact gsettings command rather than returning empty trees."""
    try:
        tk = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "toolkit-accessibility"],
                            capture_output=True, text=True).stdout.strip()
    except Exception:
        tk = "true"
    if tk == "false":
        raise SystemExit("accessibility is OFF — enable it then relaunch the app:\n"
                         "  gsettings set org.gnome.desktop.interface toolkit-accessibility true")
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
    Atspi.init()
    return Atspi


def atspi_apps(Atspi):
    d = Atspi.get_desktop(0)
    out = []
    for i in range(d.get_child_count()):
        a = d.get_child_at_index(i)
        if a is None:
            continue
        try:
            out.append((a.get_name() or "", a))
        except Exception:
            pass
    return out


def atspi_app(Atspi, name):
    matches = [a for n, a in atspi_apps(Atspi) if name.lower() in n.lower()]
    if not matches:
        known = sorted({n for n, _ in atspi_apps(Atspi) if n})
        raise SystemExit(f"no a11y app matching {name!r} — known: {known}")
    return matches[0]


def atspi_resolve(Atspi, app, query):
    """query is either a path index like '0/3/1' (re-resolve the exact node afind
    reported) or a free-text name/role substring (first match, depth-first)."""
    parts = [p for p in query.split("/") if p != ""]
    if parts and all(p.isdigit() for p in parts):
        n = app
        for idx in [int(p) for p in parts[1:]]:
            if n is None or idx >= n.get_child_count():
                raise SystemExit(f"path {query!r} does not resolve under this app")
            n = n.get_child_at_index(idx)
        return n
    q = query.lower()
    found = []

    def walk(n):
        if found or n is None:
            return
        try:
            if q in (n.get_name() or "").lower() or q in n.get_role_name().lower():
                found.append(n)
                return
        except Exception:
            return
        for i in range(n.get_child_count()):
            walk(n.get_child_at_index(i))

    walk(app)
    if not found:
        raise SystemExit(f"no node matching {query!r} under this app")
    return found[0]


def atspi_actions(Atspi, n):
    if not n.is_action():
        return []
    try:
        return [Atspi.Action.get_action_name(n, j) for j in range(Atspi.Action.get_n_actions(n))]
    except Exception:
        return []


def atspi_rect_window(Atspi, n):
    """GTK on Wayland reports a bogus (0,0) origin for CoordType.SCREEN but correct
    WINDOW-relative extents — so screen coords must be computed as the Hyprland
    window origin plus these. Returns None if there's no Component interface."""
    if not n.is_component():
        return None
    try:
        e = Atspi.Component.get_extents(n, Atspi.CoordType.WINDOW)
        return {"x": e.x, "y": e.y, "w": e.width, "h": e.height}
    except Exception:
        return None


def atspi_window_origin(Atspi, app):
    """Map an AT-SPI app to its Hyprland window to recover the real screen origin
    that CoordType.SCREEN refuses to give. Match the frame name against client
    titles, then fall back to a class-name substring of the app name."""
    frame_name = ""
    for i in range(app.get_child_count()):
        c = app.get_child_at_index(i)
        if c and c.get_role_name() == "frame":
            frame_name = c.get_name() or ""
            break
    app_name = (app.get_name() or "").lower()
    clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
    for c in clients:
        if frame_name and c.get("title") == frame_name:
            return tuple(c["at"])
    for c in clients:
        if app_name and app_name in c.get("class", "").lower():
            return tuple(c["at"])
    return None


def atspi_screen_center(Atspi, app, n):
    r = atspi_rect_window(Atspi, n)
    if r is None:
        raise SystemExit("node has no Component interface — cannot derive coordinates")
    origin = atspi_window_origin(Atspi, app)
    if origin is None:
        raise SystemExit("could not map this app to a Hyprland window for its screen origin")
    return origin[0] + r["x"] + r["w"] / 2, origin[1] + r["y"] + r["h"] / 2


def atspi_tree(Atspi, app, depth):
    lines = []

    def walk(n, d, path):
        if n is None or d > depth:
            return
        try:
            role = n.get_role_name(); name = n.get_name() or ""
        except Exception:
            return
        acts = atspi_actions(Atspi, n)
        r = atspi_rect_window(Atspi, n)
        tag = "  " * d + f"{path} [{role}] {name!r} kids={n.get_child_count()}"
        if acts:
            tag += " A:" + ",".join(acts)
        if r is not None:
            tag += f" C(win {r['x']},{r['y']} {r['w']}x{r['h']})"
        lines.append(tag)
        for i in range(n.get_child_count()):
            walk(n.get_child_at_index(i), d + 1, path + "/" + str(i))

    walk(app, 0, "0")
    return "\n".join(lines)


def atspi_find(Atspi, app, query):
    q = query.lower()
    out = []

    def walk(n, path):
        if n is None:
            return
        try:
            role = n.get_role_name(); name = n.get_name() or ""
        except Exception:
            return
        if q in name.lower() or q in role.lower():
            acts = atspi_actions(Atspi, n)
            r = atspi_rect_window(Atspi, n)
            out.append({"path_index": path, "role": role, "name": name,
                        "has_action": n.is_action(), "actions": acts, "rect": r})
        for i in range(n.get_child_count()):
            walk(n.get_child_at_index(i), path + "/" + str(i))

    walk(app, "0")
    return out


CLICK_ACTIONS = {"click", "press", "activate", "jump", "open"}


def atspi_click(Atspi, app_name, query, force=False):
    app = atspi_app(Atspi, app_name)
    n = atspi_resolve(Atspi, app, query)
    node = {"role": n.get_role_name(), "name": n.get_name() or ""}
    acts = atspi_actions(Atspi, n)
    idx = next((j for j, a in enumerate(acts) if a.lower() in CLICK_ACTIONS), 0 if acts else None)
    if idx is not None:
        ok = bool(Atspi.Action.do_action(n, idx))
        return {"method": "action", "action": acts[idx], "node": node, "ok": ok}
    cx, cy = atspi_screen_center(Atspi, app, n)
    ensure_special_workspace_closed()
    move_click(cx, cy, force=force)
    return {"method": "coord", "node": node, "clicked": [round(cx), round(cy)], "ok": True}


def card_rect(card_id):
    pins = json.load(open(PINNED))
    e = next((p for p in pins if p.get("spec", {}).get("card_id") == card_id), None)
    if not e:
        raise SystemExit(f"card_id {card_id!r} not found in {PINNED}")
    return {"x": e.get("x", 0), "y": e.get("y", 0), "w": e.get("w", round(360 * scale_factor())),
            "h": e.get("h"), "compact": e.get("compact"), "id": e.get("id")}


def cursor_pos():
    out = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True, check=True).stdout.strip()
    x, y = out.split(",")
    return int(x.strip()), int(y.strip())


def move_click(x, y, force=False):
    if not force and y < topbar_height():
        raise SystemExit(
            f"refusing: y={y} is inside the topbar's reserved strip (0-{topbar_height()}) — "
            "this is exactly the mistake that stole focus to another window last time. "
            "Pass --force only if you've actually confirmed this is intentional."
        )
    # ydotool's `mousemove` (both --absolute and relative) reports at exactly 2x the
    # real screen-pixel distance on this system (confirmed: a relative move of (1553,255)
    # from (0,0) landed the cursor at (1919,510) — clamped X, but Y=510 is precisely
    # 255*2). Calibrate by forcing the cursor to the known (0,0) corner with a deliberately
    # oversized negative move (clamps there, immune to the scale factor), then walk the
    # *halved* relative delta to land on the real target pixel.
    subprocess.run(["ydotool", "mousemove", "-x", "-5000", "-y", "-5000"], check=True)
    time.sleep(0.1)
    cx, cy = cursor_pos()
    if (cx, cy) != (0, 0):
        raise SystemExit(f"calibration failed: expected cursor at (0,0) after the oversized move, got ({cx},{cy})")
    subprocess.run(["ydotool", "mousemove", "-x", str(round(x / 2)), "-y", str(round(y / 2))], check=True)
    time.sleep(0.1)
    cx, cy = cursor_pos()
    if abs(cx - x) > 2 or abs(cy - y) > 2:
        raise SystemExit(f"move landed at ({cx},{cy}), not near the requested ({int(x)},{int(y)}) — refusing to click blind")
    time.sleep(0.15)
    subprocess.run(["ydotool", "click", "0xC0"], check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("shot")
    sub.add_parser("monitor")
    sub.add_parser("topbar")

    pc = sub.add_parser("crop")
    pc.add_argument("x", type=float); pc.add_argument("y", type=float)
    pc.add_argument("w", type=float); pc.add_argument("h", type=float)
    pc.add_argument("--zoom", type=int, default=2)

    pr = sub.add_parser("cardrect")
    pr.add_argument("card_id")

    pcc = sub.add_parser("cardcrop")
    pcc.add_argument("card_id")
    pcc.add_argument("--height", type=float, default=400)
    pcc.add_argument("--pad", type=float, default=12)
    pcc.add_argument("--zoom", type=int, default=2)

    pk = sub.add_parser("click")
    pk.add_argument("x", type=float); pk.add_argument("y", type=float)
    pk.add_argument("--force", action="store_true")

    sub.add_parser("manifest")

    pf = sub.add_parser("find")
    pf.add_argument("selector")

    pe = sub.add_parser("clickel")
    pe.add_argument("selector")
    pe.add_argument("--force", action="store_true")

    pbf = sub.add_parser("bfind")
    pbf.add_argument("selector"); pbf.add_argument("--tab", default="")

    pbc = sub.add_parser("bclick")
    pbc.add_argument("selector"); pbc.add_argument("--tab", default="")

    pbt = sub.add_parser("btype")
    pbt.add_argument("selector"); pbt.add_argument("text"); pbt.add_argument("--tab", default="")

    pat = sub.add_parser("atree")
    pat.add_argument("--app", default=""); pat.add_argument("--depth", type=int, default=12)

    paf = sub.add_parser("afind")
    paf.add_argument("app"); paf.add_argument("query")

    pac = sub.add_parser("aclick")
    pac.add_argument("app"); pac.add_argument("query"); pac.add_argument("--force", action="store_true")

    args = ap.parse_args()

    if args.cmd == "shot":
        print(json.dumps({"path": take_shot()}))
    elif args.cmd == "monitor":
        w, h = monitor_geometry()
        print(json.dumps({"width": w, "height": h, "scale": scale_factor()}))
    elif args.cmd == "topbar":
        print(json.dumps({"height": topbar_height()}))
    elif args.cmd == "crop":
        print(json.dumps(crop(args.x, args.y, args.w, args.h, args.zoom)))
    elif args.cmd == "cardrect":
        print(json.dumps(card_rect(args.card_id)))
    elif args.cmd == "cardcrop":
        r = card_rect(args.card_id)
        print(json.dumps(crop(r["x"] - args.pad, r["y"] - args.pad,
                               r["w"] + 2 * args.pad, args.height, args.zoom)))
    elif args.cmd == "click":
        move_click(args.x, args.y, force=args.force)
        print(json.dumps({"clicked": [args.x, args.y]}))
    elif args.cmd == "manifest":
        try:
            print(json.dumps(json.load(open(MANIFEST)), indent=2))
        except Exception:
            print(json.dumps({}))
    elif args.cmd == "find":
        print(json.dumps(manifest_lookup(args.selector)))
    elif args.cmd == "clickel":
        r = manifest_lookup(args.selector)
        cx, cy = r["x"] + r["w"] / 2, r["y"] + r["h"] / 2
        move_click(cx, cy, force=args.force)
        print(json.dumps({"selector": args.selector, "clicked": [cx, cy], "rect": r}))
    elif args.cmd == "bfind":
        rect, tab = browser_rect(args.selector, args.tab)
        print(json.dumps({"rect": rect, "tab": tab["id"]}))
    elif args.cmd == "bclick":
        print(json.dumps(browser_click(args.selector, args.tab)))
    elif args.cmd == "btype":
        print(json.dumps(browser_type(args.selector, args.text, args.tab)))
    elif args.cmd == "atree":
        Atspi = atspi_init()
        if not args.app:
            print(json.dumps(sorted({n for n, _ in atspi_apps(Atspi) if n})))
        else:
            print(atspi_tree(Atspi, atspi_app(Atspi, args.app), args.depth))
    elif args.cmd == "afind":
        Atspi = atspi_init()
        print(json.dumps(atspi_find(Atspi, atspi_app(Atspi, args.app), args.query)))
    elif args.cmd == "aclick":
        Atspi = atspi_init()
        print(json.dumps(atspi_click(Atspi, args.app, args.query, force=args.force)))


if __name__ == "__main__":
    main()
