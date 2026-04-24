import json
import os
from openai import OpenAI

def _client():
    return OpenAI(api_key=os.environ["OPENAI_API_KEY"])

SYSTEM_PROMPT = """You are a knowledge assistant that enriches saved content.
Given a URL, title, and extracted text, return a JSON object with:
- summary: 2-sentence summary of what this content is about
- intent: one label from [learn, build, inspire, share, reference]
  - learn: educational content, tutorials, explanations
  - build: tools, code, frameworks, how-to guides for building things
  - inspire: ideas, case studies, success stories, creative content
  - share: content worth sharing with others (news, insights)
  - reference: documentation, specs, resources to look up later
- tags: array of 5 specific topic tags (lowercase, no spaces)

Examples of intent classification:
- "How LLMs work internally" → learn
- "FastAPI tutorial with auth" → build
- "How Notion grew to 10M users" → inspire
- "OpenAI launches new model" → share
- "Postgres pgvector docs" → reference

Return only valid JSON, no markdown."""

FEW_SHOT = [
    {
        "role": "user",
        "content": "Title: Building a RAG system with LangChain\nText: This tutorial walks through building a retrieval-augmented generation system...",
    },
    {
        "role": "assistant",
        "content": '{"summary": "A hands-on tutorial for building a RAG system using LangChain and vector databases. Covers chunking, embedding, retrieval, and response generation.", "intent": "build", "tags": ["rag", "langchain", "vector-db", "llm", "python"]}',
    },
]


def enrich(url: str, title: str | None, text: str | None) -> dict:
    user_content = f"URL: {url}\nTitle: {title or 'Unknown'}\nText: {(text or '')[:3000]}"

    response = _client().chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            *FEW_SHOT,
            {"role": "user", "content": user_content},
        ],
        temperature=0.2,
        response_format={"type": "json_object"},
    )

    return json.loads(response.choices[0].message.content)
