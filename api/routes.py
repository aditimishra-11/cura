import re
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import logging

from ingest import ingest_url
from retrieval import query as rag_query

logger = logging.getLogger(__name__)
router = APIRouter()

URL_RE = re.compile(r"https?://\S+")


class IngestRequest(BaseModel):
    url: str


class MessageRequest(BaseModel):
    message: str


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


REMINDER_RE = re.compile(
    r"\b(remind me|reminder|don't let me forget|follow up|note to self)\b", re.IGNORECASE
)


def _note_from_text(text: str, summary: str) -> str | None:
    """Extract a user note from message text alongside a URL."""
    text = text.strip()
    if not text or len(text) < 5:
        return None
    if REMINDER_RE.search(text):
        return text
    # Any meaningful text alongside a URL is a note
    if len(text.split()) >= 3:
        return text
    return None


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
    """Unified endpoint: handles URL, query, or mixed URL+text messages."""
    from retrieval.chain import detect_mode
    text = req.message.strip()
    urls = URL_RE.findall(text)

    if urls:
        url = urls[0]
        surrounding_text = URL_RE.sub("", text).strip()
        note = _note_from_text(surrounding_text, "")

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
            if REMINDER_RE.search(note):
                response_parts.append(
                    f"\n\n📝 **Note saved:** \"{note}\"\n"
                    "*(Reminder feature coming soon — for now I've tagged this so you can find it with \"what have I noted to try?\")*"
                )
            else:
                response_parts.append(f"\n\n📝 **Your note:** \"{note}\"")

        return {"response": "".join(response_parts), "mode": "ingest", "intent": result["intent"], "tags": result["tags"]}

    # Pure text query
    try:
        mode = detect_mode(text)
        response = rag_query(text)
        return {"response": response, "mode": mode}
    except Exception as e:
        logger.error(f"Query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/query", response_model=QueryResponse)
async def query(req: MessageRequest):
    from retrieval.chain import detect_mode
    try:
        mode = detect_mode(req.message)
        response = rag_query(req.message)
        return QueryResponse(response=response, mode=mode)
    except Exception as e:
        logger.error(f"Query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/digest")
async def digest():
    from scheduler.digest import get_pending_digest, clear_pending_digest
    data = get_pending_digest()
    if not data:
        return {"available": False}
    clear_pending_digest()
    return {"available": True, **data}


@router.get("/status", response_model=StatusResponse)
async def status():
    import os
    from supabase import create_client
    supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])
    result = supabase.table("items").select("intent").execute()
    items = result.data or []
    counts: dict[str, int] = {}
    for item in items:
        intent = item.get("intent", "unknown")
        counts[intent] = counts.get(intent, 0) + 1
    return StatusResponse(total=len(items), by_intent=counts)
