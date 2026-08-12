-- 投稿検索用GINインデックス追加マイグレーション
-- 目的: title / excerpt / content の部分一致検索で pg_trgm GIN インデックスを利用可能にする

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_posts_search_trgm_gin ON posts
    USING GIN ((coalesce(title, '') || ' ' || coalesce(excerpt, '') || ' ' || coalesce(content, '')) gin_trgm_ops);

COMMIT;
