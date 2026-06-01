"""
Reminder parsing via LLM.

parse_reminder(text) — returns a UTC datetime if the text expresses a reminder,
                        or None if no reminder intent is found.
strip_reminder(text) — removes the reminder phrase, returning a clean note.

The LLM is given the current UTC time and asked to return an ISO 8601 datetime
(or the string "none") so it handles any natural-language phrasing.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone, timedelta

logger = logging.getLogger(__name__)

IST = timezone(timedelta(hours=5, minutes=30))

_SYSTEM = """\
You are a reminder-time extractor. The user will give you a short piece of text \
that may contain a reminder request (e.g. "remind me in 2 mins", "ping me tomorrow \
at 9am", "follow up next Monday", "don't let me forget this on Friday").

Current IST date and time: {now_ist}
(IST = India Standard Time = UTC+5:30)

All times the user mentions are in IST unless explicitly stated otherwise.
Output the reminder datetime in UTC (ISO 8601 with +00:00 offset).
To convert IST to UTC: subtract 5 hours 30 minutes.

Datetime pattern guide (all times are IST, resolve relative to current IST time above):
- "tomorrow at 9am"               → next calendar day 09:00 IST
- "tomorrow morning"              → next calendar day 09:00 IST
- "tomorrow afternoon"            → next calendar day 14:00 IST
- "tomorrow evening"              → next calendar day 18:00 IST
- "tonight"                       → today 21:00 IST
- "this friday / saturday / ..."  → the coming occurrence of that weekday 09:00 IST \
(if today is that day, use next week)
- "next friday / monday / ..."    → the occurrence in the NEXT calendar week 09:00 IST
- "next week"                     → Monday of next calendar week 09:00 IST
- "next week wednesday"           → Wednesday of next calendar week 09:00 IST
- "this weekend"                  → coming Saturday 10:00 IST
- "end of day" / "EOD"            → today 18:00 IST
- "morning" (no day given)        → next upcoming 09:00 IST
- "afternoon" (no day given)      → next upcoming 14:00 IST
- "evening" (no day given)        → next upcoming 18:00 IST
- "night" (no day given)          → next upcoming 21:00 IST
- explicit time like "5:30 AM"    → treat as IST, convert to UTC

Rules:
- If the text contains a reminder/follow-up request, output ONLY the target \
datetime in ISO 8601 format with UTC offset (always UTC), \
e.g. 2025-06-01T03:30:00+00:00
- If there is NO reminder intent, output ONLY the word: none
- Do not output anything else — no explanation, no punctuation, just the datetime \
or the word none.
"""


import re

# Patterns handled directly in Python — no LLM arithmetic needed
_RELATIVE_RE = re.compile(
    r'\bin\s+(\d+)\s*(min(?:ute)?s?|hr?s?|hours?|days?)\b',
    re.IGNORECASE,
)
_NO_REMINDER_RE = re.compile(
    r'\b(remind|reminder|ping|follow.?up|don.?t let me forget|note to self|revisit|check|read this)\b',
    re.IGNORECASE,
)


def _parse_relative(text: str, now: datetime) -> datetime | None:
    """
    Handle "in X mins/hours/days" purely in Python.
    Returns UTC datetime or None if pattern not found.
    """
    m = _RELATIVE_RE.search(text)
    if not m:
        return None
    n    = int(m.group(1))
    unit = m.group(2).lower()
    if unit.startswith('m'):
        return now + timedelta(minutes=n)
    if unit.startswith('h'):
        return now + timedelta(hours=n)
    if unit.startswith('d'):
        return now + timedelta(days=n)
    return None


def parse_reminder(text: str) -> datetime | None:
    """Return a UTC datetime if the text contains a reminder expression, else None."""
    from services.langfuse_compat import OpenAI

    now_utc = datetime.now(timezone.utc)

    # ── Fast path: relative durations handled in Python (no LLM) ─────────────
    relative = _parse_relative(text, now_utc)
    if relative is not None:
        logger.debug("Relative reminder parsed in Python: %s", relative)
        return relative

    # ── If no reminder intent at all, skip LLM call entirely ─────────────────
    if not _NO_REMINDER_RE.search(text):
        return None

    # ── LLM path: complex expressions (tomorrow, next friday, tonight…) ───────
    now_ist = now_utc.astimezone(IST)
    client  = OpenAI()

    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": _SYSTEM.format(
                        now_ist=now_ist.strftime("%Y-%m-%dT%H:%M:%S IST (%A, %B %d %Y)"),
                    ),
                },
                {"role": "user", "content": text},
            ],
            temperature=0,
            max_tokens=30,
        )
        raw = resp.choices[0].message.content.strip()
        logger.debug("Reminder LLM raw response: %r", raw)

        if raw.lower() == "none" or not raw:
            return None

        dt = datetime.fromisoformat(raw)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt

    except Exception as e:
        logger.error("Reminder LLM parse failed: %s", e)
        return None


def strip_reminder(text: str) -> str:
    """
    Remove the reminder/follow-up phrase from text, returning just the clean note.

    Uses the LLM so it can handle any phrasing, falling back to returning the
    original text unchanged if the call fails.
    """
    from services.langfuse_compat import OpenAI

    client = OpenAI()
    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Remove any reminder/follow-up/scheduling phrases from the "
                        "following text and return only the clean remaining note. "
                        "If the entire text is just a reminder phrase with no other "
                        "content, return an empty string. "
                        "Output ONLY the cleaned text, nothing else."
                    ),
                },
                {"role": "user", "content": text},
            ],
            temperature=0,
            max_tokens=200,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        logger.error("strip_reminder LLM call failed: %s", e)
        # Fallback: return original text
        return text
