# LuaAIDiary

LuaベースのWordPressライクなブログシステム

## 概要

LuaAIDiaryは、OpenResty（Nginx + LuaJIT）、Lapis、PostgreSQL、Redisを使用した高性能なブログシステムです。Docker Composeを使用して簡単にセットアップでき、テスト実行しながら開発できる環境を提供します。

## 主な特徴

- **超高速動作**: OpenResty + LuaJIT による非同期I/O処理で、従来のPHP製CMSと比較して数倍のパフォーマンスを実現
- **AI記事生成**: Gemini API統合により、トピックから完全な記事を自動生成
- **AI校正機能**: 文法・表現・構成を自動改善
- **完全な管理画面**: WordPress風のダッシュボードで直感的なコンテンツ管理
- **軽量**: LuaJIT による高速なスクリプト実行
- **ロールベースアクセス制御**: 5段階の権限管理（admin/editor/author/contributor/subscriber）
- **全文検索**: PostgreSQL GINインデックスによる高速検索
- **テスト環境**: Busted による自動テスト対応
- **開発ツール**: Makefile、Luacheck による開発効率化
- **スケーラブル**: Redis、PostgreSQL による水平スケーリング対応
- **ホットリロード**: コード変更時の自動反映
- **セキュア**: bcrypt、CSRF保護、暗号化APIキー管理

## ⚡ パフォーマンス

LuaAIDiary は高性能CMSとして設計されており、以下のベンチマーク結果を達成しています：

- **スループット**: 70,405 req/sec
- **レイテンシ**: 2.83ms（平均）
- **スケール**: 日間60億PV、月間1.8兆PVに対応可能
- **評価**: ⭐⭐⭐⭐⭐ エンタープライズグレード

*ベンチマーク環境: AMD Ryzen 7 6800HS (8C/16T), 7.8GB RAM, Ubuntu 24.04 LTS (WSL2)*

📊 **詳細なパフォーマンスレポート**: [`tests/performance/results/performance_improvement_report.md`](tests/performance/results/performance_improvement_report.md)

## 技術スタック

- **Webフレームワーク**: Lapis (OpenResty/Nginx + LuaJIT)
- **データベース**: PostgreSQL 15（全文検索、JSONB対応）
- **キャッシュ/セッション**: Redis 7
- **AI統合**: Google Gemini API
- **テストフレームワーク**: Busted
- **静的解析**: Luacheck
- **コンテナ化**: Docker & Docker Compose
- **言語**: Lua

### なぜ OpenResty + LuaJIT なのか？

OpenResty は Nginx に LuaJIT を統合したプラットフォームで、以下の利点があります：

1. **非同期I/O**: イベント駆動型アーキテクチャにより、同時接続数が多い環境でも高パフォーマンス
2. **低メモリ使用量**: LuaJIT のJITコンパイラにより、PHP等と比較してメモリ効率が高い
3. **高速レスポンス**: Nginxのイベントループ上で直接Luaコードが実行されるため、CGI/FastCGIのオーバーヘッドなし
4. **C拡張との親和性**: FFI（Foreign Function Interface）により、C言語ライブラリを直接呼び出し可能

## ディレクトリ構造

```
LuaAIDiary/
├── app/                        # アプリケーションコード
│   ├── init.lua               # Lapisアプリケーションエントリーポイント
│   ├── config/                # 設定ファイル
│   ├── controllers/           # コントローラー層
│   ├── models/                # モデル層
│   ├── views/                 # ビュー層（テンプレート）
│   ├── middleware/            # ミドルウェア
│   └── utils/                 # ユーティリティ関数
├── tests/                     # テストコード
│   ├── test_helper.lua        # テストヘルパー
│   ├── test_database.lua      # データベーステスト
│   └── test_health.lua        # ヘルスチェックテスト
├── static/                    # 静的ファイル
│   ├── css/
│   ├── js/
│   └── images/
├── docker/                    # Docker関連ファイル
│   └── web/
│       ├── Dockerfile         # OpenResty + Lapis環境
│       └── nginx.conf         # Nginx設定
├── postgresql/                # PostgreSQL関連
│   └── init/
│       └── 01_create_tables.sql  # データベース初期化スクリプト
├── Makefile                   # 開発タスク自動化
├── .luacheckrc               # Luacheck設定
├── docker-compose.yml         # Docker Compose設定
├── .env.example              # 環境変数のサンプル
├── ARCHITECTURE.md           # アーキテクチャ設計書
└── DESIGN.md                 # 詳細設計書
```

