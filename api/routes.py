from __future__ import annotations

import re
import os
from datetime import timezone, timedelta
from typing import Optional

IST = timezone(timedelta(hours=5, minutes=30))
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
import logging

from ingest import ingest_url
from ingest.reminder_parser import parse_reminder, strip_reminder
from retrieval import query as rag_query

logger = logging.getLogger(__name__)
router = APIRouter()

URL_RE = re.compile(r"https?://\S+")

# Bare domain: skills.sh, getdesign.md, example.io/path etc.
BARE_DOMAIN_RE = re.compile(
    r'(?<![/\w])'
    r'((?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)'
    r'+(?:com|org|net|io|sh|md|ai|co|dev|app|xyz|gov|edu|tv|me|gg|tech|design|tools|so|cc|uk|us|in))'
    r'(?:/\S*)?'
    r'(?!\w)',
    re.IGNORECASE,
)


class IngestRequest(BaseModel):
    url: str


class MessageRequest(BaseModel):
    message: str
    history: list[dict] = []
    user_email: Optional[str] = None   # identifies which user sent this


class IngestResponse(BaseModel):
    summary: str
    intent: str
    tags: list[str]


class QueryResponse(BaseModel):
    response: str
    mode: str


class StatusResponse(BaseModel):
    total: int
    by_intent: dict[str, int]


class UpdateItemRequest(BaseModel):
    user_note: Optional[str] = None
    remind_at: Optional[str] = None


class GoogleAuthRequest(BaseModel):
    server_auth_code: str
    email: str   # required — we need email to key the token row


class DeviceRequest(BaseModel):
    fcm_token: str
    user_email: Optional[str] = None


REMINDER_RE = re.compile(
    r"\b(remind me|reminder|don't let me forget|follow up|note to self)\b", re.IGNORECASE
)


def _note_from_text(text: str) -> str | None:
    text = text.strip()
    if not text or len(text) < 5:
        return None
    if REMINDER_RE.search(text):
        return text
    if len(text.split()) >= 3:
        return text
    return None


def _get_supabase():
    from supabase import create_client
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def _save_text_item(subject: str, original_text: str) -> dict:
    """Store a text-only reminder (no URL) using a Google search URL as the key."""
    from urllib.parse import quote
    supabase = _get_supabase()
    search_url = f"https://www.google.com/search?q={quote(subject or original_text)}"
    row = {
        "url":     search_url,
        "title":   (subject or original_text)[:200],
        "summary": original_text,
        "intent":  "reference",
        "tags":    [],
        "source":  "text",
    }
    result = supabase.table("items").upsert(row, on_conflict="url").execute()
    stored = result.data[0] if result.data else row
    return {"stored": stored, "summary": row["summary"],
            "intent": "reference", "tags": []}


@router.post("/ingest", response_model=IngestResponse)
async def ingest(req: IngestRequest):
    try:
        result = ingest_url(req.url)
        return IngestResponse(
            summary=result["summary"],
            intent=result["intent"],
            tags=result["tags"],
        )
    except Exception as e:
        logger.error(f"Ingestion failed for {req.url}: {e}")
        raise HTTPException(status_code=422, detail=f"Could not extract content from URL: {str(e)}")


