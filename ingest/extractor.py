import re
import urllib.request
import json
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
    if "github.com" in url:
        return "github"
    return "web"


def _extract_github(url: str) -> dict:
    # Convert github.com/owner/repo to GitHub API call for README + repo description
    match = re.match(r"https?://github\.com/([^/]+)/([^/\s?#]+)", url)
    if not match:
        return {}
    owner, repo = match.group(1), match.group(2)
    try:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{owner}/{repo}",
            headers={"Accept": "application/vnd.github+json", "User-Agent": "knowledge-assistant"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
        title = data.get("full_name", f"{owner}/{repo}")
        description = data.get("description") or ""
        topics = ", ".join(data.get("topics") or [])
        stars = data.get("stargazers_count", 0)
        language = data.get("language") or ""
        text = f"{description}\nTopics: {topics}\nLanguage: {language}\nStars: {stars}"
        return {"title": title, "text": text.strip()}
    except Exception:
        return {}


def extract_content(url: str) -> dict:
    source = extract_source(url)

    # Use GitHub API for GitHub repo URLs — trafilatura gets poor results
    if source == "github" and re.match(r"https?://github\.com/[^/]+/[^/\s?#]+/?$", url):
        github_data = _extract_github(url)
        if github_data.get("text"):
            return {"url": url, "title": github_data["title"], "text": github_data["text"], "source": source}

    config = use_config()
    config.set("DEFAULT", "EXTRACTION_TIMEOUT", "30")

    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        return {"url": url, "title": None, "text": None, "source": source}

    result = trafilatura.extract(
        downloaded,
        include_comments=False,
        include_tables=True,
        no_fallback=False,
        config=config,
    )

    metadata = trafilatura.extract_metadata(downloaded)
    title = metadata.title if metadata else None

    return {"url": url, "title": title, "text": result, "source": source}
