# LuaAIDiary

Lua/OpenResty ベースの WordPress ライクなブログシステムです。管理画面、JSON API、Gemini による記事作成支援、ローカル画像メディア管理を備えています。

英語版は [`README.md`](README.md) を参照してください。

## 概要

LuaAIDiary は OpenResty、LuaJIT、Lapis、PostgreSQL、Valkey で構成されたブログ/CMS アプリケーションです。WordPress 風の公開 URL、認証付き管理画面、投稿・カテゴリー・タグ・メディア・認証用 API、Docker Compose ベースのローカル開発環境を提供します。

現在の実装には、管理画面でのコンテンツ管理、認証/権限管理、Gemini AI 連携、PostgreSQL メタデータと Docker ボリュームを利用する Phase 1 のローカル画像アップロード機能が含まれます。

## 実装済み機能

### 公開ブログフロントエンド

- ホーム、単一投稿、カテゴリーアーカイブ、タグアーカイブ、著者アーカイブ、日付アーカイブ、検索結果、404 表示。
- `/`, `/posts/:slug`, `/category/:slug`, `/tag/:slug`, `/author/:username`, `/search`, 日付アーカイブなどの WordPress 風ルーティング。
- 記事一覧画面と記事表示画面のサイドバー検索フォームから、公開記事をタイトル・抜粋・本文の部分一致で検索できます。
- 検索 URL は `/search?s=keyword` の形式で、検索結果は検索結果画面のサイドバー内にレスポンシブ表示されます。
- [`app/init.lua`](app/init.lua) で接続されている公開表示用コントローラー経路による基本表示。

### 管理画面

- ログイン/ログアウト、パスワード変更画面。
- サイト統計、最近の投稿、システム情報を表示するダッシュボード。
- 投稿一覧・作成・編集・削除、draft/published/trash のステータス管理、カテゴリー/タグ設定、Markdown プレビュー、メディアピッカー連携。
- カテゴリー管理、タグ管理。
- 管理者向けユーザー管理、認証済みユーザー向けプロフィール編集。
- サイト設定、AI 設定、Gemini API キー管理。
- 画像アップロード、検索、名称変更、削除、利用状態表示を行うメディアライブラリ。

### API

- 認証 API: 登録、ログイン、ログアウト、現在ユーザー取得、パスワード変更、認証状態確認。
- 更新系リクエスト向け CSRF トークン API。
- 投稿 CRUD API、カテゴリー/タグ設定、所有者チェック。
- ロール権限付きのカテゴリー/タグ CRUD API。
- 画像アップロード、一覧、詳細、名称変更、論理削除を行うメディア API。
- Markdown プレビュー API。
- Gemini による記事生成、校正、接続テスト API。
- AI 設定 API と暗号化 Gemini API キー保存。

### 認証とセキュリティ

- Valkey を利用したセッションベース認証。
- `admin`, `editor`, `author`, `subscriber` ロールによるアクセス制御。
- 更新系 API と管理画面フォーム向け CSRF 保護。
- 認証サービスによるパスワードハッシュ化。
- ユーザー設定モデルによる Gemini API キーの暗号化保存対応。

### メディアアップロード

- `jpg`, `jpeg`, `png`, `webp`, `gif` のローカル画像アップロード。
- 管理画面メディアライブラリと投稿編集画面のメディアピッカー。
- `media` と `media_post_usages` テーブルによるメタデータ管理。
- SHA-256 による重複検知と既存アクティブメディアの再利用。
- `vips`/`vipsheader` が利用できる場合のサムネイル生成と、生成失敗時の原本 URL フォールバック。
- 投稿から参照中のメディア削除を防ぐ論理削除。投稿作成/更新時に `/uploads/...` 参照を `media_post_usages` へ同期。
- アップロードファイルは `/app/uploads` にマウントされた `media_uploads` Docker ボリュームに保存。

### データベースとキャッシュ