@router.post("/message")
async def message(req: MessageRequest):
    """Unified endpoint: handles URL, bare domain, query, or mixed messages."""
    from retrieval.chain import detect_mode
    text = req.message.strip()

    # ── Detect URL: explicit https:// first, then bare domain fallback ─────────
    explicit_urls = URL_RE.findall(text)
    if explicit_urls:
        url             = explicit_urls[0]
        surrounding_text = URL_RE.sub("", text, count=1).strip()
    else:
        bare = BARE_DOMAIN_RE.search(text)
        if bare:
            url              = "https://" + bare.group(0)
            surrounding_text = BARE_DOMAIN_RE.sub("", text, count=1).strip()
        else:
            url              = None
            surrounding_text = None

    if url:
        note = _note_from_text(surrounding_text) if surrounding_text else None

        try:
            result = ingest_url(url)
        except Exception as e:
            logger.error(f"Ingestion failed for {url}: {e}")
            raise HTTPException(status_code=422, detail=f"Could not extract content from URL: {str(e)}")

        response_parts = [
            f"✅ **Saved!**\n\n**Summary:** {result['summary']}\n\n"
            f"**Intent:** {result['intent']}  |  **Tags:** {', '.join(result['tags'])}"
        ]

        if note:
            remind_at = parse_reminder(note)
            clean_note = strip_reminder(note) if remind_at else note

            if remind_at:
                supabase = _get_supabase()
                item_id  = result["stored"].get("id")

                if item_id:
                    # Store reminder in user_reminders table (per-user)
                    reminder_row = {
                        "item_id":      item_id,
                        "user_email":   req.user_email or "unknown",
                        "remind_at":    remind_at.isoformat(),
                        "user_note":    clean_note or None,
                        "reminder_sent": False,
                    }

                    # Create Google Calendar event if user has connected Google
                    if req.user_email:
                        try:
                            from services.google_calendar_service import create_calendar_event
                            item_title = result["stored"].get("title") or url

                            # Rich description with all item details
                            cal_description = (
                                f"🔗 {url}\n\n"
                                f"{result['summary']}\n\n"
                                f"🏷️ Intent: {result['intent'].capitalize()}  |  "
                                f"Tags: {', '.join(result['tags'])}"
                            )
                            if clean_note:
                                cal_description += f"\n\n📝 {clean_note}"

                            cal_event_id = create_calendar_event(
                                req.user_email, remind_at, item_title, cal_description
                            )
                            if cal_event_id:
                                reminder_row["calendar_event_id"] = cal_event_id
                        except Exception as cal_err:
                            logger.warning("Calendar event creation skipped: %s", cal_err)

                    supabase.table("user_reminders").insert(reminder_row).execute()

                ist_time  = remind_at.astimezone(IST)
                local_str = ist_time.strftime("%A, %b %d at %I:%M %p IST")
                response_parts.append(
                    f"\n\n⏰ **Reminder set for {local_str}**\n"
                    f"I'll send a push notification when it's time."
                )
            elif clean_note:
                response_parts.append(f"\n\n📝 **Note:** \"{clean_note}\"")

        return {
            "response": "".join(response_parts),
            "mode":     "ingest",
            "intent":   result["intent"],
            "tags":     result["tags"],
        }

    # ── Text-only reminder (no URL, no domain) ────────────────────────────────
    remind_at = parse_reminder(text)
    if remind_at:
        clean_note = strip_reminder(text)
        subject    = clean_note if clean_note else text

        result   = _save_text_item(subject, text)
        item_id  = result["stored"].get("id")
        supabase = _get_supabase()

        reminder_row = {
            "item_id":       item_id,
            "user_email":    req.user_email or "unknown",
            "remind_at":     remind_at.isoformat(),
            "user_note":     subject or None,
            "reminder_sent": False,
        }

        if req.user_email and item_id:
            try:
                from services.google_calendar_service import create_calendar_event
                cal_event_id = create_calendar_event(
                    req.user_email, remind_at, subject,
                    f"📝 {text}"
                )
                if cal_event_id:
                    reminder_row["calendar_event_id"] = cal_event_id
            except Exception as cal_err:
                logger.warning("Calendar event creation skipped: %s", cal_err)

        supabase.table("user_reminders").insert(reminder_row).execute()

        ist_time  = remind_at.astimezone(IST)
        local_str = ist_time.strftime("%A, %b %d at %I:%M %p IST")
        return {
            "response": (
                f"✅ **Got it!**\n\n📝 **Note:** \"{subject}\"\n\n"
                f"⏰ **Reminder set for {local_str}**\n"
                f"I'll send a push notification when it's time."
            ),
            "mode": "ingest",
        }

    # ── Pure text query ────────────────────────────────────────────────────────
    try:
        mode     = detect_mode(text)
        response = rag_query(text, history=req.history)
        return {"response": response, "mode": mode}
    except Exception as e:
        logger.error(f"Query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/query", response_model=QueryResponse)
