#!/usr/bin/env python3
"""
Set Vivaldi speed dial background via Chrome DevTools Protocol.
Usage: vivaldi_set_bg.py <image_path>
"""

import sys
import asyncio
import base64
import json
import urllib.request
import urllib.error

try:
    import websockets
except ImportError:
    print("Error: websockets package required (pip install websockets)", file=sys.stderr)
    sys.exit(1)

CDP_PORT = 9222

async def set_background(image_path: str):
    # Read and encode the image
    with open(image_path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    # Detect mime type
    ext = image_path.lower().rsplit(".", 1)[-1]
    mime = "image/jpeg" if ext in ("jpg", "jpeg") else "image/png"
    data_url = f"data:{mime};base64,{data}"

    # Get CDP targets
    try:
        with urllib.request.urlopen(f"http://localhost:{CDP_PORT}/json", timeout=3) as r:
            targets = json.loads(r.read())
    except Exception as e:
        print(f"Error: could not reach Vivaldi on port {CDP_PORT}: {e}", file=sys.stderr)
        sys.exit(1)

    if not targets:
        print("Error: no CDP targets found", file=sys.stderr)
        sys.exit(1)

    # Prefer the background_page target; fall back to first available
    ws_url = None
    for t in targets:
        if t.get("type") == "background_page":
            ws_url = t.get("webSocketDebuggerUrl")
            break
    if not ws_url:
        ws_url = targets[0].get("webSocketDebuggerUrl")

    if not ws_url:
        print("Error: no WebSocket debugger URL found", file=sys.stderr)
        sys.exit(1)

    async with websockets.connect(ws_url) as ws:
        # Try vivaldi.prefs API (available in background page context)
        js = f"""
        (function() {{
            if (typeof vivaldi === 'undefined' || !vivaldi.prefs) {{
                return 'no_vivaldi_api';
            }}
            // Common pref paths for speed dial background
            const paths = [
                'vivaldi.homepage.background.data',
                'vivaldi.startpage.background',
                'vivaldi.startpage.backgroundData',
            ];
            // List all pref paths that contain 'background'
            return 'api_available';
        }})()
        """
        msg = {"id": 1, "method": "Runtime.evaluate", "params": {"expression": js, "returnByValue": True}}
        await ws.send(json.dumps(msg))
        resp = json.loads(await ws.recv())
        result = resp.get("result", {}).get("result", {}).get("value", "")

        if result == "no_vivaldi_api":
            # Fall back: inject into all pages by broadcasting to each target
            print("Vivaldi prefs API not available in this context, trying DOM approach...")
            await set_via_dom(targets, data_url)
            return

        # Try setting the background via vivaldi.prefs
        js_set = f"""
        (function() {{
            const url = {json.dumps(data_url)};
            // Try known pref paths
            const attempts = [];
            if (typeof vivaldi !== 'undefined' && vivaldi.prefs) {{
                vivaldi.prefs.set({{path: 'vivaldi.homepage.background.data', value: url}});
                vivaldi.prefs.set({{path: 'vivaldi.startpage.background', value: url}});
                attempts.push('prefs_set_attempted');
            }}
            return attempts.join(',') || 'no_action';
        }})()
        """
        msg2 = {"id": 2, "method": "Runtime.evaluate", "params": {"expression": js_set, "returnByValue": True}}
        await ws.send(json.dumps(msg2))
        resp2 = json.loads(await ws.recv())
        print(f"Result: {resp2.get('result', {}).get('result', {}).get('value', '')}")


async def set_via_dom(targets, data_url):
    """Inject background into DOM of all pages as fallback."""
    css = f"""
    #speed-dial-bg,
    .speed-dial-background,
    .startpage-background,
    .sd-background {{
        background-image: url('{data_url}') !important;
        background-size: cover !important;
        background-position: center !important;
    }}
    """
    for t in targets:
        ws_url = t.get("webSocketDebuggerUrl")
        if not ws_url:
            continue
        try:
            async with websockets.connect(ws_url) as ws:
                msg = {
                    "id": 1,
                    "method": "Runtime.evaluate",
                    "params": {
                        "expression": f"""
                        (function() {{
                            const style = document.createElement('style');
                            style.id = 'matugen-wallpaper';
                            const old = document.getElementById('matugen-wallpaper');
                            if (old) old.remove();
                            style.textContent = {json.dumps(css)};
                            document.head.appendChild(style);
                            return document.title;
                        }})()
                        """,
                        "returnByValue": True
                    }
                }
                await ws.send(json.dumps(msg))
                resp = json.loads(await ws.recv())
                title = resp.get("result", {}).get("result", {}).get("value", "?")
                print(f"  Injected into: {title}")
        except Exception:
            pass


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <image_path>", file=sys.stderr)
        sys.exit(1)
    asyncio.run(set_background(sys.argv[1]))
