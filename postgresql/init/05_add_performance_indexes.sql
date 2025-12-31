-- パフォーマンス改善用インデックス追加マイグレーション
-- 作成日: 2025-12-31
-- 目的: 頻繁に使用されるクエリのパフォーマンスを最適化

-- 1. 公開記事の高速取得用複合インデックス
-- トップページでの公開記事一覧取得を高速化
-- status='published'でフィルタリングし、published_atで降順ソート
CREATE INDEX IF NOT EXISTS idx_posts_published 
ON posts(status, published_at DESC);

COMMENT ON INDEX idx_posts_published IS '公開記事の一覧取得を高速化（トップページ用）';

-- 2. カテゴリー別記事取得用インデックス
-- post_categoriesテーブルでのカテゴリー絞り込みを高速化
CREATE INDEX IF NOT EXISTS idx_post_categories_category 
ON post_categories(category_id, post_id);

COMMENT ON INDEX idx_post_categories_category IS 'カテゴリー別記事一覧の取得を高速化';

-- 3. タグ検索用複合インデックス
-- 特定タグに紐づく記事の検索を高速化
CREATE INDEX IF NOT EXISTS idx_post_tags_composite 
ON post_tags(tag_id, post_id);

COMMENT ON INDEX idx_post_tags_composite IS 'タグでの記事検索を高速化';

-- 4. 著者別記事取得用複合インデックス
-- 特定ユーザー（著者）の記事一覧取得を高速化
CREATE INDEX IF NOT EXISTS idx_posts_author_published 
ON posts(author_id, published_at DESC);

COMMENT ON INDEX idx_posts_author_published IS '特定著者の記事一覧取得を高速化';

-- 5. スラッグ検索用インデックス（冪等性確保）
-- 個別記事ページでのURL→記事取得を高速化
-- 注: このインデックスは01_create_tables.sqlで既に作成されていますが、
-- 冪等性確保のためIF NOT EXISTSで再定義
CREATE INDEX IF NOT EXISTS idx_posts_slug 
ON posts(slug);

COMMENT ON INDEX idx_posts_slug IS '個別記事ページの高速化（URLからの記事取得）';

-- インデックス作成完了
-- 以下のインデックスが追加/確認されました:
-- - idx_posts_published: 公開記事一覧の高速化
-- - idx_post_categories_category: カテゴリー別記事の高速化
-- - idx_post_tags_composite: タグ検索の高速化
-- - idx_posts_author_published: 著者別記事の高速化
-- - idx_posts_slug: スラッグ検索の高速化（冪等性確保）
