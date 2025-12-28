-- サンプル投稿データ（テスト用）
-- このファイルはデータベース初期化時に自動実行されます

-- サンプル投稿1: 公開済み
INSERT INTO posts (title, slug, content, excerpt, author_id, status, published_at, created_at, updated_at)
VALUES 
(
    'LuaAIDiaryへようこそ',
    'welcome-to-luaaidiary',
    E'# LuaAIDiaryへようこそ\n\nこれはLuaで構築された高性能ブログシステムです。\n\n## 特徴\n\n- OpenRestyによる高速処理\n- WordPressテーマ互換\n- Gemini AI連携（準備中）\n\n詳しくは[ドキュメント](/docs)をご覧ください。',
    'LuaAIDiaryは、Luaで構築された高性能ブログシステムです。OpenRestyによる高速処理、WordPressテーマ互換、Gemini AI連携などの特徴があります。',
    1,  -- admin user
    'published',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);

-- サンプル投稿2: 公開済み
INSERT INTO posts (title, slug, content, excerpt, author_id, status, published_at, created_at, updated_at)
VALUES
(
    'ブログの使い方',
    'how-to-use-blog',
    E'# ブログの使い方\n\n管理画面から記事を投稿できます。\n\n## 記事の作成方法\n\n1. 管理画面にログイン\n2. 「新規投稿」をクリック\n3. タイトルと本文を入力\n4. 「公開」をクリック\n\n## カテゴリーとタグ\n\n投稿にはカテゴリーとタグを設定できます。カテゴリーは記事の分類に、タグはキーワードとして使用します。',
    '管理画面からブログ記事を簡単に投稿する方法を解説します。',
    1,
    'published',
    CURRENT_TIMESTAMP - INTERVAL '1 day',
    CURRENT_TIMESTAMP - INTERVAL '1 day',
    CURRENT_TIMESTAMP - INTERVAL '1 day'
);

-- サンプル投稿3: 下書き
INSERT INTO posts (title, slug, content, excerpt, author_id, status, published_at, created_at, updated_at)
VALUES
(
    '下書き記事のサンプル',
    'draft-sample',
    E'これは下書き状態の記事です。\n\nまだ公開されていません。\n\n## 下書きの用途\n\n- 執筆中の記事を保存\n- 公開前の確認\n- 予約投稿の準備',
    '下書き記事のサンプルです。',
    1,
    'draft',
    NULL,
    CURRENT_TIMESTAMP - INTERVAL '2 hours',
    CURRENT_TIMESTAMP - INTERVAL '2 hours'
);

-- 投稿とカテゴリーの関連付け
-- 投稿1: 'welcome-to-luaaidiary' -> 'news'カテゴリー
INSERT INTO post_categories (post_id, category_id)
SELECT p.id, c.id
FROM posts p, categories c
WHERE p.slug = 'welcome-to-luaaidiary' AND c.slug = 'news';

-- 投稿2: 'how-to-use-blog' -> 'tech'カテゴリー
INSERT INTO post_categories (post_id, category_id)
SELECT p.id, c.id
FROM posts p, categories c
WHERE p.slug = 'how-to-use-blog' AND c.slug = 'tech';

-- 投稿3: 'draft-sample' -> 'uncategorized'カテゴリー
INSERT INTO post_categories (post_id, category_id)
SELECT p.id, c.id
FROM posts p, categories c
WHERE p.slug = 'draft-sample' AND c.slug = 'uncategorized';

-- 投稿とタグの関連付け
-- 投稿1: 'welcome-to-luaaidiary' -> 'lua', 'openresty'タグ
INSERT INTO post_tags (post_id, tag_id)
SELECT p.id, t.id
FROM posts p, tags t
WHERE p.slug = 'welcome-to-luaaidiary' AND t.slug = 'lua';

INSERT INTO post_tags (post_id, tag_id)
SELECT p.id, t.id
FROM posts p, tags t
WHERE p.slug = 'welcome-to-luaaidiary' AND t.slug = 'openresty';

-- 投稿2: 'how-to-use-blog' -> 'lua', 'postgresql'タグ
INSERT INTO post_tags (post_id, tag_id)
SELECT p.id, t.id
FROM posts p, tags t
WHERE p.slug = 'how-to-use-blog' AND t.slug = 'lua';

INSERT INTO post_tags (post_id, tag_id)
SELECT p.id, t.id
FROM posts p, tags t
WHERE p.slug = 'how-to-use-blog' AND t.slug = 'postgresql';

-- コミット
COMMIT;