- ユーザー、投稿、コメント、カテゴリー、タグ、ユーザー設定、サンプルデータ、AI 設定、性能向上インデックス、メディアテーブル用の PostgreSQL 初期化スクリプト。
- 投稿タイトル/本文向け PostgreSQL 全文検索インデックス。
- セッションおよびキャッシュ関連サービスで Valkey を利用。

## 技術スタック

- **言語**: Lua
- **ランタイム/Web サーバー**: OpenResty + LuaJIT + Nginx
- **Web フレームワーク**: Lapis
- **データベース**: PostgreSQL 18
- **セッション/キャッシュストア**: Valkey 9
- **テンプレート**: 管理画面は ETV Lua テンプレート、公開画面は Lua/公開表示用コード
- **AI 統合**: Google Gemini API
- **テスト**: Busted、シェルベース E2E テスト、統合テスト
- **静的解析**: Luacheck
- **コンテナ**: Docker、Docker Compose

## プロジェクト構成

```text
LuaAIDiary/
├── app/
│   ├── init.lua                 # Lapis アプリケーションとルーティング
│   ├── controllers/             # 公開/API/管理/認証/メディア/Gemini コントローラー
│   ├── models/                  # DB モデル
│   ├── services/                # 認証、キャッシュ、Gemini サービス
│   ├── middleware/              # 認証、CSRF、ページキャッシュミドルウェア
│   ├── theme_engine/            # 実験的/未完成のテーマ関連コード
│   ├── utils/                   # 暗号化、Markdown、セッション、slug、バリデーション
│   └── views/admin/             # 管理画面テンプレート
├── docker/web/                  # OpenResty イメージと Nginx 設定
├── docs/                        # 機能仕様・設計ドキュメント
├── postgresql/init/             # DB 初期化スクリプト
├── postgresql/migrations/       # 既存 DB 向け追加マイグレーション
├── static/                      # 管理画面 CSS/JavaScript と静的アセット
├── tests/                       # ユニット、統合、E2E、性能、関連テスト
├── wp-content/themes/           # リポジトリに残っている実験的テーマアセット
├── docker-compose.yml
├── Makefile
├── README.md
└── README_JP.md
```

## クイックスタート

### 前提条件

- Docker 20.10+
- Docker Compose 2.0+
- Make（主要開発タスク用に推奨）

### 推奨セットアップ

```bash
git clone https://github.com/hawkie275/LuaAIDiary.git
cd LuaAIDiary
make setup
```

`make setup` は、必要に応じて `.env.example` から `.env` を作成し、GHCR から最新 Web イメージを取得、`APP_VERSION` を同期、サービスを起動し、DB 起動を短時間待機します。

GHCR から取得せずローカルで Docker イメージをビルドする場合:

```bash
make setup-build
```

### 手動セットアップ

```bash
cp .env.example .env
docker compose up -d --build
sleep 10
```

### アクセス URL

- 公開サイト: <http://localhost:8080>
- 管理画面: <http://localhost:8080/admin>
- ヘルスチェック: <http://localhost:8080/health>

デフォルト管理者ユーザーは PostgreSQL 初期化スクリプトで作成されます。詳細は [`postgresql/init/01_create_tables.sql`](postgresql/init/01_create_tables.sql) と [`postgresql/init/02_update_admin_password.sql`](postgresql/init/02_update_admin_password.sql) を確認し、初回ログイン後にパスワードを変更してください。

## 主要 Make コマンド

