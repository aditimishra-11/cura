import re
from datetime import datetime, timedelta, timezone


REMINDER_PATTERNS = [
    # "remind me tomorrow at 9am"
    (r"remind me tomorrow\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", "tomorrow_at"),
    # "remind me tomorrow morning/evening"
    (r"remind me tomorrow\s+(morning|afternoon|evening|night)", "tomorrow_period"),
    # "remind me tomorrow"
    (r"remind me tomorrow", "tomorrow"),
    # "remind me in 2 days/hours"
    (r"remind me in (\d+)\s+(hour|hours|day|days|week|weeks)", "in_duration"),
    # "remind me next week/monday/..."
    (r"remind me next\s+(week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)", "next_period"),
    # "follow up in 3 days"
    (r"follow(?:\s+up)?\s+in\s+(\d+)\s+(day|days|week|weeks)", "followup_in"),
    # "note to self: try this tomorrow"
    (r"(?:note to self|don't let me forget)[^.]*tomorrow", "tomorrow"),
    # bare "tomorrow"
    (r"\btomorrow\b", "tomorrow"),
    # "next week"
    (r"\bnext week\b", "next_week"),
    # "in X days"
    (r"\bin (\d+) (day|days)\b", "in_days"),
]

PERIOD_HOURS = {
    "morning": 9,
    "afternoon": 14,
    "evening": 18,
    "night": 21,
}

WEEKDAY_MAP = {
    "monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3,
    "friday": 4, "saturday": 5, "sunday": 6,
}


def parse_reminder(text: str) -> datetime | None:
    """Return a UTC datetime if the text contains a reminder expression, else None."""
    text_lower = text.lower()
    now = datetime.now(timezone.utc)

    for pattern, kind in REMINDER_PATTERNS:
        m = re.search(pattern, text_lower)
        if not m:
            continue

        if kind == "tomorrow":
            return (now + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)

        if kind == "tomorrow_period":
            period = m.group(1)
            hour = PERIOD_HOURS.get(period, 9)
            return (now + timedelta(days=1)).replace(hour=hour, minute=0, second=0, microsecond=0)

        if kind == "tomorrow_at":
            hour = int(m.group(1))
            minute = int(m.group(2)) if m.group(2) else 0
            meridiem = m.group(3)
            if meridiem == "pm" and hour != 12:
                hour += 12
            elif meridiem == "am" and hour == 12:
                hour = 0
            return (now + timedelta(days=1)).replace(hour=hour, minute=minute, second=0, microsecond=0)

        if kind in ("in_duration", "followup_in"):
            amount = int(m.group(1))
            unit = m.group(2).rstrip("s")
            if unit == "hour":
                return now + timedelta(hours=amount)
            elif unit == "day":
                return (now + timedelta(days=amount)).replace(hour=9, minute=0, second=0, microsecond=0)
            elif unit == "week":
                return (now + timedelta(weeks=amount)).replace(hour=9, minute=0, second=0, microsecond=0)

        if kind == "next_period":
            period = m.group(1)
            if period == "week":
                return (now + timedelta(weeks=1)).replace(hour=9, minute=0, second=0, microsecond=0)
            target_day = WEEKDAY_MAP.get(period)
            if target_day is not None:
                days_ahead = (target_day - now.weekday() + 7) % 7 or 7
                return (now + timedelta(days=days_ahead)).replace(hour=9, minute=0, second=0, microsecond=0)

        if kind == "next_week":
            return (now + timedelta(weeks=1)).replace(hour=9, minute=0, second=0, microsecond=0)

        if kind == "in_days":
            amount = int(m.group(1))
            return (now + timedelta(days=amount)).replace(hour=9, minute=0, second=0, microsecond=0)

    return None


def strip_reminder(text: str) -> str:
    """Remove reminder phrases from text, leaving the clean note."""
    patterns_to_strip = [
        r",?\s*remind me[^,\.]*",
        r",?\s*follow(?:\s+up)?[^,\.]*",
        r",?\s*note to self[^,\.]*",
        r",?\s*don't let me forget[^,\.]*",
    ]
    for p in patterns_to_strip:
        text = re.sub(p, "", text, flags=re.IGNORECASE)
    return text.strip(" ,.")
