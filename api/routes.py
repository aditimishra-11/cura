from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, HttpUrl
import logging

from ingest import ingest_url
from retrieval import query as rag_query

logger = logging.getLogger(__name__)
router = APIRouter()


class IngestRequest(BaseModel):
    url: str


class QueryRequest(BaseModel):
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


@router.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest):
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