```bash
make help              # 利用可能なコマンドを表示
make setup             # GHCR の Web イメージを使った初期セットアップ
make setup-build       # ローカル Docker ビルドで初期セットアップ
make dev               # フォアグラウンドでサービス起動
make build             # Docker イメージを no-cache でビルド
make up                # バックグラウンドでサービス起動
make down              # サービス停止
make restart           # サービス再起動
make logs              # 全サービスログを追跡
make logs-web          # Web ログを追跡
make logs-db           # PostgreSQL ログを追跡
make logs-redis        # Valkey ログを追跡
make shell             # Web コンテナのシェルを開く
make shell-lua         # Web コンテナ内で Lua シェルを起動
make shell-db          # DB コンテナのシェルを開く
make psql              # PostgreSQL クライアントを開く
make redis-cli         # Valkey/Redis CLI を開く
make migrate           # 既存 DB にメディアテーブルマイグレーションを適用
make health            # /health を確認
make status            # Docker Compose サービス状態を表示
make db-reset          # 確認後に DB をリセット
make clean             # 確認後にコンテナとボリュームを削除
```

## テストと品質確認

E2E テストと統合テストはサービス起動後に実行します。

```bash
make up
make health
make test              # make test-e2e 経由で E2E テストを実行
make test-e2e          # 投稿 API とメディア API の E2E スクリプトを実行
make test-integration  # 実 DB に対する統合テストを実行
make test-all          # 設定済み E2E テストターゲットを実行
make test-file FILE=/tests/path/to/spec.lua
make lint              # app/ と tests/ に Luacheck を実行
```

主なテスト領域:

- [`tests/e2e`](tests/e2e): 投稿、メディア、認証/管理画面、カテゴリー/タグ、パスワード変更、ユーザー管理の HTTP ベース E2E テスト。
- [`tests/controllers`](tests/controllers): コントローラー spec。
- [`tests/models`](tests/models): モデル spec。
- [`tests/middleware`](tests/middleware): CSRF ミドルウェア spec。
- [`tests/theme_engine`](tests/theme_engine): リポジトリに残っている実験的テーマ関連コードのテスト。
- [`tests/integration`](tests/integration): 実 DB 統合テスト。
- [`tests/performance`](tests/performance): ベンチマークスクリプトとレポート。

## 利用可能なエンドポイント

### 公開エンドポイント

| ルート | 用途 |
| --- | --- |
| `/` | ホーム/投稿一覧 |
| `/posts/:slug` | 単一投稿 |
| `/category/:slug` | カテゴリーアーカイブ |
| `/tag/:slug` | タグアーカイブ |
| `/author/:username` | 著者アーカイブ |
| `/search?s=keyword` | 公開記事をタイトル・抜粋・本文で検索し、サイドバー内にレスポンシブ表示 |
| `/:year`, `/:year/:month`, `/:year/:month/:day` | 日付アーカイブ |

### 認証 API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/auth/register` | POST | ユーザー登録 | 不要 |
| `/api/auth/login` | POST | ログイン | 不要 |
| `/api/auth/logout` | POST | ログアウト | 必要 |
| `/api/auth/me` | GET | 現在のユーザー取得 | 必要 |
| `/api/auth/change-password` | POST | パスワード変更 | 必要 |
| `/api/auth/check` | GET | 認証状態確認 | 任意 |
| `/api/csrf-token` | GET | CSRF トークン取得 | セッションベース |

### 投稿 API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/posts` | GET | 投稿一覧取得 | 任意 |
| `/api/posts` | POST | 投稿作成 | 必要 |
| `/api/posts/:id` | GET | 投稿詳細取得 | 任意、下書きは制限あり |
| `/api/posts/:id` | PUT | 投稿更新 | 所有者 |
| `/api/posts/:id` | DELETE | 投稿削除 | 所有者 |

### カテゴリー API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/categories` | GET | カテゴリー一覧取得 | 不要 |
| `/api/categories` | POST | カテゴリー作成 | editor または admin |
| `/api/categories/:id` | GET | カテゴリー詳細取得 | 不要 |
| `/api/categories/:id` | PUT | カテゴリー更新 | editor または admin |
| `/api/categories/:id` | DELETE | カテゴリー削除 | editor または admin |

