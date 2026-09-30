#!/usr/bin/env python3
import base64
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://gmail.googleapis.com/gmail/v1/users/me"
TOKEN_URL = "https://oauth2.googleapis.com/token"
MIRA_DIR = os.path.expanduser("~/.config/mira")
TOGGLE = os.path.expanduser("~/.config/hypr/scripts/mira_toggle.sh")
THREAD_ID_RE = re.compile(r"^[0-9a-fA-F]{8,32}$")
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+$")

_tokens = {}


class MailError(Exception):
    pass


def _load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def accounts():
    state = _load_json(os.path.join(MIRA_DIR, "state.json"), {})
    return state.get("accounts") or [], state.get("active")


def _refresh_token(email):
    try:
        out = subprocess.run(
            ["secret-tool", "lookup", "service", "mira", "username", email, "target", "default"],
            capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MailError(f"keyring unavailable: {e}")
    token = out.stdout.strip()
    if not token:
        raise MailError(f"no Mira refresh token for {email}; reconnect it in Mira")
    return token


def _access_token(email):
    cached = _tokens.get(email)
    if cached and cached[1] - time.time() > 60:
        return cached[0]
    creds = _load_json(os.path.join(MIRA_DIR, "credentials.json"), None)
    if not creds:
        raise MailError("missing ~/.config/mira/credentials.json")
    body = urllib.parse.urlencode({
        "client_id": creds["client_id"],
        "client_secret": creds["client_secret"],
        "refresh_token": _refresh_token(email),
        "grant_type": "refresh_token",
    }).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=body), timeout=15) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if "invalid_grant" in detail:
            raise MailError(f"{email} needs reauth in Mira (invalid_grant)")
        raise MailError(f"token refresh failed: {e.code} {detail[:200]}")
    except OSError as e:
        raise MailError(f"token refresh failed: {e}")
    _tokens[email] = (data["access_token"], time.time() + int(data.get("expires_in", 3600)))
    return data["access_token"]


def _get(email, path, params=None):
    url = f"{API}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {_access_token(email)}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise MailError(f"gmail api {e.code}: {e.read().decode(errors='replace')[:200]}")
    except OSError as e:
        raise MailError(f"gmail api: {e}")


def _header(headers, name):
    for h in headers or []:
        if h.get("name", "").lower() == name.lower():
            return h.get("value", "")
    return ""


def _pick_accounts(account):
    all_accounts, active = accounts()
    if not all_accounts:
        raise MailError("Mira has no connected accounts")
    if account:
        if account not in all_accounts:
            raise MailError(f"unknown account {account}; Mira has {', '.join(all_accounts)}")
        return [account]
    return all_accounts


def _summary(email, thread_id):
    t = _get(email, f"threads/{thread_id}", {
        "format": "metadata", "metadataHeaders": ["From", "Subject", "Date"]})
    msgs = t.get("messages") or []
    last = msgs[-1] if msgs else {}
    headers = (last.get("payload") or {}).get("headers")
    labels = {l for m in msgs for l in m.get("labelIds") or []}
    return {
        "account": email,
        "thread_id": thread_id,
        "from": _header(headers, "From"),
        "subject": _header(headers, "Subject") or "(no subject)",
        "date": _header(headers, "Date"),
        "snippet": html.unescape(last.get("snippet", "")),
        "unread": "UNREAD" in labels,
        "starred": "STARRED" in labels,
        "messages": len(msgs),
        "gmail_url": f"https://mail.google.com/mail/u/{email}/#all/{thread_id}",
        "open_action": {"fn": "open_mail", "args": {"thread_id": thread_id, "account": email}},
    }


def search(query, account=None, limit=8):
    limit = max(1, min(int(limit or 8), 25))
    results, errors = [], []
    for email in _pick_accounts(account):
        try:
            page = _get(email, "threads", {"q": query, "maxResults": limit})
        except MailError as e:
            errors.append(str(e))
            continue
        ids = [t["id"] for t in page.get("threads") or []]
        with ThreadPoolExecutor(max_workers=8) as pool:
            for item in pool.map(lambda i: _safe_summary(email, i), ids):
                if item:
                    results.append(item)
    out = {"query": query, "count": len(results), "results": results}
    if errors:
        out["errors"] = errors
    return out


