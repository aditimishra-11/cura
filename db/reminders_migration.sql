-- Run this in Supabase SQL Editor after the initial schema

-- Add reminder fields to items
alter table items add column if not exists remind_at timestamptz;
alter table items add column if not exists user_note text;
alter table items add column if not exists reminder_sent boolean default false;

-- Device FCM tokens
create table if not exists devices (
    id uuid primary key default gen_random_uuid(),
    fcm_token text not null unique,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Index for due reminders query
create index if not exists items_remind_at_idx
    on items (remind_at)
    where remind_at is not null and reminder_sent = false;