## クイックスタート

### 前提条件

- Docker 20.10+
- Docker Compose 2.0+
- Make（オプション、推奨）

### 初期セットアップ（推奨）

Makefileを使った自動セットアップ：

```bash
# リポジトリのクローン
git clone https://github.com/hawkie275/LuaAIDiary.git
cd LuaAIDiary

# 初期セットアップ（.env作成、ビルド、起動）
make setup
```

これで以下が自動的に実行されます：
1. `.env`ファイルの作成
2. Dockerイメージのビルド
3. サービスの起動
4. データベースの初期化

### 手動セットアップ

Makefileを使わない場合：

```bash
# 1. .envファイルの作成
cp .env.example .env

# 2. Dockerイメージのビルドとサービス起動
docker compose up -d --build

# 3. データベースが起動するまで待機（約10秒）
sleep 10
```

### 動作確認

ブラウザで以下のURLにアクセスします：

```
http://localhost:8080
```

ヘルスチェック：
```bash
curl http://localhost:8080/health
# または
make health
```

## 開発コマンド（Makefile）

プロジェクトには便利なMakefileが用意されています：

```bash
# ヘルプを表示
make help

# 開発サーバー起動（フォアグラウンド）
make dev

# サービス起動（バックグラウンド）
make up

# サービス停止
make down

# サービス再起動
make restart

# ログ表示
make logs          # すべてのサービス
make logs-web      # Webサーバーのみ
make logs-db       # データベースのみ
make logs-redis    # Redisのみ

# シェルに接続
make shell         # Webコンテナ
make shell-db      # DBコンテナ
make psql          # PostgreSQLクライアント
make redis-cli     # Redisクライアント

# テスト実行
make test          # すべてのテスト

# データベースリセット
make db-reset

# 静的解析
make lint

# ヘルスチェック
make health

# サービス状態確認
make status

# クリーンアップ（データ削除）
make clean
```

## 管理画面

### アクセス方法

管理画面には以下のURLでアクセスできます：

```
http://localhost:8080/admin
```

または

```
http://localhost:8080/admin/dashboard
```

### デフォルトログイン情報

初期セットアップ後、以下の管理者アカウントでログインできます：

- **ユーザー名**: `admin`
- **パスワード**: データベース初期化スクリプトで設定されたパスワード
  - デフォルトは `postgresql/init/02_update_admin_password.sql` で確認できます
  - **セキュリティのため、初回ログイン後すぐにパスワードを変更してください**

### パスワード変更

1. 管理画面にログイン
2. 右上のユーザーメニューから「パスワード変更」を選択
3. 現在のパスワードと新しいパスワードを入力

または、以下のURLから直接アクセス：

```
http://localhost:8080/admin/change-password
```

### 管理画面の主要機能

#### ダッシュボード（`/admin/dashboard`）
- サイト統計情報の表示
  - 投稿数（全ステータス）
  - カテゴリー数
  - タグ数
  - コメント数
- 最近の投稿5件
- システム情報（Luaバージョン、サーバー時刻、DB接続状態）

#### 投稿管理（`/admin/posts`）
- 投稿一覧表示
- 新規投稿作成
- 投稿編集
- 投稿削除
- ステータス管理（draft/published/trash）
- Markdownプレビュー
- カテゴリー・タグの割り当て