def _safe_summary(email, thread_id):
    try:
        return _summary(email, thread_id)
    except MailError:
        return None


def _decode(data, charset):
    raw = base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))
    try:
        return raw.decode(charset or "utf-8", errors="replace")
    except LookupError:
        return raw.decode("utf-8", errors="replace")


def _charset(part):
    m = re.search(r'charset="?([^";\s]+)', _header(part.get("headers"), "Content-Type"), re.I)
    return m.group(1) if m else None


def _find(part, mime):
    if part.get("mimeType") == mime and (part.get("body") or {}).get("data"):
        return _decode(part["body"]["data"], _charset(part))
    for sub in part.get("parts") or []:
        found = _find(sub, mime)
        if found:
            return found
    return None


def _html_to_text(markup):
    markup = re.sub(r"(?is)<(script|style|head|title)[^>]*>.*?</\1>", "", markup)
    markup = re.sub(r"(?i)<br\s*/?>|</(p|div|tr|li|h[1-6])>", "\n", markup)
    text = html.unescape(re.sub(r"<[^>]+>", "", markup))
    text = re.sub(r"[ \t ‌​]+", " ", text)
    return re.sub(r"\n\s*\n+", "\n\n", text).strip()


def read(thread_id, account=None, max_chars=6000):
    if not THREAD_ID_RE.match(thread_id or ""):
        raise MailError("thread_id must be a Gmail thread id")
    email = _pick_accounts(account)[0]
    t = _get(email, f"threads/{thread_id}", {"format": "full"})
    messages = []
    budget = max_chars
    for m in reversed(t.get("messages") or []):
        payload = m.get("payload") or {}
        body = _find(payload, "text/plain")
        if not body:
            markup = _find(payload, "text/html")
            body = _html_to_text(markup) if markup else html.unescape(m.get("snippet", ""))
        body = body.strip()[:max(budget, 400)]
        budget -= len(body)
        messages.append({
            "from": _header(payload.get("headers"), "From"),
            "to": _header(payload.get("headers"), "To"),
            "date": _header(payload.get("headers"), "Date"),
            "body": body,
        })
        if budget <= 0:
            break
    messages.reverse()
    headers = ((t.get("messages") or [{}])[0].get("payload") or {}).get("headers")
    return {
        "account": email,
        "thread_id": thread_id,
        "subject": _header(headers, "Subject") or "(no subject)",
        "messages": messages,
        "truncated": budget <= 0,
        "open_action": {"fn": "open_mail", "args": {"thread_id": thread_id, "account": email}},
    }


def open_in_mira(thread_id=None, account=None, query=None):
    if thread_id:
        if not THREAD_ID_RE.match(thread_id):
            raise MailError("thread_id must be a Gmail thread id")
        if account and not EMAIL_RE.match(account):
            raise MailError("bad account")
        args = ["open", thread_id] + ([account] if account else [])
    elif query:
        args = ["search", query]
    else:
        raise MailError("need thread_id or query")
    subprocess.Popen(["bash", TOGGLE] + args, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True, "opened": thread_id or query}


def main(argv):
    if len(argv) < 2 or argv[1] not in ("search", "read", "open"):
        print("usage: mira_mail.py search <query> [--account A] [--limit N] | read <thread_id> [--account A] | open <thread_id> [--account A]")
        return 2
    cmd, rest = argv[1], argv[2:]
    opts, pos = {}, []
    it = iter(rest)
    for a in it:
        if a in ("--account", "--limit"):
            opts[a[2:]] = next(it, None)
        else:
            pos.append(a)
    try:
        if cmd == "search":
            out = search(" ".join(pos), opts.get("account"), opts.get("limit") or 8)
        elif cmd == "read":
            out = read(pos[0] if pos else "", opts.get("account"))
        else:
            out = open_in_mira(pos[0] if pos else None, opts.get("account"))
    except MailError as e:
        print(json.dumps({"error": str(e)}))
        return 1
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