### タグ API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/tags` | GET | タグ一覧取得 | 不要 |
| `/api/tags` | POST | タグ作成 | author 以上 |
| `/api/tags/:id` | GET | タグ詳細取得 | 不要 |
| `/api/tags/:id` | PUT | タグ更新 | editor または admin |
| `/api/tags/:id` | DELETE | タグ削除 | editor または admin |

### メディア API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/media` | GET | アップロード済み画像のページネーション/検索付き一覧 | editor または admin |
| `/api/media` | POST | multipart form-data による画像アップロード | editor または admin + CSRF |
| `/api/media/:id` | GET | 画像メタデータ取得 | editor または admin |
| `/api/media/:id` | PATCH | 画像名/alt テキスト更新 | editor または admin + CSRF |
| `/api/media/:id` | DELETE | 未使用画像の論理削除 | editor または admin + CSRF |

対応画像形式は `jpg`, `jpeg`, `png`, `webp`, `gif` です。メディアメタデータは PostgreSQL に保存し、ファイル本体は `media_uploads` Docker ボリューム経由で `/app/uploads` に保存します。

現在のメディア API の挙動:

- アップロード時は multipart の `file` が必須、`alt_text` は任意です。
- 新規アップロードは `201` を返し、`success`, `id`, `file_name`, `url`, `thumbnail_url`, `mime_type`, `size_bytes`, `width`, `height`, `alt_text`, `usage_count`, `in_use`, `deduplicated` を返します。
- SHA-256 で重複を検知した場合は既存のアクティブメディアを `200` と `deduplicated: true` で返します。
- `GET /api/media` は `page`, `per_page`, `q` クエリに対応します。
- `PATCH /api/media/:id` は `file_name` が必須で、`alt_text` も更新できます。
- `DELETE /api/media/:id` は投稿から参照中の場合 `409` を返します。
- 10 MB を超えるファイルは `413`、未対応拡張子/MIME 不一致は `415` になります。

### 管理画面エンドポイント

| ルート | 用途 |
| --- | --- |
| `/admin/login` | ログイン画面 |
| `/admin` | ダッシュボードへリダイレクト |
| `/admin/dashboard` | ダッシュボード |
| `/admin/posts` | 投稿管理 |
| `/admin/posts/new` | 新規投稿フォーム |
| `/admin/posts/:id/edit` | 投稿編集フォーム |
| `/admin/categories` | カテゴリー管理 |
| `/admin/tags` | タグ管理 |
| `/admin/media` | メディアライブラリ |
| `/admin/users` | ユーザー管理 |
| `/admin/users/new` | 新規ユーザーフォーム |
| `/admin/users/:id/edit` | ユーザー編集フォーム |
| `/admin/profile` | ユーザープロフィール |
| `/admin/profile/edit` | 現在ユーザーのプロフィール編集 |
| `/admin/settings` | サイト/AI 設定 |
| `/admin/change-password` | パスワード変更 |

### Gemini AI API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/gemini/generate-article` | POST | 記事本文生成 | 必要 + CSRF |
| `/api/gemini/proofread` | POST | 記事本文の校正/改善 | 必要 + CSRF |
| `/api/gemini/test-connection` | POST | Gemini API 接続テスト | 必要 + CSRF |

### AI 設定 API エンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
| --- | --- | --- | --- |
| `/api/settings/ai-preferences` | GET | 現在の AI 設定取得 | 必要 |
| `/api/settings/ai-preferences/defaults` | GET | AI 設定のデフォルト値取得 | 必要 |
| `/api/settings/ai-preferences` | PUT | AI 設定更新 | 必要 + CSRF |
| `/api/settings/gemini-api-key` | POST | Gemini API キー保存 | 必要 + CSRF |
| `/api/settings/gemini-api-key` | DELETE | Gemini API キー削除 | 必要 + CSRF |

### その他のエンドポイント

