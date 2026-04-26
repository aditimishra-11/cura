import os
from services.langfuse_compat import OpenAI, observe
from supabase import create_client

# Lazy client — created on first use to avoid crashing at import time
# if OPENAI_API_KEY is not yet available in the environment.
_openai_client = None

def _get_openai():
    global _openai_client
    if _openai_client is None:
        _openai_client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    return _openai_client


def get_supabase():
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def detect_mode(query: str) -> str:
    q = query.lower()
    # List-all intent: user wants to see everything
    if any(
        phrase in q
        for phrase in [
            "all my saves", "all saves", "everything i saved", "list all",
            "show all", "give me all", "all items", "everything saved",
            "show everything", "all my items",
        ]
    ):
        return "list_all"
    if any(w in q for w in ["teach me", "explain", "how does", "what is", "learn about"]):
        return "learn"
    if any(w in q for w in ["building", "i'm building", "help me build", "how to build", "creating"]):
        return "build"
    if any(w in q for w in ["haven't read", "unread", "not read yet", "review"]):
        return "review"
    return "browse"


@observe(name="embed_query")
def embed_query(query: str) -> list[float]:
    response = _get_openai().embeddings.create(
        model="text-embedding-3-small",
        input=query,
    )
    return response.data[0].embedding


def search_items(query_embedding: list[float], threshold: float = 0.4, count: int = 8) -> list[dict]:
    supabase = get_supabase()
    result = supabase.rpc("match_items", {
        "query_embedding": query_embedding,
        "match_threshold": threshold,
        "match_count": count,
    }).execute()
    return result.data or []


def get_unread_items(count: int = 5) -> list[dict]:
    supabase = get_supabase()
    result = (
        supabase.table("items")
        .select("id, url, title, summary, intent, tags, created_at")
        .is_("last_accessed", "null")
        .order("created_at", desc=False)
        .limit(count)
        .execute()
    )
    return result.data or []


def get_all_items(limit: int = 50) -> list[dict]:
    supabase = get_supabase()
    result = (
        supabase.table("items")
        .select("id, url, title, summary, intent, tags, created_at")
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


def mark_accessed(item_ids: list[str]):
    from datetime import datetime, timezone
    supabase = get_supabase()
    supabase.table("items").update(
        {"last_accessed": datetime.now(timezone.utc).isoformat()}
    ).in_("id", item_ids).execute()


BROWSE_PROMPT = """You are a helpful knowledge assistant. The user wants to find saved content.
Here are the relevant saved items:

{items}

Respond with a concise list. For each item: title/URL, one-line summary, and intent tag."""

LEARN_PROMPT = """You are a knowledgeable teacher. The user wants to learn about: "{query}"
Here are relevant saved items from their knowledge base:

{items}

Synthesise these into a structured explanation with:
1. Core concept
2. Key insights (from the saved content)
3. What to explore next (based on their saves)

Be concise and practical."""

BUILD_PROMPT = """You are a technical advisor. The user is building: "{query}"
Here are relevant saved items from their knowledge base:

{items}

Map each item to its role in their build:
- Tutorials (step-by-step how-tos)
- References (docs, specs to keep handy)
- Inspiration (examples and case studies)

Be direct and actionable."""

REVIEW_PROMPT = """You are a helpful assistant surfacing unread saved content.
Here are items the user saved but hasn't read yet (oldest first):

{items}

Present each as:
• [Title or URL] — summary [intent: tag]

End with: "Reply with a number to go deeper on any of these." """


def format_items(items: list[dict]) -> str:
    lines = []
    for i, item in enumerate(items, 1):
        title = item.get("title") or item.get("url", "")
        summary = item.get("summary", "")
        intent = item.get("intent", "")
        tags = ", ".join(item.get("tags") or [])
        lines.append(f"{i}. **{title}**\n   {summary}\n   intent: {intent} | tags: {tags}")
    return "\n\n".join(lines)


def format_list_all(items: list[dict]) -> str:
    lines = [f"Here are all **{len(items)}** items you've saved:\n"]
    for i, item in enumerate(items, 1):
        title = item.get("title") or item.get("url", "")
        summary = item.get("summary", "")
        if len(summary) > 90:
            summary = summary[:90] + "…"
        intent = item.get("intent", "")
        lines.append(f"{i}. **{title}**\n   {summary}\n   _{intent}_\n")
    return "\n".join(lines)


@observe(name="message")
def query(user_message: str, history: list[dict] | None = None) -> str:
    mode = detect_mode(user_message)
    # Keep the last 6 turns for context (3 user + 3 assistant)
    history_ctx = (history or [])[-6:]

    if mode == "list_all":
        items = get_all_items(50)
        if not items:
            return "You haven't saved anything yet! Share a URL to get started."
        return format_list_all(items)

    if mode == "review":
        items = get_unread_items(5)
        if not items:
            return "You're all caught up — no unread saves!"
        mark_accessed([item["id"] for item in items])
        formatted = format_items(items)
        messages = (
            [{"role": "system", "content": REVIEW_PROMPT.format(items=formatted)}]
            + history_ctx
            + [{"role": "user", "content": user_message}]
        )
        response = _get_openai().chat.completions.create(
            model="gpt-4o",
            messages=messages,
            temperature=0.3,
        )
        return response.choices[0].message.content

    embedding = embed_query(user_message)
    items = search_items(embedding, threshold=0.4, count=8)

    # Fallback: lower threshold if nothing found at 0.4
    if not items:
        items = search_items(embedding, threshold=0.2, count=5)

    if not items:
        return (
            "I couldn't find anything relevant in your saves. "
            "Try different keywords, or check the Library tab to browse everything."
        )

    mark_accessed([item["id"] for item in items])
    formatted = format_items(items)

    if mode == "learn":
        system = LEARN_PROMPT.format(query=user_message, items=formatted)
    elif mode == "build":
        system = BUILD_PROMPT.format(query=user_message, items=formatted)
    else:
        system = BROWSE_PROMPT.format(items=formatted)

    messages = (
        [{"role": "system", "content": system}]
        + history_ctx
        + [{"role": "user", "content": user_message}]
    )
    response = _get_openai().chat.completions.create(
        model="gpt-4o",
        messages=messages,
        temperature=0.3,
    )
    return response.choices[0].message.content
