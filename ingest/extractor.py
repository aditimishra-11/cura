import re
import trafilatura
from trafilatura.settings import use_config


def extract_source(url: str) -> str:
    if "instagram.com" in url:
        return "instagram"
    if "linkedin.com" in url:
        return "linkedin"
    if "twitter.com" in url or "x.com" in url:
        return "twitter"
    if "youtube.com" in url or "youtu.be" in url:
        return "youtube"
    return "web"


def extract_content(url: str) -> dict:
    config = use_config()
    config.set("DEFAULT", "EXTRACTION_TIMEOUT", "30")

    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        return {"url": url, "title": None, "text": None, "source": extract_source(url)}

    result = trafilatura.extract(
        downloaded,
        include_comments=False,
        include_tables=True,
        no_fallback=False,
        config=config,
    )

    metadata = trafilatura.extract_metadata(downloaded)
    title = metadata.title if metadata else None

    return {
        "url": url,
        "title": title,
        "text": result,
        "source": extract_source(url),
    }
