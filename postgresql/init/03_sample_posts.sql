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

-- サンプル投稿4: 公開済み（技術記事）
INSERT INTO posts (title, slug, content, excerpt, author_id, status, published_at, created_at, updated_at)
VALUES
(
    'WordPressの常識を覆す！OpenRestyとLuaJITで実現する爆速ブログの秘密',
    'wordpress-openresty-luajit-blazing-blog',
    E'<font color="#ff0000">**この記事は当ブログツールの標準搭載機能である『AI記事生成機能』を使用して作成しています。**</font><br>\r\n<font color="#ff0000">(事前にGeminiのAPIキーの取得と設定が必要です)</font>\r\n\r\n## はじめに\r\n\r\nWebサイト、特にブログを運営する上で、速度と安定性は非常に重要な要素です。多くの人が利用するWordPressは、その柔軟性と豊富なプラグインで人気ですが、時にパフォーマンス面での課題を抱えることがあります。PHPとリレーショナルデータベースを多用する特性上、ページの表示速度やサーバーリソースの消費が問題となるケースも少なくありません。\r\n\r\nしかし、もしWordPressライクな機能性を持ちながら、圧倒的な速度と高いスケーラビリティを誇るブログツールが実現できるとしたらどうでしょうか？本記事では、その答えとなる「OpenRestyとLuaJIT」という強力な組み合わせに焦点を当て、WordPressと比べて超高速なブログツールを構築する技術とその魅力について、初心者の方にも分かりやすく解説します。\r\n\r\n## OpenRestyとは何か？爆速の基盤\r\n\r\nOpenRestyは、高性能なWebサーバーであるNginxを基盤とし、その上でLuaJITという超高速なスクリプト言語を実行できるように拡張されたWebプラットフォームです。Nginxが元々持つ非同期I/Oとイベント駆動モデルにより、大量の同時接続を効率的に処理できる特性を、OpenRestyは最大限に活用します。\r\n\r\nこれにより、従来のWebサーバーでは実現が難しかった高並行処理と低レイテンシ（応答速度の速さ）を両立させることが可能になります。WebアプリケーションのロジックをNginxの内部で直接LuaJITで記述・実行するため、PHP-FPMのような外部プロセスとの通信オーバーヘッドが発生せず、驚異的なパフォーマンスを発揮するのです。\r\n\r\n## LuaとLuaJITがもたらす圧倒的なパフォーマンス\r\n\r\nOpenRestyの心臓部とも言えるのが、スクリプト言語のLuaと、そのJIT（Just-In-Time）コンパイラ版であるLuaJITです。\r\n\r\n### Luaの軽量性と高速性\r\n\r\nLuaは非常に軽量で、組み込み用途からゲーム開発まで幅広く使われる言語です。そのシンプルな文法と高い実行速度が特徴です。\r\n\r\n### LuaJITによる桁違いの速度\r\n\r\nLuaJITは、その名の通りLuaのコードをリアルタイムで機械語に変換（JITコンパイル）することで、C言語に匹敵するほどの実行速度を実現します。一般的なスクリプト言語がインタプリタ方式でコードを一行ずつ解釈・実行するのに対し、LuaJITは頻繁に実行されるコードパスを最適化し、ネイティブコードとして実行するため、Webアプリケーションにおけるデータ処理やページ生成の速度が劇的に向上します。これにより、サーバーのリソース消費を抑えつつ、ユーザーへの応答速度を極限まで高めることが可能になるのです。\r\n\r\n## WordPressライクなブログツールを実現するアーキテクチャ\r\n\r\nWordPressがPHPとMySQLなどのリレーショナルデータベースで動くのに対し、OpenRestyとLuaJITでブログツールを構築する場合、そのアーキテクチャは大きく異なります。\r\n\r\n### 動的なページ生成とデータストア\r\n\r\nOpenRestyの内部で動作するLuaスクリプトが、ユーザーからのリクエストに応じて動的にHTMLページを生成します。記事データなどのコンテンツは、PostgreSQLのようなリレーショナルデータベースだけでなく、Redisのような高速なKVS（Key-Value Store）や、CassandraのようなNoSQLデータベースと連携して管理できます。特にRedisは、キャッシュ層として活用することで、データベースへのアクセス頻度を減らし、さらなる高速化に貢献します。\r\n\r\n### Lapisフレームワークの活用\r\n\r\nこのブログもOpenRestyとLuaJIT、Lapisを使って構築されています。Lapisは、OpenResty上で動作するLua製のWebフレームワークで、MVC（Model-View-Controller）モデルに基づいた開発をサポートします。ルーティング、データベース連携、テンプレートエンジンなどの機能を提供し、WordPressのような動的なブログシステムを効率的に構築するための強力なツールとなります。Lapisを利用することで、開発者は複雑なNginx設定を意識することなく、Luaのコードに集中してアプリケーションロジックを記述できます。\r\n\r\n## なぜOpenRestyとLuaJITで爆速ブログが可能なのか？\r\n\r\n*   **プロセス起動オーバーヘッドの排除**: PHPのようにリクエストごとにプロセスを起動するオーバーヘッドがなく、Nginxの内部で直接LuaJITがコードを実行するため、非常に高速です。\r\n*   **JITコンパイルによる実行速度**: LuaJITがコードをネイティブコードにコンパイルすることで、スクリプト言語でありながらC言語に近い速度で動作します。\r\n*   **非同期処理と高効率なリソース利用**: OpenRestyの非同期I/Oモデルにより、一つのプロセスで多数のリクエストを同時に処理でき、サーバーリソースを最大限に活用します。\r\n*   **柔軟なキャッシュ戦略**: Luaスクリプト内でRedisなどの高速キャッシュを積極的に利用することで、データベースへの負荷を軽減し、さらに高速なコンテンツ配信を実現します。\r\n\r\nこれらの特性により、OpenRestyとLuaJITで構築されたブログは、WordPressと比べて超高速な応答速度と高い同時接続数を実現し、ユーザー体験を飛躍的に向上させることができます。\r\n\r\n## 結論\r\n\r\nOpenRestyとLuaJITの組み合わせは、Webアプリケーション開発、特にブログのようなコンテンツ配信システムにおいて、従来の技術スタックでは得られなかった圧倒的なパフォーマンスとスケーラビリティをもたらします。WordPressの柔軟性やエコシステムには及ばない部分もありますが、速度とリソース効率を最優先するプロジェクトにおいては、非常に強力な選択肢となり得ます。\r\n\r\n本記事で紹介したように、このブログ自体もOpenRestyとLuaJIT、Lapisを使って構築されており、そのパフォーマンスの恩恵を日々享受しています。学習コストはかかるかもしれませんが、Webの新たな可能性を追求したい方にとって、OpenRestyとLuaJITは挑戦する価値のある魅力的な技術スタックとなるでしょう。ぜひこの爆速の世界を体験してみてください。',
    'WordPressの速度に不満？OpenRestyとLuaJITで実現する爆速ブログツールを解説。Nginxベースの高性能プラットフォームとLuaJITの超高速実行が、WordPressと比べて圧倒的なパフォーマンスをもたらします。Lapisフレームワークを使った具体的な構築例も紹介。このブログもOpenRestyとLuaJIT、Lapisで動いています。',
    1,
    'published',
    CURRENT_TIMESTAMP - INTERVAL '3 days',
    CURRENT_TIMESTAMP - INTERVAL '3 days',
    CURRENT_TIMESTAMP - INTERVAL '3 days'
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

-- 投稿4: 'wordpress-openresty-luajit-blazing-blog' -> 'tech'カテゴリー
INSERT INTO post_categories (post_id, category_id)
SELECT p.id, c.id
FROM posts p, categories c
WHERE p.slug = 'wordpress-openresty-luajit-blazing-blog' AND c.slug = 'tech';

-- 投稿4: 'wordpress-openresty-luajit-blazing-blog' -> 'lua', 'openresty'タグ
INSERT INTO post_tags (post_id, tag_id)
SELECT p.id, t.id
FROM posts p, tags t
WHERE p.slug = 'wordpress-openresty-luajit-blazing-blog' AND t.slug = 'lua';

INSERT INTO post_tags (post_id, tag_id)
SELECT p.id, t.id
FROM posts p, tags t
WHERE p.slug = 'wordpress-openresty-luajit-blazing-blog' AND t.slug = 'openresty';

-- コミット
COMMIT;
