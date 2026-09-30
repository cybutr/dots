#!/usr/bin/env python3
import sys
import asyncio
import json
import base64
import urllib.request
from pathlib import Path

try:
    import websockets
except ImportError:
    print("websockets not installed", file=sys.stderr)
    sys.exit(1)

CDP_PORT = 9222


def make_data_url(img_path: str) -> str:
    data = Path(img_path).read_bytes()
    mime = "image/jpeg" if data[:3] == b"\xff\xd8\xff" else "image/png"
    return f"data:{mime};base64,{base64.b64encode(data).decode()}"


async def fetch_targets():
    try:
        with urllib.request.urlopen(f"http://localhost:{CDP_PORT}/json", timeout=2) as r:
            return json.loads(r.read())
    except Exception:
        return None


async def wait_for_startpage(max_seconds: int = 30):
    for _ in range(max_seconds):
        targets = await fetch_targets()
        if targets:
            sp = [t for t in targets
                  if "startpage" in t.get("url", "") and t.get("webSocketDebuggerUrl")]
            if sp:
                return targets, sp
        await asyncio.sleep(1)
    return None, []


async def inject_startpage(ws_url: str, data_url: str):
    css = (
        "html, body {"
        " background-color: transparent !important;"
        f" background-image: url({json.dumps(data_url)}) !important;"
        " background-size: cover !important;"
        " background-position: center !important;"
        "}"
    )
    js = f"""
    (function() {{
        const old = document.getElementById('matugen-sp-bg');
        if (old) old.remove();
        const s = document.createElement('style');
        s.id = 'matugen-sp-bg';
        s.textContent = {json.dumps(css)};
        document.head.appendChild(s);
        return 'ok';
    }})()
    """
    try:
        async with websockets.connect(ws_url, open_timeout=5) as ws:
            await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                                      "params": {"expression": js, "returnByValue": True}}))
            await ws.recv()
            return True
    except Exception as e:
        print(f"startpage inject error: {e}", file=sys.stderr)
        return False


async def update_prefs_bg(ws_url: str, data_url: str):
    js_get = """
    new Promise(resolve => {
        vivaldi.prefs.get('vivaldi.themes.user', r => resolve(JSON.stringify(r.value)));
    })
    """
    try:
        async with websockets.connect(ws_url, open_timeout=5, max_size=32 * 1024 * 1024) as ws:
            await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                                      "params": {"expression": js_get, "returnByValue": True,
                                                 "awaitPromise": True}}))
            r = json.loads(await ws.recv())
            themes_json = r.get("result", {}).get("result", {}).get("value", "[]")
            themes = json.loads(themes_json)
            for t in themes:
                t["backgroundImage"] = data_url
                t.setdefault("backgroundPosition", "stretch")

            js_set = f"""
            (function() {{
                try {{
                    vivaldi.prefs.set({{path: 'vivaldi.themes.user', value: {json.dumps(themes)}}});
                    return 'ok';
                }} catch(e) {{
                    return 'err: ' + e.message;
                }}
            }})()
            """
            await ws.send(json.dumps({"id": 2, "method": "Runtime.evaluate",
                                      "params": {"expression": js_set, "returnByValue": True}}))
            r2 = json.loads(await ws.recv())
            val = r2.get("result", {}).get("result", {}).get("value", "")
            return val == "ok"
    except Exception as e:
        print(f"prefs update error: {e}", file=sys.stderr)
        return False


async def main(img_path: str):
    data_url = make_data_url(img_path)

    targets, sp_targets = await wait_for_startpage()
    if not targets:
        print("CDP not available after waiting", file=sys.stderr)
        sys.exit(1)
    if not sp_targets:
        print("startpage target never appeared", file=sys.stderr)

    win_targets = [t for t in targets
                   if t.get("type") == "app" and "window.html" in t.get("url", "")
                   and t.get("webSocketDebuggerUrl")]

    if win_targets:
        ok = await update_prefs_bg(win_targets[0]["webSocketDebuggerUrl"], data_url)
        print(f"Prefs update: {'ok' if ok else 'failed'}")

    # Re-inject across several passes — the startpage finishes rendering
    # asynchronously after the target appears and a late render wipes the style.
    for attempt in range(6):
        targets = await fetch_targets() or []
        sp_targets = [t for t in targets
                      if "startpage" in t.get("url", "") and t.get("webSocketDebuggerUrl")]
        results = await asyncio.gather(*[inject_startpage(t["webSocketDebuggerUrl"], data_url)
                                         for t in sp_targets])
        print(f"Start page injection pass {attempt + 1}: {sum(results)}/{len(sp_targets)}")
        await asyncio.sleep(1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <image_path>", file=sys.stderr)
        sys.exit(1)
    asyncio.run(main(sys.argv[1]))