| エンドポイント | メソッド | 説明 |
| --- | --- | --- |
| `/health` | GET | ヘルスチェック |
| `/api/db-test` | GET | PostgreSQL 接続テスト |
| `/api/redis-test` | GET | Valkey 接続テスト |
| `/api/models-test` | GET | モデル読み込み確認 |
| `/api/preview/markdown` | POST | 管理画面エディタ向け Markdown プレビュー |

### 例: ヘルスチェック

```bash
curl http://localhost:8080/health
```

レスポンス例:

```json
{
  "status": "ok",
  "service": "LuaAIDiary",
  "version": "0.1.0",
  "timestamp": 1760000000
}
```

### 例: データベース接続テスト

```bash
curl http://localhost:8080/api/db-test
```

レスポンス例:

```json
{
  "status": "success",
  "message": "データベース接続成功",
  "postgres_version": "PostgreSQL ...",
  "database": "luaaidiary",
  "host": "db"
}
```

## データベース補足

新規コンテナでは [`postgresql/init`](postgresql/init) 配下のスクリプトが実行されます。既存 DB にメディアテーブルを追加する場合は以下を実行します。

```bash
make migrate
```

メディアアップロード用メタデータは [`postgresql/init/06_add_media_tables.sql`](postgresql/init/06_add_media_tables.sql) で作成され、既存 DB 向けの同等マイグレーションは [`postgresql/migrations/001_add_media_tables.sql`](postgresql/migrations/001_add_media_tables.sql) です。

### 主なテーブル

- `users`: ユーザーアカウントとロール。
- `posts`: `draft`, `published`, `trash` ステータスを持つ投稿。
- `comments`: コメントデータとモデレーション状態。
- `categories`, `tags`: タクソノミーデータ。
- `post_categories`, `post_tags`: 投稿とタクソノミーの関連。
- `user_settings`: AI 設定と Gemini API キー保存。
- `post_meta`: 投稿カスタムメタデータ。
- `media`: アップロード済み画像メタデータ。
- `media_post_usages`: 投稿と参照メディアの関連。投稿本文内の `/uploads/...` URL から同期されます。

## 開発ワークフロー

### ホットリロード

開発時は `make dev` でフォアグラウンド起動し、必要に応じて `make restart` でコンテナを再起動します。OpenResty/Lapis 側の反映タイミングに応じてリロードまたは再起動してください。

### 静的解析

```bash
make lint
```

Luacheck は [`app`](app) と [`tests`](tests) を対象に実行されます。

### データベースリセット

```bash
make db-reset
```

確認後、初期化スクリプトを使って DB を再作成します。既存のアプリケーションデータは削除されます。

### ログ監視

```bash
make logs
make logs-web
make logs-db
make logs-redis
```

## セキュリティ

### 本番環境での重要な設定

本番利用前に少なくとも以下を確認してください。

- デフォルト管理者認証情報を変更する。
- `.env` の `POSTGRES_PASSWORD` とアプリケーションシークレットを強い値にする。
- Gemini API キー保存に使う暗号化キーを設定し、安全に管理する。
- 外部公開が不要な DB/キャッシュポートを制限する。
- リバースプロキシやロードバランサーで HTTPS を利用する。
- メディアアップロードのサイズ制限と MIME 許可設定を確認する。

### 実装済みセキュリティ機能

#### パスワードセキュリティ

- パスワードハッシュ化は認証サービスで処理します。
- API と管理画面の両方でパスワード変更に対応しています。

#### セッション管理

- セッションデータは Valkey に保存されます。
- 認証状態はコントローラーおよびミドルウェアで確認されます。

#### CSRF 保護

- 更新系リクエストでは CSRF トークンを生成・検証します。
- API 利用時は `/api/csrf-token` からトークンを取得できます。

#### API キー暗号化

- Gemini API キー保存はユーザー設定モデルと暗号化ユーティリティを通じて扱います。
- 各ユーザーが自分の Gemini API キーを管理します。

#### ロールベースアクセス制御

