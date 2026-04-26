-- Google OAuth tokens (single-user app — exactly one row, id always = 1)
CREATE TABLE IF NOT EXISTS google_tokens (
    id          int PRIMARY KEY DEFAULT 1,
    access_token  text,
    refresh_token text NOT NULL,
    token_expiry  timestamptz,
    email         text,
    updated_at    timestamptz DEFAULT now(),
    CONSTRAINT single_row CHECK (id = 1)
);

-- Store the Calendar event ID on each item so we can update/delete it later
ALTER TABLE items
    ADD COLUMN IF NOT EXISTS calendar_event_id text;
