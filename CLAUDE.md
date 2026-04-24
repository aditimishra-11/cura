# Personal Knowledge Assistant

## Problem
User saves interesting URLs to personal WhatsApp chat but never revisits them. This bot solves that by making saved content retrievable and useful.

## Stack
- Python backend (FastAPI) — REST API
- Supabase (postgres + pgvector for embeddings)
- OpenAI (gpt-4o for enrichment, text-embedding-3-small for vectors)
- Flutter Android app — chat UI + share intent
- trafilatura for URL content extraction
- APScheduler for the weekly resurface cron job

## Project structure
- /api — FastAPI routes (POST /ingest, POST /query, GET /status, GET /digest)
- /ingest — URL extraction + LLM enrichment + Supabase storage
- /retrieval — RAG chain with intent-aware routing
- /scheduler — Weekly digest cron job
- /db — Supabase schema + migrations
- /flutter_app — Android app (Flutter)

## Key behaviours
- On any shared URL: extract → summarise → tag intent → embed → store
- On query "show me X": semantic search, return list with summaries
- On query "teach me X": retrieve + synthesise into structured explainer
- On query "building Y": retrieve + map each item to a build role
- On query "what haven't I read yet?": filter unread items, surface oldest
- Weekly cron: pick 3 unread items, send digest message

## Intent labels
learn, build, inspire, share, reference

## Query modes
- browse: semantic search, return list with summaries
- learn: retrieve + synthesise into structured explainer
- build: retrieve + map each item to a role (tutorial / reference / inspiration)
- review: filter by last_accessed IS NULL, surface oldest unread

## Environment variables (see .env.example)
- TELEGRAM_BOT_TOKEN
- OPENAI_API_KEY
- SUPABASE_URL
- SUPABASE_KEY

## Deploy target
Railway — picks up requirements.txt automatically, set env vars in dashboard.