- 管理ダッシュボードとメディアライブラリは `admin` または `editor` が必要です。
- ユーザー管理は `admin` のみ利用できます。
- 投稿/カテゴリー/タグ API と管理画面操作ではロールと所有者チェックを行います。

#### 入力検証

- コントローラーで必須項目、ID、ステータス値、メディア制約を検証します。
- メディアアップロードでは拡張子/MIME の整合性とサイズ制限を検証します。

## 環境変数

[`.env.example`](.env.example) から `.env` を作成してください。主な変数は以下です。

| 変数 | 用途 |
| --- | --- |
| `POSTGRES_DB` | PostgreSQL データベース名 |
| `POSTGRES_USER` | PostgreSQL ユーザー |
| `POSTGRES_PASSWORD` | PostgreSQL パスワード |
| `IMAGE_TAG` | Docker Compose/GHCR ワークフローで使う Web イメージタグ |
| `APP_VERSION` | 管理画面のシステム情報に表示するアプリケーションバージョン |
| `ENCRYPTION_KEY` | 設定時、暗号化されたシークレット保存に使うキー素材 |

`POSTGRES_HOST`, `POSTGRES_PORT`, `REDIS_HOST`, `REDIS_PORT`, `LAPIS_ENVIRONMENT` などのコンテナ実行時変数は [`docker-compose.yml`](docker-compose.yml) から渡されます。

## トラブルシューティング

### サービスが起動しない

```bash
make status
make logs
```

Docker が起動しているか、`.env` が存在するか、必要なポートが空いているか確認してください。

### ポートが既に使用されている

デフォルトのサービスポートは以下です。

- Web: `8080`
- PostgreSQL: `5432`
- Valkey: `6379`

他プロセスが使用している場合は [`docker-compose.yml`](docker-compose.yml) のポートマッピングを変更してください。

### データベース接続エラー

```bash
make logs-db
make psql
curl http://localhost:8080/api/db-test
```

`.env` の `POSTGRES_*` 値と `db` サービスのヘルス状態を確認してください。

### テストが失敗する

```bash
make up
make health
make test-e2e
```

E2E テストはアプリケーションが期待するベース URL で起動している必要があります。一部のスクリプトは一時ユーザーやコンテンツを作成します。

### メディアアップロードが失敗する

- ファイル形式が `jpg`, `jpeg`, `png`, `webp`, `gif` のいずれかか確認する。
- ファイルサイズがアップロード上限内か確認する。
- `make logs-web` で Web ログを確認する。
- 既存 DB の場合は `make migrate` 適用済みか確認する。
- 削除時に `409` になる場合は、先に投稿本文から画像参照を削除し、利用状況同期で参照を解消してください。

### コンテナビルドエラー

```bash
make build
make logs-web
```

レジストリイメージを使う場合は `make setup`、ローカル Docker 変更を開発する場合は `make setup-build` を実行してください。

## 関連ドキュメント

- [`ARCHITECTURE.md`](ARCHITECTURE.md): アーキテクチャ概要。
- [`DESIGN.md`](DESIGN.md): 詳細設計メモ。
- [`README_ADMIN.md`](README_ADMIN.md): 管理画面ダッシュボード実装メモ。
- [`README_AUTH.md`](README_AUTH.md): 認証システムドキュメント。
- [`README_POST_API.md`](README_POST_API.md): 投稿 API ドキュメント。
- [`docs/media_upload_feature_spec.md`](docs/media_upload_feature_spec.md): メディアアップロード機能仕様。
- [`docs/media_upload_design.md`](docs/media_upload_design.md): メディアアップロード実装設計。
- [`tests/e2e/README.md`](tests/e2e/README.md): E2E テストガイド。
- [`tests/integration/README.md`](tests/integration/README.md): 統合テストガイド。
- [`tests/performance/README.md`](tests/performance/README.md): 性能テストガイド。

## ライセンス

MIT License。詳細は [`LICENSE`](LICENSE) を参照してください。
