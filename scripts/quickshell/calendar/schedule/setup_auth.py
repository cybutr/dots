#!/usr/bin/env python3
import pickle, os
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from google.auth.exceptions import RefreshError

SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/gmail.readonly",
]
TOKEN_PATH = os.path.expanduser("~/.local/share/qs_calendar_oauth")
CLIENT_ID     = os.environ.get("CLIENT_ID")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET")

creds = None
if os.path.exists(TOKEN_PATH):
    with open(TOKEN_PATH, "rb") as f:
        creds = pickle.load(f)

def run_flow():
    flow = InstalledAppFlow.from_client_config(
        {
            "installed": {
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "redirect_uris": ["http://localhost"],
            }
        },
        SCOPES,
    )
    return flow.run_local_server(port=0)

missing_scopes = creds is not None and not set(SCOPES).issubset(set(creds.scopes or []))
if missing_scopes:
    # An existing token that lacks a newly-added scope (e.g. gmail.readonly
    # added after the token was first created) won't self-upgrade — Google
    # requires a fresh interactive consent for the new scope, refreshing the
    # old token just re-grants the scopes it already had.
    creds = run_flow()
    with open(TOKEN_PATH, "wb") as f:
        pickle.dump(creds, f)
elif not creds or not creds.valid:
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except RefreshError:
            creds = run_flow()
    else:
        creds = run_flow()
    with open(TOKEN_PATH, "wb") as f:
        pickle.dump(creds, f)

print("Auth saved to", TOKEN_PATH)
print("Scopes:", creds.scopes)
