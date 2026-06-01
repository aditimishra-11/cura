"""
AI News Auto-Ingestion Pipeline for Cura.

Fetches from RSS feeds + GitHub trending, filters for AI PM relevance
using GPT-4o-mini, auto-ingests via existing ingest_url(), then sends
a categorised daily digest push notification.

Triggered by: GET /fetch-news  (called by external cron at 7 AM IST daily)
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone, timedelta

import feedparser
import requests

logger = logging.getLogger(__name__)

# ── RSS feed sources ──────────────────────────────────────────────────────────
RSS_FEEDS = [
    {
        "url":      "https://techcrunch.com/category/artificial-intelligence/feed/",
        "source":   "TechCrunch AI",
        "category": "industry",
    },
    {
        "url":      "https://venturebeat.com/category/ai/feed/",
        "source":   "VentureBeat AI",
        "category": "industry",
    },
    {
        "url":      "https://www.deeplearning.ai/the-batch/feed/",
        "source":   "The Batch",
        "category": "research",
    },
    {
        "url":      "https://hnrss.org/newest?q=LLM+AI+GPT&points=50",
        "source":   "Hacker News",
        "category": "community",
    },
    {
        "url":      "https://www.producthunt.com/feed?category=artificial-intelligence",
        "source":   "Product Hunt",
        "category": "launches",
    },
    {
        "url":      "https://www.anthropic.com/news/rss.xml",
        "source":   "Anthropic",
        "category": "models",
    },
    {
        "url":      "https://openai.com/blog/rss.xml",
        "source":   "OpenAI",
        "category": "models",
    },
]

RELEVANCE_PROMPT = """\
You are a filter for an AI Product Manager's personal knowledge feed.

Score each item 1-10 for relevance to an AI PM who tracks:
- New AI model/capability releases (GPT-5, Claude 4, Gemini etc.)
- AI product launches and funding rounds
- AI engineering practices (RAG, agents, fine-tuning, evals)
- AI strategy, policy, and industry trends

Respond with ONLY a JSON array in this exact format, one object per item:
[
  {{"index": 0, "score": 8, "category": "models"}},
  {{"index": 1, "score": 3, "category": "industry"}},
  ...
]

Categories must be one of: models, launches, research, engineering, industry, community

Items to score:
{items}
"""


def _get_supabase():
    from supabase import create_client
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def _get_openai():
    from services.langfuse_compat import OpenAI
    return OpenAI(api_key=os.environ["OPENAI_API_KEY"])


# ── Step 1: Fetch ─────────────────────────────────────────────────────────────

def fetch_rss_items() -> list[dict]:
    """Fetch last 24h items from all RSS feeds."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    items = []

    for feed_cfg in RSS_FEEDS:
        try:
            feed = feedparser.parse(feed_cfg["url"])
            for entry in feed.entries:
                # Parse publish date
                published = None
                if hasattr(entry, "published_parsed") and entry.published_parsed:
                    import time
                    published = datetime.fromtimestamp(
                        time.mktime(entry.published_parsed), tz=timezone.utc
                    )

                # Skip if older than 24h (if date available)
                if published and published < cutoff:
                    continue

                link = getattr(entry, "link", None)
                title = getattr(entry, "title", None)
                if not link or not title:
                    continue

                items.append({
                    "url":      link,
                    "title":    title,
                    "source":   feed_cfg["source"],
                    "category": feed_cfg["category"],
                })
        except Exception as e:
            logger.warning("RSS fetch failed for %s: %s", feed_cfg["source"], e)

    logger.info("Fetched %d raw RSS items", len(items))
    return items


def fetch_github_trending() -> list[dict]:
    """Fetch trending AI repos from GitHub Search API (no auth needed)."""
    items = []
    try:
        since = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
        resp = requests.get(
            "https://api.github.com/search/repositories",
            params={
                "q":    f"topic:llm topic:ai created:>{since}",
                "sort": "stars",
                "order": "desc",
                "per_page": 10,
            },
            headers={"Accept": "application/vnd.github.v3+json"},
            timeout=10,
        )
        if resp.status_code == 200:
            for repo in resp.json().get("items", []):
                items.append({
                    "url":      repo["html_url"],
                    "title":    f"{repo['full_name']} — {repo.get('description', '')}",
                    "source":   "GitHub Trending",
                    "category": "engineering",
                })
    except Exception as e:
        logger.warning("GitHub trending fetch failed: %s", e)

    logger.info("Fetched %d GitHub trending items", len(items))
    return items


# ── Step 2: Deduplicate ───────────────────────────────────────────────────────

