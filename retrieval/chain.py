import os
import re
from openai import OpenAI
from supabase import create_client

openai_client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY", ""))


def get_supabase():
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def detect_mode(query: str) -> str:
    q = query.lower()
    if any(w in q for w in ["teach me", "explain", "how does", "what is", "learn about"]):
        return "learn"
    if any(w in q for w in ["building", "i'm building", "help me build", "how to build", "creating"]):
        return "build"
    if any(w in q for w in ["haven't read", "unread", "not read yet", "review"]):
        return "review"
    return "browse"


def embed_query(query: str) -> list[float]:
    response = openai_client.embeddings.create(
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


def mark_accessed(item_ids: list[str]):
    from datetime import datetime, timezone
    supabase = get_supabase()
    supabase.table("items").update({"last_accessed": datetime.now(timezone.utc).isoformat()}).in_("id", item_ids).execute()


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
• [Title or URL] — {summary} [intent: {intent}]

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


def query(user_message: str) -> str:
    mode = detect_mode(user_message)

    if mode == "review":
        items = get_unread_items(5)
        if not items:
            return "You're all caught up — no unread saves!"
        mark_accessed([item["id"] for item in items])
        formatted = format_items(items)
        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": REVIEW_PROMPT.format(items=formatted)}],
            temperature=0.3,
        )
        return response.choices[0].message.content

    embedding = embed_query(user_message)
    items = search_items(embedding)

    if not items:
        return "I couldn't find anything relevant in your saves. Try different keywords, or I may not have anything on this yet."

    mark_accessed([item["id"] for item in items])
    formatted = format_items(items)

    if mode == "learn":
        prompt = LEARN_PROMPT.format(query=user_message, items=formatted)
    elif mode == "build":
        prompt = BUILD_PROMPT.format(query=user_message, items=formatted)
    else:
        prompt = BROWSE_PROMPT.format(items=formatted)

    response = openai_client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3,
    )
    return response.choices[0].message.content
