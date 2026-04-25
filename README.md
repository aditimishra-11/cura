# Cura

A personal knowledge assistant for Android. Save URLs from anywhere, enrich them with AI, retrieve them by intent — and never lose a link again.

## What's new in v2

- **Three-tab app** — Chat · Library · Reminders
- **Library tab** — browse all your saves, filter by intent, tap for full detail
- **Reminders tab** — grouped by Overdue / Today / Upcoming, with relative time display
- **Conversation memory** — the last 6 turns are sent with every message, so "remind me about that" and pronouns actually work
- **Langfuse tracing** — every LLM call (enrich, embed, answer, digest) is traced end-to-end with latency and token cost
- **Bug fixes** — Enter key now inserts a newline instead of sending; foreground push notifications now show a heads-up banner
- **Smarter retrieval** — list-all intent detected ("show all my saves"), lower-threshold semantic fallback so queries no longer return empty

## Architecture

```
Android App (Flutter 3.22)
    │  share intent / chat
    ▼
FastAPI Backend  (Python 3.11 · Render)
    ├─ trafilatura     → extract page content
    ├─ GPT-4o          → summarise + classify intent + tag
    ├─ text-embedding-3-small  → 1536-dim vector
    ├─ APScheduler     → reminder checks (15 min) + weekly digest (Sun 9am)
    ├─ firebase-admin  → FCM push notifications
    └─ Langfuse        → LLM observability & tracing
    │
    ▼
Supabase (Postgres + pgvector)
    items table  ·  devices table
```

## How it works

1. **Save** — share any URL from Chrome, Instagram, LinkedIn → Cura extracts, summarises, tags intent, stores with a vector embedding
2. **Chat** — ask naturally: *"teach me about RAG"*, *"I'm building a dashboard, what's useful?"*, *"show all my saves"*
3. **Library** — swipe to the Library tab; filter by intent chip (learn / build / inspire / share / reference); tap any card for full detail, tags, notes, and reminder status
4. **Reminders** — add "remind me tomorrow" when saving a URL; the Reminders tab groups them by urgency and fires a push when due
5. **Weekly digest** — every Sunday at 9am the backend picks 3 unread saves and surfaces them in Chat on next open

## Backend setup

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

### 2. Supabase

1. Create a project at [supabase.com](https://supabase.com)
2. SQL Editor → run `db/schema.sql`, then `db/reminders_migration.sql`
3. Copy your project URL and anon key from Settings → API

### 3. Environment variables

```bash
cp .env.example .env
```

| Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | ✅ | GPT-4o + embeddings |
| `SUPABASE_URL` | ✅ | Supabase project URL |
| `SUPABASE_KEY` | ✅ | Supabase anon/service key |
| `FIREBASE_CREDENTIALS_JSON` | ✅ | Firebase service account JSON (for FCM) |
| `LANGFUSE_PUBLIC_KEY` | ✅ | Langfuse project public key |
| `LANGFUSE_SECRET_KEY` | ✅ | Langfuse project secret key |
| `LANGFUSE_HOST` | optional | Default: `https://cloud.langfuse.com` |

### 4. Run locally

```bash
python main.py
# API at http://localhost:8000
# Docs at http://localhost:8000/docs
```

### 5. Deploy to Render

1. Push to GitHub → connect Render to this repo
2. Set all env vars in the Render dashboard
3. Copy your Render URL and put it in the Android app settings

## Android app setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.22
- Android Studio / VS Code with Flutter extension
- JDK 17

### Run

```bash
cd flutter_app
flutter pub get
flutter run
```

### Configure API URL

On first launch → Settings (top-right) → enter your backend URL:
- Local emulator: `http://10.0.2.2:8000`
- Render: `https://your-service.onrender.com`

### Build APK

```bash
flutter build apk --release
# → flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

## API reference

| Method | Path | Description |
|---|---|---|
| `POST` | `/message` | Chat — handles URLs, queries, mixed. Accepts `history[]` |
| `POST` | `/ingest` | Ingest a URL directly |
| `GET` | `/items` | Paginated library (`limit`, `offset`, `intent` filter) |
| `GET` | `/items/{id}` | Single item detail |
| `PATCH` | `/items/{id}` | Update `user_note` or `remind_at` |
| `GET` | `/reminders` | All items with `remind_at` set, sorted by time |
| `GET` | `/digest` | Poll for pending weekly digest |
| `GET` | `/status` | Item counts by intent |
| `POST` | `/register-device` | Register FCM token |

## Query modes

| You say | Mode | What happens |
|---|---|---|
| (any URL) | ingest | Extract → summarise → embed → store |
| `show all my saves` | list_all | Return all items, no LLM call |
| `show me what I saved about X` | browse | Semantic search, list results |
| `teach me about X` | learn | Synthesised explainer from your saves |
| `I'm building Y, what's useful?` | build | Items mapped to tutorial / reference / inspiration |
| `what haven't I read yet?` | review | Oldest unread saves surfaced |

## Project structure

```
├── main.py
├── requirements.txt
├── api/
│   └── routes.py               # All API endpoints
├── db/
│   ├── schema.sql
│   └── reminders_migration.sql
├── ingest/
│   ├── __init__.py             # ingest_url() — @observe traced
│   ├── extractor.py            # URL → raw text (trafilatura + GitHub API)
│   ├── enricher.py             # GPT-4o: summary + intent + tags — @observe traced
│   ├── embedder.py             # text-embedding-3-small + Supabase store — @observe traced
│   └── reminder_parser.py      # NLU date/time extraction from user note
├── retrieval/
│   └── chain.py                # Intent-aware RAG — @observe traced, history-aware
├── scheduler/
│   └── digest.py               # Weekly digest + reminder checker — @observe traced
├── notifications/
│   └── fcm.py                  # FCM push via firebase-admin
└── flutter_app/
    └── lib/
        ├── main.dart            # App entry + share intent + 3-tab shell
        ├── screens/
        │   ├── chat_screen.dart
        │   ├── library_screen.dart
        │   ├── reminders_screen.dart
        │   └── settings_screen.dart
        ├── services/
        │   ├── api_service.dart
        │   └── notification_service.dart
        └── widgets/
            └── chat_bubble.dart
```