def filter_already_saved(items: list[dict]) -> list[dict]:
    """Remove URLs already in the items table."""
    if not items:
        return []

    supabase = _get_supabase()
    urls = [i["url"] for i in items]

    # Supabase 'in' filter
    result = supabase.table("items").select("url").in_("url", urls).execute()
    saved_urls = {r["url"] for r in (result.data or [])}

    fresh = [i for i in items if i["url"] not in saved_urls]
    logger.info("%d items after dedup (%d already saved)", len(fresh), len(saved_urls))
    return fresh


# ── Step 3: Relevance filter ──────────────────────────────────────────────────

def filter_by_relevance(items: list[dict], min_score: int = 7) -> list[dict]:
    """Use GPT-4o-mini to score items, keep those >= min_score."""
    if not items:
        return []

    import json

    # Format items for the prompt
    formatted = "\n".join(
        f"{i}. [{item['source']}] {item['title']}"
        for i, item in enumerate(items)
    )

    try:
        client = _get_openai()
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "user",
                    "content": RELEVANCE_PROMPT.format(items=formatted),
                }
            ],
            temperature=0,
            max_tokens=1000,
        )
        raw = resp.choices[0].message.content.strip()
        scores = json.loads(raw)

        # Attach scores and categories back to items
        for s in scores:
            idx = s["index"]
            if idx < len(items):
                items[idx]["relevance_score"] = s["score"]
                items[idx]["category"]        = s.get("category", items[idx]["category"])

        filtered = [i for i in items if i.get("relevance_score", 0) >= min_score]
        logger.info(
            "%d items passed relevance filter (score >= %d)",
            len(filtered), min_score
        )
        return filtered

    except Exception as e:
        logger.error("Relevance filter failed: %s", e)
        # On failure, return all items so we don't drop everything
        return items


# ── Step 4: Ingest ────────────────────────────────────────────────────────────

def ingest_news_items(items: list[dict]) -> list[dict]:
    """
    Ingest each item via the existing ingest_url() pipeline.
    Then patch the items table with news_category + news_source.
    ingest_url() is NOT modified — we just do a follow-up UPDATE.
    """
    from ingest import ingest_url

    supabase   = _get_supabase()
    ingested   = []

    for item in items:
        try:
            result = ingest_url(item["url"])
            item_id = result.get("stored", {}).get("id")

            # Patch news metadata without touching ingest_url()
            if item_id:
                supabase.table("items").update({
                    "news_source":   item["source"],
                    "news_category": item["category"],
                }).eq("id", item_id).execute()

            ingested.append({
                **item,
                "summary": result.get("summary", ""),
                "intent":  result.get("intent", "reference"),
            })
            logger.info("Ingested: %s", item["title"][:80])

        except Exception as e:
            logger.warning("Ingest failed for %s: %s", item["url"], e)

    logger.info("Successfully ingested %d news items", len(ingested))
    return ingested


# ── Step 5: Send digest push ──────────────────────────────────────────────────

def send_news_digest(items: list[dict]):
    """Send a categorised push notification summarising today's ingested news."""
    if not items:
        logger.info("No news items to digest, skipping push.")
        return

    try:
        from notifications.fcm import send_to_all_devices

        # Group by category
        by_category: dict[str, list] = {}
        for item in items:
            cat = item.get("category", "general")
            by_category.setdefault(cat, []).append(item)

        # Build title + body
        total   = len(items)
        cats    = ", ".join(by_category.keys())
        title   = f"📰 {total} AI updates saved to your library"
        body    = f"Topics: {cats}. Open Cura to explore."

        send_to_all_devices(title=title, body=body, item_id=None)
        logger.info("News digest push sent: %d items across %s", total, cats)

    except Exception as e:
        logger.error("News digest push failed: %s", e)


# ── Main entry point ──────────────────────────────────────────────────────────

def run_news_pipeline() -> dict:
    """
    Full pipeline: fetch → deduplicate → filter → ingest → notify.
    Called by GET /fetch-news (external cron) or APScheduler.
    """
    logger.info("=== AI News Pipeline starting ===")

    # 1. Fetch
    raw = fetch_rss_items() + fetch_github_trending()
    if not raw:
        logger.info("No items fetched, pipeline done.")
        return {"status": "ok", "fetched": 0, "ingested": 0}

    # 2. Deduplicate
    fresh = filter_already_saved(raw)
    if not fresh:
        logger.info("All items already saved, pipeline done.")
        return {"status": "ok", "fetched": len(raw), "ingested": 0}

    # 3. Relevance filter
    relevant = filter_by_relevance(fresh, min_score=7)
    if not relevant:
        logger.info("No items passed relevance filter, pipeline done.")
        return {"status": "ok", "fetched": len(raw), "ingested": 0}

    # 4. Ingest
    ingested = ingest_news_items(relevant)

    # 5. Notify
    send_news_digest(ingested)

    logger.info("=== AI News Pipeline done: %d ingested ===", len(ingested))
    return {
        "status":   "ok",
        "fetched":  len(raw),
        "relevant": len(relevant),
        "ingested": len(ingested),
    }
