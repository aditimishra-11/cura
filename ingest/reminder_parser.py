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
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

_SYSTEM = """\
You are a reminder-time extractor. The user will give you a short piece of text \
that may contain a reminder request (e.g. "remind me in 2 mins", "ping me tomorrow \
at 9am", "follow up next Monday", "don't let me forget this on Friday").

Current UTC time: {now}

Rules:
- If the text contains a reminder/follow-up request, output ONLY the target \
datetime in ISO 8601 format with UTC offset, e.g. 2025-06-01T09:00:00+00:00
- If there is NO reminder intent, output ONLY the word: none
- Do not output anything else — no explanation, no punctuation, just the datetime \
or the word none.
"""


def parse_reminder(text: str) -> datetime | None:
    """Return a UTC datetime if the text contains a reminder expression, else None."""
    from services.langfuse_compat import OpenAI

    now = datetime.now(timezone.utc)
    client = OpenAI()

    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": _SYSTEM.format(now=now.strftime("%Y-%m-%dT%H:%M:%SZ")),
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

        # Parse the ISO datetime returned by the LLM
        dt = datetime.fromisoformat(raw)
        # Ensure UTC
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
