-- Deduplicate existing rows (keep the most recent per URL), then add
-- a unique constraint so future upserts work correctly.

-- Step 1: delete older duplicate rows, keeping the newest per URL
DELETE FROM items
WHERE id NOT IN (
    SELECT DISTINCT ON (url) id
    FROM items
    ORDER BY url, created_at DESC
);

-- Step 2: add unique constraint on url
ALTER TABLE items
    ADD CONSTRAINT items_url_unique UNIQUE (url);