#### カテゴリー管理（`/admin/categories`）
- カテゴリー一覧
- カテゴリー作成・編集・削除
- 階層構造の管理

#### タグ管理（`/admin/tags`）
- タグ一覧
- タグ作成・編集・削除

#### ユーザー管理（`/admin/users`）
- ユーザー一覧
- 新規ユーザー作成
- ユーザー情報編集
- ロール変更（admin/editor/author/contributor/subscriber）
- ユーザー削除

#### サイト設定（`/admin/settings`）
- サイト基本情報
- AI設定（Gemini API）
- テーマ設定

#### プロフィール管理（`/admin/profile`）
- 自分のプロフィール表示・編集
- パスワード変更

## Gemini AI 機能

LuaAIDiary は Google Gemini API と統合されており、AI を活用した記事作成支援機能を提供します。

### 主な機能

#### 1. AI記事自動生成

トピックやキーワードから、完全な記事を自動生成します。

**機能**:
- タイトルと本文の自動生成
- 見出し構成の提案
- SEOに配慮した文章
- カスタマイズ可能な文字数・トーン

**使い方**:
1. 管理画面の投稿編集画面で「AI生成」ボタンをクリック
2. トピックとキーワードを入力
3. オプションで対象読者・文字数・トーンを指定
4. 生成された記事を確認・編集

**APIエンドポイント**:
```bash
POST /api/gemini/generate-article
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN

{
  "topic": "LuaJITの性能について",
  "keywords": "Lua, JIT, パフォーマンス",
  "target_audience": "開発者",
  "word_count": 2000,
  "tone": "technical"
}
```

#### 2. AI校正機能

既存の記事を分析し、文法・表現・構成の改善提案を行います。

**機能**:
- 文法チェック
- 表現の改善提案
- 読みやすさの向上
- トーンの調整

**使い方**:
1. 投稿編集画面で本文を入力
2. 「AI校正」ボタンをクリック
3. 改善提案を確認
4. 必要な修正を適用

**APIエンドポイント**:
```bash
POST /api/gemini/proofread
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN

{
  "content": "校正したい記事本文...",
  "tone": "formal"
}
```

### Gemini APIキーの設定

AI機能を使用するには、各ユーザーが個別にGemini APIキーを設定する必要があります。

#### 1. APIキーの取得

