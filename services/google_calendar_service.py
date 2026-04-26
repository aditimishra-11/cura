"""
Google Calendar integration — per-user, keyed by email.

Flow:
  1. Flutter signs in with Google (google_sign_in, Calendar scope) and sends
     the serverAuthCode + email to POST /auth/google.
  2. This module exchanges it for access + refresh tokens and stores them in
     the google_tokens table keyed by email (one row per user).
  3. Whenever a reminder is set, create_calendar_event(email, ...) is called
     to create the event in THAT user's primary Google Calendar.
  4. Tokens are refreshed automatically when they expire.
"""
from __future__ import annotations

import os
import logging
from datetime import datetime, timezone, timedelta

import requests

logger = logging.getLogger(__name__)

_TOKEN_URL     = "https://oauth2.googleapis.com/token"
_CALENDAR_BASE = "https://www.googleapis.com/calendar/v3"


# ── Supabase helper ──────────────────────────────────────────────────────────

def _supabase():
    from supabase import create_client
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


# ── Token management ─────────────────────────────────────────────────────────

def exchange_code(server_auth_code: str) -> dict:
    """Exchange a serverAuthCode (from Flutter) for access + refresh tokens."""
    resp = requests.post(_TOKEN_URL, data={
        "code":          server_auth_code,
        "client_id":     os.environ["GOOGLE_CLIENT_ID"],
        "client_secret": os.environ["GOOGLE_CLIENT_SECRET"],
        "redirect_uri":  "",   # empty for mobile server-auth-code flow
        "grant_type":    "authorization_code",
    }, timeout=15)
    resp.raise_for_status()
    return resp.json()


def _store_tokens(token_data: dict, email: str):
    expiry = None
    if "expires_in" in token_data:
        expiry = (
            datetime.now(timezone.utc) + timedelta(seconds=int(token_data["expires_in"]))
        ).isoformat()

    _supabase().table("google_tokens").upsert({
        "email":         email,
        "access_token":  token_data.get("access_token"),
        "refresh_token": token_data.get("refresh_token"),
        "token_expiry":  expiry,
        "updated_at":    datetime.now(timezone.utc).isoformat(),
    }, on_conflict="email").execute()


def _load_tokens(email: str) -> dict | None:
    result = (
        _supabase().table("google_tokens")
        .select("*")
        .eq("email", email)
        .limit(1)
        .execute()
    )
    return result.data[0] if result.data else None


def _get_valid_access_token(email: str) -> str | None:
    """Return a valid access token for this user, refreshing if necessary."""
    row = _load_tokens(email)
    if not row:
        return None

    expiry  = row.get("token_expiry")
    expired = True
    if expiry:
        try:
            expiry_dt = datetime.fromisoformat(expiry.replace("Z", "+00:00"))
            expired   = datetime.now(timezone.utc) >= expiry_dt - timedelta(minutes=5)
        except ValueError:
            pass

    if expired:
        refresh_token = row.get("refresh_token")
        if not refresh_token:
            return None
        resp = requests.post(_TOKEN_URL, data={
            "refresh_token": refresh_token,
            "client_id":     os.environ["GOOGLE_CLIENT_ID"],
            "client_secret": os.environ["GOOGLE_CLIENT_SECRET"],
            "grant_type":    "refresh_token",
        }, timeout=15)
        if not resp.ok:
            logger.error("Token refresh failed for %s: %s", email, resp.text)
            return None
        new_data = resp.json()
        new_data.setdefault("refresh_token", refresh_token)
        _store_tokens(new_data, email=email)
        return new_data["access_token"]

    return row.get("access_token")


# ── Public API ───────────────────────────────────────────────────────────────

def connect(server_auth_code: str, email: str) -> dict:
    """Exchange auth code and persist tokens for this user."""
    token_data = exchange_code(server_auth_code)
    _store_tokens(token_data, email=email)
    return get_status(email)


def disconnect(email: str):
    _supabase().table("google_tokens").delete().eq("email", email).execute()


def get_status(email: str) -> dict:
    row = _load_tokens(email)
    if row:
        return {"connected": True, "email": email}
    return {"connected": False, "email": email}


def create_calendar_event(
    email: str,
    remind_at: datetime,
    title: str,
    note: str = "",
) -> str | None:
    """Create a Google Calendar event for a reminder. Returns event_id or None."""
    token = _get_valid_access_token(email)
    if not token:
        logger.info("Google Calendar not connected for %s — skipping.", email)
        return None

    end_time = remind_at + timedelta(minutes=30)
    body = {
        "summary":     f"🔔 Cura: {title[:100]}",
        "description": note or title,
        "start": {"dateTime": remind_at.isoformat(), "timeZone": "UTC"},
        "end":   {"dateTime": end_time.isoformat(),  "timeZone": "UTC"},
        "reminders": {
            "useDefault": False,
            "overrides":  [{"method": "popup", "minutes": 10}],
        },
    }
    resp = requests.post(
        f"{_CALENDAR_BASE}/calendars/primary/events",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=body,
        timeout=15,
    )
    if resp.ok:
        event_id = resp.json().get("id")
        logger.info("Calendar event created for %s: %s", email, event_id)
        return event_id
    logger.error("Calendar event creation failed for %s: %s", email, resp.text)
    return None


def update_calendar_event(email: str, event_id: str, remind_at: datetime, title: str, note: str = ""):
    """Update an existing calendar event (e.g. when remind_at changes)."""
    token = _get_valid_access_token(email)
    if not token or not event_id:
        return
    end_time = remind_at + timedelta(minutes=30)
    body = {
        "summary":     f"🔔 Cura: {title[:100]}",
        "description": note or title,
        "start": {"dateTime": remind_at.isoformat(), "timeZone": "UTC"},
        "end":   {"dateTime": end_time.isoformat(),  "timeZone": "UTC"},
    }
    requests.patch(
        f"{_CALENDAR_BASE}/calendars/primary/events/{event_id}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=body,
        timeout=15,
    )


def delete_calendar_event(email: str, event_id: str):
    """Delete a calendar event (e.g. when reminder is dismissed)."""
    token = _get_valid_access_token(email)
    if not token or not event_id:
        return
    requests.delete(
        f"{_CALENDAR_BASE}/calendars/primary/events/{event_id}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=15,
    )
