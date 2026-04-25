from langfuse.decorators import observe
from .extractor import extract_content
from .enricher import enrich
from .embedder import store_item


@observe(name="ingest")
def ingest_url(url: str) -> dict:
    extracted = extract_content(url)
    enriched = enrich(extracted["url"], extracted["title"], extracted["text"])
    stored = store_item(
        url=extracted["url"],
        title=extracted["title"],
        raw_text=extracted["text"],
        summary=enriched["summary"],
        intent=enriched["intent"],
        tags=enriched["tags"],
        source=extracted["source"],
    )
    return {
        "stored": stored,
        "summary": enriched["summary"],
        "intent": enriched["intent"],
        "tags": enriched["tags"],
    }