1. [Google AI Studio](https://makersuite.google.com/app/apikey) にアクセス
2. Googleアカウントでログイン
3. 「APIキーを作成」をクリック
4. 生成されたAPIキーをコピー

#### 2. APIキーの設定

管理画面から設定：

1. `/admin/settings` にアクセス
2. 「AI設定」タブを選択
3. Gemini APIキーを入力
4. 「保存」をクリック

APIから設定：

```bash
POST /api/settings/gemini-api-key
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN

{
  "api_key": "YOUR_GEMINI_API_KEY"
}
```

#### 3. セキュリティ

- APIキーはAES-256-CBCで暗号化されてデータベースに保存されます
- 各ユーザーが個別のAPIキーを管理
- マスター暗号化キーは環境変数（`ENCRYPTION_KEY`）で管理
- APIキーは本人のみが参照・更新可能

### AI設定のカスタマイズ

プロンプトテンプレートをカスタマイズすることで、生成される記事の品質やスタイルを調整できます。

**設定項目**:
- **モデル選択**: `gemini-2.5-flash`, `gemini-1.5-pro` など
- **記事生成プロンプト**: 記事生成時のプロンプトテンプレート
- **校正プロンプト**: 校正時のプロンプトテンプレート
- **デフォルト対象読者**: 記事の対象読者
- **デフォルトトーン**: formal, casual, technical など

### API接続テスト

APIキーが正しく設定されているかテストできます：

```bash
POST /api/gemini/test-connection
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN
```

成功時のレスポンス：
```json
{
  "success": true,
  "data": {
    "success": true,
    "message": "API接続に成功しました",
    "response": "接続成功"
  }
}
```

## 利用可能なエンドポイント

### 公開エンドポイント

| エンドポイント | 説明 | レスポンス |
|--------------|------|-----------|
| `GET /` | ホームページ（投稿一覧） | HTML |
| `GET /:slug` | 単一投稿 | HTML |
| `GET /category/:slug` | カテゴリーアーカイブ | HTML |
| `GET /tag/:slug` | タグアーカイブ | HTML |
| `GET /author/:username` | 著者アーカイブ | HTML |
| `GET /search` | 検索結果 | HTML |
| `GET /health` | ヘルスチェック | JSON |
| `GET /api/db-test` | PostgreSQL接続テスト | JSON |
| `GET /api/redis-test` | Redis接続テスト | JSON |

### 認証APIエンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
|--------------|---------|------|-----|
| `/api/auth/register` | POST | ユーザー登録 | 不要 |
| `/api/auth/login` | POST | ログイン | 不要 |
| `/api/auth/logout` | POST | ログアウト | 必要 |
| `/api/auth/me` | GET | 現在のユーザー情報取得 | 必要 |
| `/api/auth/change-password` | POST | パスワード変更 | 必要 |
| `/api/auth/check` | GET | 認証状態チェック | 任意 |

### 投稿APIエンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
|--------------|---------|------|-----|
| `/api/posts` | GET | 投稿一覧取得 | 任意 |
| `/api/posts` | POST | 投稿作成 | 必要（author以上） |
| `/api/posts/:id` | GET | 投稿詳細取得 | 任意 |
| `/api/posts/:id` | PUT | 投稿更新 | 必要（作成者） |
| `/api/posts/:id` | DELETE | 投稿削除 | 必要（作成者） |

### カテゴリーAPIエンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
|--------------|---------|------|-----|
| `/api/categories` | GET | カテゴリー一覧取得 | 不要 |
| `/api/categories` | POST | カテゴリー作成 | 必要（editor以上） |
| `/api/categories/:id` | GET | カテゴリー詳細取得 | 不要 |
| `/api/categories/:id` | PUT | カテゴリー更新 | 必要（editor以上） |
| `/api/categories/:id` | DELETE | カテゴリー削除 | 必要（editor以上） |

### タグAPIエンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
|--------------|---------|------|-----|
| `/api/tags` | GET | タグ一覧取得 | 不要 |
| `/api/tags` | POST | タグ作成 | 必要（author以上） |
| `/api/tags/:id` | GET | タグ詳細取得 | 不要 |
| `/api/tags/:id` | PUT | タグ更新 | 必要（editor以上） |
| `/api/tags/:id` | DELETE | タグ削除 | 必要（editor以上） |

### 管理画面エンドポイント

| エンドポイント | 説明 | 権限 |
|--------------|------|-----|
| `GET /admin` | 管理画面トップ（ダッシュボードへリダイレクト） | editor以上 |
| `GET /admin/dashboard` | ダッシュボード | editor以上 |
| `GET /admin/posts` | 投稿一覧 | editor以上 |
| `GET /admin/posts/new` | 新規投稿フォーム | author以上 |
| `GET /admin/posts/:id/edit` | 投稿編集フォーム | 作成者 |
| `GET /admin/categories` | カテゴリー管理 | editor以上 |
| `GET /admin/tags` | タグ管理 | editor以上 |
| `GET /admin/users` | ユーザー管理 | admin |
| `GET /admin/settings` | サイト設定 | admin |
| `GET /admin/profile` | プロフィール表示 | 全ユーザー |
| `GET /admin/login` | ログインフォーム | 不要 |
| `GET /admin/change-password` | パスワード変更フォーム | 必要 |

### Gemini AI APIエンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
|--------------|---------|------|-----|
| `/api/gemini/generate-article` | POST | AI記事生成 | 必要 |
| `/api/gemini/proofread` | POST | AI校正 | 必要 |
| `/api/gemini/test-connection` | POST | API接続テスト | 必要 |

### AI設定APIエンドポイント

| エンドポイント | メソッド | 説明 | 認証 |
|--------------|---------|------|-----|
| `/api/settings/ai-preferences` | GET | AI設定取得 | 必要 |
| `/api/settings/ai-preferences` | PUT | AI設定更新 | 必要 |
| `/api/settings/gemini-api-key` | POST | APIキー保存 | 必要 |
| `/api/settings/gemini-api-key` | DELETE | APIキー削除 | 必要 |

### その他のエンドポイント

| エンドポイント | メソッド | 説明 |
|--------------|---------|------|
| `/api/csrf-token` | GET | CSRFトークン取得 |
| `/api/preview/markdown` | POST | Markdownプレビュー |

### 例：ヘルスチェック

```bash
curl http://localhost:8080/health
```

レスポンス例：
```json
{
  "status": "ok",
  "service": "LuaAIDiary",
  "timestamp": 1703500000,
  "version": "0.1.0"
}
```

### 例：データベース接続テスト

```bash
curl http://localhost:8080/api/db-test
```

レスポンス例：
```json
{
  "status": "success",
  "message": "データベース接続成功",
  "postgres_version": "PostgreSQL 15.x",
  "host": "db",
  "database": "LuaAIDiary"
}
```

## テストの実行

### すべてのテストを実行

```bash
make test
```

または

```bash
docker compose exec web busted tests/
```

### 特定のテストファイルを実行

```bash
make test-file FILE=tests/test_database.lua
```

### テストの内容

- **test_database.lua**: データベース接続とスキーマのテスト
- **test_health.lua**: ヘルスチェックエンドポイントのテスト

## データベーススキーマ

以下のテーブルが自動的に作成されます：

- **users** - ユーザー情報（認証、権限管理）
- **posts** - 投稿（記事本文、ステータス）
- **comments** - コメント（スレッド対応）
- **categories** - カテゴリー（階層構造対応）
- **tags** - タグ
- **post_categories** - 投稿とカテゴリーの多対多関連
- **post_tags** - 投稿とタグの多対多関連
- **user_settings** - ユーザー設定（Gemini APIキーなど）
- **post_meta** - 投稿メタデータ（カスタムフィールド）

詳細なスキーマ定義は [`postgresql/init/01_create_tables.sql`](postgresql/init/01_create_tables.sql) を参照してください。

## 開発ワークフロー

### ホットリロード

`app/`ディレクトリのファイルはホストマシンとコンテナ間でマウントされているため、編集すると即座に反映されます。

### コードの静的解析

```bash
make lint
```

Luacheckを使ってコードの品質をチェックします。設定は`.luacheckrc`で管理されています。

### データベースのリセット

開発中にデータベースをクリーンな状態に戻す：

```bash
make db-reset
```

### ログの監視

開発中はログを監視しながら作業するのが便利です：

```bash
make logs-web
```

## トラブルシューティング

### サービスが起動しない

```bash
# サービスの状態を確認
make status

# ログを確認
make logs

# 完全にクリーンアップして再セットアップ
make clean
make setup
```

### ポートが既に使用されている

ポート8080、5432、6379が既に使用されている場合は、`docker-compose.yml`のポート設定を変更してください。

### データベース接続エラー

```bash
# データベースコンテナの状態確認
docker compose ps db

# データベースのログ確認
make logs-db

# データベースリセット
make db-reset
```

### テストが失敗する

```bash
# サービスが正常に起動しているか確認
make health

# データベース接続テスト
curl http://localhost:8080/api/db-test

# Redis接続テスト
curl http://localhost:8080/api/redis-test
```

### コンテナのビルドエラー

```bash
# キャッシュなしで再ビルド
make build
```

## セキュリティ

### 本番環境での重要な設定

**⚠️ 本番環境では必ず以下の設定を変更してください：**

1. **データベースパスワードの変更**
   ```bash
   # .envファイルで強力なパスワードに変更
   POSTGRES_PASSWORD=強力なランダムパスワード
   ```

2. **暗号化キーの生成**
   ```bash
   # 安全な32バイトキーを生成
   openssl rand -hex 32
   
   # .envファイルに設定
   ENCRYPTION_KEY=生成されたキー
   ```

3. **管理者パスワードの変更**
   - 初回ログイン後すぐに変更
   - `/admin/change-password` から変更可能

4. **環境変数の管理**
   - `.env`ファイルは**絶対にGitにコミットしない**
   - `.gitignore`に`.env`が含まれていることを確認
   - 本番環境では環境変数を安全に管理（AWS Secrets Manager、Hashicorp Vaultなど）

5. **HTTPS の使用**
   - 本番環境では必ずHTTPS/TLS を設定
   - Let's Encryptなどで無料のSSL証明書を取得可能

### 実装済みセキュリティ機能

#### パスワードセキュリティ
- **bcrypt**: 12ラウンドのハッシュ化
- **ソルト**: 自動生成
- **最小長**: 8文字

#### セッション管理
- **ストレージ**: Redis（インメモリ）
- **有効期限**: 7日間
- **Cookie設定**:
  - `HttpOnly`: JavaScriptからアクセス不可
  - `SameSite=Lax`: CSRF攻撃を軽減
  - `Secure`: 本番環境ではHTTPSのみ（要設定）

#### CSRF保護
- 全ての変更操作でCSRFトークン検証
- トークンは32バイトのランダム文字列
- セッションごとに生成

#### APIキー暗号化
- **暗号化方式**: AES-256-CBC
- **マスターキー**: 環境変数で管理
- **アクセス制御**: 本人のみ参照可能

#### ロールベースアクセス制御（RBAC）
- **admin**: 全ての操作が可能
- **editor**: コンテンツ管理と公開
- **author**: 自分の記事管理
- **contributor**: 記事下書き作成
- **subscriber**: 閲覧のみ

#### 入力検証
- 全ての入力データをサーバー側で検証
- SQLインジェクション対策（パラメータ化クエリ）
- XSS対策（出力エスケープ）

## 環境変数

`.env`ファイルで設定可能な環境変数：

```bash
# PostgreSQL設定
POSTGRES_PASSWORD=change_this_secure_password
POSTGRES_DB=luaaidiary
POSTGRES_USER=luaaidiary

# Redis設定
REDIS_HOST=redis
REDIS_PORT=6379

# Lapis設定
LAPIS_ENVIRONMENT=development

# 暗号化設定（必ず変更！）
ENCRYPTION_KEY=change_this_to_a_secure_32_byte_key_in_production

# Gemini API設定（オプション）
GEMINI_API_KEY=your_gemini_api_key_here
```

詳細は[`.env.example`](.env.example)を参照してください。

## プロジェクト構造の詳細

### `/app` - アプリケーションコード

- **init.lua**: Lapisアプリケーションのメインエントリーポイント
- **config/**: データベース接続などの設定
- **controllers/**: リクエストハンドラー
- **models/**: データモデル
- **middleware/**: 認証、CSRF対策などのミドルウェア
- **utils/**: ヘルパー関数、バリデーションなど

### `/tests` - テストコード

- **test_helper.lua**: テスト用ヘルパー関数
- **test_database.lua**: データベース接続とスキーマのテスト
- **test_health.lua**: エンドポイントのテスト

### `/docker` - Docker関連

- **web/Dockerfile**: OpenResty + Lapis + 各種Luaライブラリ
- **web/nginx.conf**: Nginx設定（Lapis対応）

## 今後の実装予定

### Phase 1: コアシステム ✅ 完了
- ✅ ユーザー認証・認可システム（bcrypt）
- ✅ 投稿CRUD機能
- ✅ セッション管理（Redis）
- ✅ CSRF対策

### Phase 2: テーマ互換レイヤー ✅ 完了
- ✅ WordPressテーマローダー
- ✅ WordPress関数エミュレーション
- ✅ テンプレートエンジン統合

### Phase 3: Gemini連携 ✅ 完了
- ✅ Gemini API統合
- ✅ 記事構成提案機能
- ✅ APIキー暗号化管理
- ✅ AI校正機能

### Phase 4: 管理画面 ✅ 完了
- ✅ ダッシュボード
- ✅ 投稿管理画面
- ✅ カテゴリー・タグ管理
- ✅ ユーザー管理
- ✅ サイト設定

### Phase 5: 今後の拡張（検討中）

#### コンテンツ機能
- [ ] リッチテキストエディタ（WYSIWYG）
- [ ] メディアアップロード・管理
- [ ] 画像最適化
- [ ] 投稿のバージョン管理
- [ ] 投稿の複製機能
- [ ] 一括操作（複数投稿の削除など）

#### AI機能の拡張
- [ ] 記事のSEO分析
- [ ] 自動タグ付け
- [ ] 関連記事の提案
- [ ] 画像生成（Imagen統合）
- [ ] 多言語翻訳

#### ユーザー機能
- [ ] 二要素認証（2FA）
- [ ] パスワードリセット（メール経由）
- [ ] OAuth連携（Google/GitHub等）
- [ ] ログイン履歴
- [ ] セッション管理画面

#### パフォーマンス
- [ ] ページキャッシュ機構
- [ ] CDN統合
- [ ] 画像遅延読み込み
- [ ] HTTP/2 Server Push

#### プラグインシステム
- [ ] プラグインアーキテクチャ
- [ ] フック/フィルターシステム
- [ ] プラグインマーケットプレイス

#### 監視・分析
- [ ] アクセス解析
- [ ] エラー追跡（Sentry統合）
- [ ] パフォーマンス監視（Prometheus + Grafana）

詳細な実装計画は [DESIGN.md](DESIGN.md) を参照してください。

## ライセンス

このプロジェクトは[MIT License](LICENSE)の下で公開されています。

### MIT Licenseを選んだ理由

1. **自由度が高い** - 商用利用、改変、再配布が自由
2. **シンプル** - 短く理解しやすいライセンス文
3. **広く採用** - オープンソースコミュニティで最も人気
4. **互換性** - 他のライブラリとの組み合わせが容易

MITライセンスにより、このソフトウェアを自由に使用、コピー、変更、マージ、公開、配布、サブライセンス、および販売することができます。

## 参考資料

- [OpenResty公式ドキュメント](https://openresty.org/)
- [Lapis公式ドキュメント](https://leafo.net/lapis/)
- [Lua公式サイト](https://www.lua.org/)
- [PostgreSQL公式ドキュメント](https://www.postgresql.org/docs/15/)
- [Redis公式ドキュメント](https://redis.io/documentation)
- [Busted公式ドキュメント](https://lunarmodules.github.io/busted/)
- [Docker公式ドキュメント](https://docs.docker.com/)

## ドキュメント

### アーキテクチャ・設計
- [ARCHITECTURE.md](ARCHITECTURE.md) - システムアーキテクチャ
- [DESIGN.md](DESIGN.md) - 詳細設計書

### 機能別ドキュメント
- [README_ADMIN.md](README_ADMIN.md) - 管理画面機能
- [README_AUTH.md](README_AUTH.md) - 認証システム
- [README_POST_API.md](README_POST_API.md) - 投稿API仕様
- [README_THEME_ENGINE.md](README_THEME_ENGINE.md) - テーマエンジン

### テスト関連
- [tests/README.md](tests/README.md) - テスト実行方法
- [tests/e2e/README.md](tests/e2e/README.md) - E2Eテスト
- [tests/integration/README.md](tests/integration/README.md) - 統合テスト

## コントリビューション

プルリクエストを歓迎します。大きな変更の場合は、まずissueを開いて変更内容を議論してください。
