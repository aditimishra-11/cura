-- AI News Pipeline Migration
-- Adds two nullable columns to items table.
-- Existing rows get NULL — no impact on current functionality.

ALTER TABLE items
  ADD COLUMN IF NOT EXISTS news_source   TEXT,
  ADD COLUMN IF NOT EXISTS news_category TEXT;

-- Optional index for filtering library by news category
CREATE INDEX IF NOT EXISTS idx_items_news_category ON items(news_category);