async def query(req: MessageRequest):
    from retrieval.chain import detect_mode
    try:
        mode     = detect_mode(req.message)
        response = rag_query(req.message, history=req.history)
        return QueryResponse(response=response, mode=mode)
    except Exception as e:
        logger.error(f"Query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ── Device registration ──────────────────────────────────────────────────────

@router.post("/register-device")
async def register_device(req: DeviceRequest):
    supabase = _get_supabase()
    row = {"fcm_token": req.fcm_token}
    if req.user_email:
        row["user_email"] = req.user_email
    supabase.table("devices").upsert(row, on_conflict="fcm_token").execute()
    return {"status": "registered"}


# ── Digest ───────────────────────────────────────────────────────────────────

@router.get("/digest")
async def digest():
    from scheduler.digest import get_pending_digest, clear_pending_digest
    data = get_pending_digest()
    if not data:
        return {"available": False}
    clear_pending_digest()
    return {"available": True, **data}


# ── Status ───────────────────────────────────────────────────────────────────

@router.get("/status", response_model=StatusResponse)
async def status():
    supabase = _get_supabase()
    result   = supabase.table("items").select("intent").execute()
    items    = result.data or []
    counts: dict[str, int] = {}
    for item in items:
        intent         = item.get("intent", "unknown")
        counts[intent] = counts.get(intent, 0) + 1
    return StatusResponse(total=len(items), by_intent=counts)


# ── Library endpoints ────────────────────────────────────────────────────────

@router.get("/items")
async def list_items(
    limit:  int           = Query(default=20, ge=1, le=100),
    offset: int           = Query(default=0,  ge=0),
    intent: Optional[str] = None,
):
    supabase = _get_supabase()
    q = supabase.table("items").select(
        "id, url, title, summary, intent, tags, source, created_at"
    )
    if intent:
        q = q.eq("intent", intent)
    result = q.order("created_at", desc=True).range(offset, offset + limit - 1).execute()
    items  = result.data or []
    return {"items": items, "offset": offset, "limit": limit, "count": len(items)}


@router.get("/items/{item_id}")
async def get_item(item_id: str):
    supabase = _get_supabase()
    result   = (
        supabase.table("items")
        .select("id, url, title, summary, intent, tags, source, created_at")
        .eq("id", item_id)
        .limit(1)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Item not found")
    return result.data[0]


@router.patch("/items/{item_id}")
async def update_item(item_id: str, req: UpdateItemRequest):
    updates: dict = {}
    if req.user_note is not None:
        updates["user_note"] = req.user_note
    if req.remind_at is not None:
        updates["remind_at"]      = req.remind_at
        updates["reminder_sent"]  = False
    if not updates:
        raise HTTPException(status_code=400, detail="Nothing to update")

    supabase = _get_supabase()
    result   = supabase.table("items").update(updates).eq("id", item_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Item not found")
    return result.data[0]


# ── Reminders endpoint ───────────────────────────────────────────────────────

@router.get("/reminders")
async def reminders(user_email: Optional[str] = Query(default=None)):
    supabase = _get_supabase()

    if not user_email:
        return {"reminders": []}

    # Fetch user_reminders joined with item data
    result = (
        supabase.table("user_reminders")
        .select(
            "id, remind_at, user_note, reminder_sent, calendar_event_id, "
            "items(id, url, title, summary, intent, tags, source, created_at)"
        )
        .eq("user_email", user_email)
        .order("remind_at", desc=False)
        .execute()
    )

    # Flatten to match the SavedItem shape the Flutter app expects
    reminders_list = []
    for r in (result.data or []):
        item = r.get("items") or {}
        reminders_list.append({
            "id":             item.get("id") or r["id"],
            "reminder_id":    r["id"],
            "url":            item.get("url", ""),
            "title":          item.get("title"),
            "summary":        item.get("summary"),
            "intent":         item.get("intent", "reference"),
            "tags":           item.get("tags", []),
            "source":         item.get("source"),
            "created_at":     item.get("created_at", ""),
            "remind_at":      r["remind_at"],
            "user_note":      r["user_note"],
            "reminder_sent":  r["reminder_sent"],
        })

    return {"reminders": reminders_list}


# ── Manual reminder trigger (called by external cron every 2 min) ───────────

@router.get("/check-reminders")
async def trigger_reminder_check():
    """Lightweight endpoint pinged by an external cron service.
    Runs the reminder check immediately so we don't depend on APScheduler
    staying alive on Render's free tier (which spins down between requests)."""
    try:
        from scheduler.digest import check_reminders
        check_reminders()
        return {"status": "ok"}
    except Exception as e:
        logger.error("Manual reminder check failed: %s", e)
        return {"status": "error", "detail": str(e)}


# ── Google Calendar auth endpoints ──────────────────────────────────────────

@router.post("/auth/google")
async def connect_google(req: GoogleAuthRequest):
    from services.google_calendar_service import connect
    try:
        return connect(req.server_auth_code, req.email)
    except Exception as e:
        logger.error("Google auth failed: %s", e)
        raise HTTPException(status_code=400, detail=f"Google auth failed: {str(e)}")


@router.get("/auth/google/status")
async def google_auth_status(user_email: Optional[str] = Query(default=None)):
    from services.google_calendar_service import get_status
    if not user_email:
        return {"connected": False, "email": None}
    return get_status(user_email)


@router.delete("/auth/google")
async def disconnect_google(user_email: Optional[str] = Query(default=None)):
    from services.google_calendar_service import disconnect
    if user_email:
        disconnect(user_email)
    return {"status": "disconnected"}
