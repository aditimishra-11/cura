import logging
import os
from datetime import datetime, timezone, timedelta

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.schedulers.background import BackgroundScheduler
from openai import OpenAI
from supabase import create_client

logger = logging.getLogger(__name__)
openai_client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY", ""))

# Digest items are stored here so the app can poll GET /digest
_pending_digest: list[dict] = []

DIGEST_PROMPT = """You are a helpful knowledge assistant sending a weekly digest.
Here are 3 items the user saved but hasn't read yet:

{items}

Write a short, friendly digest message (max 200 words) that:
1. Surfaces these items with their key insight
2. Reminds the user why each might be worth revisiting
3. Ends with "Tap any item to go deeper."

Be warm and conversational, not robotic."""


def get_digest_items() -> list[dict]:
    supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])
    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
    result = (
        supabase.table("items")
        .select("id, url, title, summary, intent, created_at")
        .is_("last_accessed", "null")
        .lt("created_at", cutoff)
        .order("created_at", desc=False)
        .limit(3)
        .execute()
    )
    return result.data or []


def generate_digest():
    global _pending_digest
    items = get_digest_items()
    if not items:
        logger.info("No unread items for digest, skipping.")
        return

    formatted = "\n\n".join(
        f"{i+1}. {item.get('title') or item['url']}\n   {item.get('summary', '')}"
        for i, item in enumerate(items)
    )
    response = openai_client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": DIGEST_PROMPT.format(items=formatted)}],
        temperature=0.4,
    )
    message = response.choices[0].message.content
    _pending_digest = [{"message": message, "items": items, "created_at": datetime.now(timezone.utc).isoformat()}]
    logger.info(f"Weekly digest generated with {len(items)} items.")


def get_pending_digest() -> dict | None:
    return _pending_digest[0] if _pending_digest else None


def clear_pending_digest():
    global _pending_digest
    _pending_digest = []


def start_background_digest() -> BackgroundScheduler:
    scheduler = BackgroundScheduler()
    scheduler.add_job(generate_digest, "cron", day_of_week="sun", hour=9, minute=0, id="weekly_digest")
    scheduler.start()
    logger.info("Weekly digest scheduler started (Sundays 9am).")
    return scheduler
