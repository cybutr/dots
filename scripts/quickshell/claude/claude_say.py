#!/usr/bin/env python3
"""Headless one-shot Claude call (Haiku by default) for ambient/background use.
Calls the Messages API directly over HTTPS — NOT the claude CLI. The CLI route
was found to leak prior-session facts (battery%, calendar) into supposedly
stateless rephrase calls, traced to ~/.claude/settings.json hooks (cavemem)
that run regardless of --settings/--mcp-config/--no-session-persistence
overrides (those overrides merge rather than replace). A raw API call has no
hooks, no plugins, no session state — just this prompt in, text out.
Usage: claude_say.py "<prompt>" [--model M] [--system S] [--max N]
"""
import os, json, argparse, urllib.request

ACC_DIR = os.path.expanduser("~/.config/anthropic/accounts")
DEFAULT_MODEL = "claude-haiku-4-5-20251001"

# (key file, base url) — tried in order; falls through on any failure.
# cc.freemodel.dev (third-party relay, not Anthropic) removed — it's what
# triggered an "Access Denied: unauthorized client" response from Anthropic's
# backend, which then got displayed verbatim as if it were a real Claude reply.
_PROVIDERS = [
    ("backup.key", "https://api.anthropic.com/v1/messages"),
]


def _read_key(name):
    try:
        with open(os.path.join(ACC_DIR, name)) as f:
            return f.read().strip()
    except OSError:
        return ""


def _call(base_url, key, prompt, model, system, max_tokens, timeout):
    body = {"model": model, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}]}
    if system:
        body["system"] = system
    req = urllib.request.Request(
        base_url, data=json.dumps(body).encode(),
        headers={"content-type": "application/json", "x-api-key": key,
                 "anthropic-version": "2023-06-01"},
        method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read())
    return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text").strip()


def say(prompt, model=DEFAULT_MODEL, system="", timeout=25, max_tokens=150):
    for keyfile, base_url in _PROVIDERS:
        key = _read_key(keyfile)
        if not key:
            continue
        try:
            out = _call(base_url, key, prompt, model, system, max_tokens, timeout)
            if out:
                return out
        except Exception:
            continue
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--system", default="")
    ap.add_argument("--max", type=int, default=150)
    a = ap.parse_args()
    print(say(a.prompt, a.model, a.system, max_tokens=a.max))


if __name__ == "__main__":
    main()
