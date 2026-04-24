-- Enable pgvector extension
create extension if not exists vector;

-- Main table for saved knowledge items
create table if not exists items (
    id uuid primary key default gen_random_uuid(),
    url text not null,
    title text,
    raw_text text,
    summary text,
    intent text check (intent in ('learn', 'build', 'inspire', 'share', 'reference')),
    tags text[],
    source text,  -- 'instagram', 'linkedin', 'web', etc.
    embedding vector(1536),
    last_accessed timestamptz,
    created_at timestamptz default now()
);

-- Index for vector similarity search
create index if not exists items_embedding_idx
    on items using ivfflat (embedding vector_cosine_ops)
    with (lists = 100);

-- Index for unread/review queries
create index if not exists items_last_accessed_idx
    on items (last_accessed, created_at);

-- Function to match items by embedding similarity
create or replace function match_items(
    query_embedding vector(1536),
    match_threshold float default 0.75,
    match_count int default 10
)
returns table (
    id uuid,
    url text,
    title text,
    summary text,
    intent text,
    tags text[],
    similarity float
)
language sql stable
as $$
    select
        id,
        url,
        title,
        summary,
        intent,
        tags,
        1 - (embedding <=> query_embedding) as similarity
    from items
    where 1 - (embedding <=> query_embedding) > match_threshold
    order by embedding <=> query_embedding
    limit match_count;
$$;
