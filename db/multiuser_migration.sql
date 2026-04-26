-- ── Multi-user migration ────────────────────────────────────────────────────
-- Run ONCE in Supabase SQL Editor.
-- Items/library remain shared. Reminders + Google Calendar are per-user.

-- 1. Drop old single-row google_tokens, replace with per-user (keyed by email)
DROP TABLE IF EXISTS google_tokens;
CREATE TABLE google_tokens (
    email         text PRIMARY KEY,
    access_token  text,
    refresh_token text NOT NULL,
    token_expiry  timestamptz,
    updated_at    timestamptz DEFAULT now()
);

-- 2. Per-user reminders (separate from items)
CREATE TABLE IF NOT EXISTS user_reminders (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id           uuid REFERENCES items(id) ON DELETE CASCADE,
    user_email        text NOT NULL,
    remind_at         timestamptz NOT NULL,
    user_note         text,
    reminder_sent     boolean DEFAULT false,
    calendar_event_id text,
    created_at        timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_reminders_email_idx ON user_reminders(user_email);
CREATE INDEX IF NOT EXISTS user_reminders_due_idx   ON user_reminders(remind_at) WHERE NOT reminder_sent;

-- 3. Add user_email to devices so notifications go to the right person
ALTER TABLE devices ADD COLUMN IF NOT EXISTS user_email text;
