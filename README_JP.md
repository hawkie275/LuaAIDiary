# LuaAIDiary

LuaベースのWordPressライクなブログシステム

## 概要

LuaAIDiaryは、OpenResty（Nginx + LuaJIT）、Lapis、MySQL、Redisを使用した高性能なブログシステムです。Docker Composeを使用して簡単にセットアップでき、テスト実行しながら開発できる環境を提供します。

## 主な特徴

- **高性能**: OpenResty + Lapisによる非同期I/O処理
- **軽量**: LuaJITによる高速なスクリプト実行
- **テスト環境**: Bustedによる自動テスト対応
- **開発ツール**: Makefile、Luacheckによる開発効率化
- **スケーラブル**: Redis、MySQLによる水平スケーリング対応
- **ホットリロード**: コード変更時の自動反映

## 技術スタック

- **Webフレームワーク**: Lapis (OpenResty/Nginx + LuaJIT)
- **データベース**: MySQL 8.0
- **キャッシュ/セッション**: Redis 7
- **テストフレームワーク**: Busted
- **静的解析**: Luacheck
- **コンテナ化**: Docker & Docker Compose
- **言語**: Lua

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
├── mysql/                     # MySQL関連
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
git clone <repository-url>
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
make mysql         # MySQLクライアント
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

## 利用可能なエンドポイント

| エンドポイント | 説明 | レスポンス |
|--------------|------|-----------|
| `GET /` | ホームページ | HTML |
| `GET /health` | ヘルスチェック | JSON |
| `GET /api/db-test` | MySQL接続テスト | JSON |
| `GET /api/redis-test` | Redis接続テスト | JSON |

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
  "mysql_version": "8.0.35",
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

詳細なスキーマ定義は [`mysql/init/01_create_tables.sql`](mysql/init/01_create_tables.sql) を参照してください。

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

ポート8080、3306、6379が既に使用されている場合は、`docker-compose.yml`のポート設定を変更してください。

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
   MYSQL_ROOT_PASSWORD=強力なランダムパスワード
   MYSQL_PASSWORD=強力なランダムパスワード
   ```

2. **暗号化キーの生成**
   ```bash
   # 安全な32バイトキーを生成
   openssl rand -hex 32
   
   # .envファイルに設定
   ENCRYPTION_KEY=生成されたキー
   ```

3. **環境変数の管理**
   - `.env`ファイルは**絶対にGitにコミットしない**
   - `.gitignore`に`.env`が含まれていることを確認
   - 本番環境では環境変数を安全に管理（AWS Secrets Manager、Hashicorp Vaultなど）

4. **HTTPS の使用**
   - 本番環境では必ずHTTPS/TLS を設定
   - Let's Encryptなどで無料のSSL証明書を取得可能

### 開発環境のセキュリティ

開発環境でも以下に注意してください：

- デフォルトの`.env.example`の値は開発専用
- 個人情報や実際のAPIキーは使用しない
- データベースポート（3306）を外部に公開しない

## 環境変数

`.env`ファイルで設定可能な環境変数：

```bash
# MySQL設定
MYSQL_ROOT_PASSWORD=change_this_secure_root_password
MYSQL_DATABASE=luaaidiary
MYSQL_USER=luaaidiary
MYSQL_PASSWORD=change_this_secure_password

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

### Phase 1: コアシステム
- [ ] ユーザー認証・認可システム（bcrypt）
- [ ] 投稿CRUD機能
- [ ] セッション管理（Redis）
- [ ] CSRF対策

### Phase 2: テーマ互換レイヤー
- [ ] WordPressテーマローダー
- [ ] WordPress関数エミュレーション
- [ ] テンプレートエンジン統合

### Phase 3: Gemini連携
- [ ] Gemini API統合
- [ ] 記事構成提案機能
- [ ] APIキー暗号化管理

### Phase 4: 管理画面
- [ ] ダッシュボード
- [ ] リッチテキストエディタ
- [ ] メディアアップロード

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
- [MySQL公式ドキュメント](https://dev.mysql.com/doc/)
- [Redis公式ドキュメント](https://redis.io/documentation)
- [Busted公式ドキュメント](https://lunarmodules.github.io/busted/)
- [Docker公式ドキュメント](https://docs.docker.com/)

## ドキュメント

- [ARCHITECTURE.md](ARCHITECTURE.md) - システムアーキテクチャ
- [DESIGN.md](DESIGN.md) - 詳細設計書

## コントリビューション

プルリクエストを歓迎します。大きな変更の場合は、まずissueを開いて変更内容を議論してください。
