-- Add GIN index for post search
-- Purpose: enable pg_trgm GIN index usage for partial-match searches across title / excerpt / content

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_search_trgm_gin ON posts
    USING GIN ((coalesce(title, '') || ' ' || coalesce(excerpt, '') || ' ' || coalesce(content, '')) gin_trgm_ops);

DROP INDEX CONCURRENTLY IF EXISTS idx_posts_title_content_gin;
