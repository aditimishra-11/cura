# Personal Knowledge Assistant

An Android app + Python backend that saves URLs you find online, enriches them with AI, and lets you retrieve them by intent — browse, learn, build, or review.

## Architecture

```
Android App (Flutter)
    ↓ POST /ingest  (share from any app)
    ↓ POST /query   (chat interface)
FastAPI Backend (Python)
    ↓ trafilatura   (extract content)
    ↓ GPT-4o        (summarise + tag intent)
    ↓ pgvector      (semantic search)
Supabase (postgres + pgvector)
```

## How it works

1. **Save:** Share any URL from Chrome/Instagram/LinkedIn → taps "Knowledge" in the share sheet → auto-extracted, summarised, tagged, stored
2. **Chat:** Open the app, ask naturally — *"teach me about RAG"*, *"I'm building a dashboard, what's useful?"*, *"what haven't I read yet?"*
3. **Weekly digest:** Every Sunday at 9am, app surfaces 3 unread saves when you open it

## Backend setup

### 1. Install dependencies

```bash
cd personal-knowledge-assistant
pip install -r requirements.txt
```

### 2. Set up Supabase

1. Create a project at [supabase.com](https://supabase.com)
2. Go to SQL Editor and run `db/schema.sql`
3. Copy your project URL and anon key from Settings → API

### 3. Configure environment

```bash
cp .env.example .env
# Fill in: OPENAI_API_KEY, SUPABASE_URL, SUPABASE_KEY
```

### 4. Run locally

```bash
python main.py
# API available at http://localhost:8000
```

### 5. Deploy to Railway

1. Push to GitHub
2. New Railway project → Deploy from GitHub
3. Add env vars in Railway dashboard
4. Copy your Railway URL for the Android app settings

## Android app setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed
- Android Studio or VS Code with Flutter extension

### Run the app

```bash
cd flutter_app
flutter pub get
flutter run
```

### Configure API URL

On first launch, tap Settings (top-right) and enter your API server URL:
- Local dev (emulator): `http://10.0.2.2:8000`
- Production: `https://your-app.railway.app`

### Build APK

```bash
flutter build apk --release
# Output: flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

## Project structure

```
├── main.py                     # FastAPI server entry point
├── CLAUDE.md                   # Persistent spec for Claude Code sessions
├── requirements.txt
├── .env.example
├── api/
│   └── routes.py               # POST /ingest, POST /query, GET /status, GET /digest
├── db/
│   └── schema.sql              # Supabase schema with pgvector
├── ingest/
│   ├── extractor.py            # URL → raw text (trafilatura)
│   ├── enricher.py             # raw text → summary + intent + tags (GPT-4o)
│   └── embedder.py             # Store to Supabase with vector embedding
├── retrieval/
│   └── chain.py                # Intent-aware RAG query chain
├── scheduler/
│   └── digest.py               # Weekly Sunday digest generator
└── flutter_app/
    ├── lib/
    │   ├── main.dart           # App entry + share intent handling
    │   ├── screens/
    │   │   ├── chat_screen.dart
    │   │   └── settings_screen.dart
    │   ├── services/
    │   │   └── api_service.dart
    │   └── widgets/
    │       └── chat_bubble.dart
    └── android/app/src/main/
        └── AndroidManifest.xml # Share intent filter
```

## Query modes

| You say | Mode | What happens |
|---|---|---|
| (any URL) | Ingest | Extract → enrich → store |
| `show me what I saved about X` | Browse | Semantic search, list results |
| `teach me about X` | Learn | Synthesised explainer from your saves |
| `I'm building Y, what's useful?` | Build | Items mapped to tutorial/reference/inspiration |
| `what haven't I read yet?` | Review | Oldest unread saves surfaced |
