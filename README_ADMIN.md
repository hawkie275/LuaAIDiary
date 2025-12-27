# 管理画面ダッシュボード - 実装ドキュメント

## 概要

管理画面のダッシュボード機能を実装しました。このドキュメントでは、実装内容と動作確認方法を説明します。

## 実装内容

### 1. 作成・修正したファイル

#### 作成したファイル
- **`app/controllers/admin_controller.lua`** - 管理画面コントローラー
  - ダッシュボード表示機能
  - 統計情報取得機能
  - 認証・権限チェック機能
  - システム情報取得機能

#### 修正したファイル
- **`app/init.lua`** - ルーティング設定に管理画面エンドポイントを追加
  - `GET /admin` - `/admin/dashboard` へのリダイレクト
  - `GET /admin/dashboard` - ダッシュボード表示

### 2. 実装した機能

#### ダッシュボード機能
- **統計情報の表示**
  - 投稿数（全ステータス）
  - カテゴリー数
  - タグ数
  - コメント数

- **最近の投稿5件の表示**
  - 投稿ID
  - タイトル
  - ステータス（draft/published/trash）
  - カテゴリー名
  - 作成日時

- **システム情報の表示**
  - Luaバージョン
  - サーバー時刻
  - データベース接続状態

#### セキュリティ機能
- **認証チェック**
  - 未認証ユーザーはログインページにリダイレクト
  
- **権限チェック**
  - admin または editor ロールのみアクセス可能
  - 権限不足の場合は403エラー

- **CSRFトークン**
  - ダッシュボードページにCSRFトークンを生成・提供
  - フォーム送信時のCSRF攻撃を防止

## 動作確認方法

### 前提条件

1. アプリケーションが起動していること
2. データベースが正常に接続されていること
3. テストユーザーが登録されていること

### 手順

#### ステップ1: ログイン

admin または editor ロールを持つユーザーでログインします。

```bash
# ログイン（adminユーザーの例）
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "your_password"
  }' \
  -c cookies.txt

# レスポンス例
# {
#   "success": true,
#   "data": {
#     "user": {
#       "id": 1,
#       "username": "admin",
#       "email": "admin@example.com",
#       "role": "admin"
#     }
#   },
#   "message": "Login successful"
# }
```

#### ステップ2: 管理画面ダッシュボードにアクセス

ログイン後、クッキーを使用してダッシュボードにアクセスします。

```bash
# ダッシュボードにアクセス
curl -X GET http://localhost:8080/admin/dashboard \
  -b cookies.txt

# または /admin にアクセス（自動的に /admin/dashboard にリダイレクト）
curl -L -X GET http://localhost:8080/admin \
  -b cookies.txt
```

**期待される結果:**
- HTMLページが返される（管理画面レイアウトとダッシュボード）
- 統計情報、最近の投稿、システム情報が表示される

#### ステップ3: ブラウザでの確認

より詳細な確認はブラウザで行うことを推奨します。

1. ブラウザで `http://localhost:8080/api/auth/login` にアクセスしてログイン
2. `http://localhost:8080/admin` または `http://localhost:8080/admin/dashboard` にアクセス
3. 以下の項目が表示されることを確認：
   - ページタイトル「ダッシュボード」
   - 統計情報カード（投稿数、カテゴリー数、タグ数、コメント数）
   - 最近の投稿リスト（5件）
   - システム情報（Luaバージョン、サーバー時刻、DB接続状態）

### エラーケースの確認

#### 未認証ユーザーのアクセス

```bash
# クッキーなしでアクセス
curl -X GET http://localhost:8080/admin/dashboard

# 期待される結果: ログインページへのリダイレクト（302）
```

#### 権限不足ユーザーのアクセス

```bash
# subscriber ロールのユーザーでログイン
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "subscriber_user",
    "password": "password"
  }' \
  -c cookies_subscriber.txt

# ダッシュボードにアクセス
curl -X GET http://localhost:8080/admin/dashboard \
  -b cookies_subscriber.txt

# 期待される結果: 403 Forbidden エラー
```

## テストデータの準備

動作確認のため、以下のテストデータを準備することを推奨します：

```bash
# 1. 投稿を作成（ログイン済みのadminユーザーで）
curl -X POST http://localhost:8080/api/posts \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: YOUR_CSRF_TOKEN" \
  -b cookies.txt \
  -d '{
    "title": "テスト投稿1",
    "content": "これはテスト投稿です。",
    "status": "published"
  }'

# 2. カテゴリーを作成
curl -X POST http://localhost:8080/api/categories \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: YOUR_CSRF_TOKEN" \
  -b cookies.txt \
  -d '{
    "name": "技術",
    "description": "技術関連の記事"
  }'

# 3. タグを作成
curl -X POST http://localhost:8080/api/tags \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: YOUR_CSRF_TOKEN" \
  -b cookies.txt \
  -d '{
    "name": "Lua"
  }'
```

## トラブルシューティング

### データベース接続エラー

**症状:** システム情報のデータベース接続状態が "disconnected"

**対処法:**
1. データベースが起動しているか確認
2. `.env` ファイルのデータベース設定を確認
3. `docker-compose.yml` でPostgreSQLコンテナが起動しているか確認

```bash
docker-compose ps
```

### 統計情報が0になる

**症状:** すべての統計情報が0と表示される

**対処法:**
1. データベースにデータが存在するか確認
2. テーブルが正しく作成されているか確認

```bash
# PostgreSQLコンテナに接続
docker-compose exec postgres psql -U luaaidiary -d luaaidiary

# テーブルを確認
\dt

# 投稿数を確認
SELECT COUNT(*) FROM posts;
SELECT COUNT(*) FROM categories;
SELECT COUNT(*) FROM tags;
SELECT COUNT(*) FROM comments;
```

### CSRFトークンエラー

**症状:** フォーム送信時にCSRFエラーが発生

**対処法:**
1. セッションが正しく開始されているか確認
2. Redisが起動しているか確認
3. ブラウザのクッキーが有効になっているか確認

## アーキテクチャ

### データフロー

```
ブラウザ
  ↓
ルーティング (/admin/dashboard)
  ↓
AdminController.dashboard()
  ↓
├─ 認証チェック (Session)
├─ 権限チェック (admin/editor)
├─ 統計情報取得 (Post/Category/Tag/Comment モデル)
├─ 最近の投稿取得 (SQL JOIN)
├─ システム情報取得 (Lua/DB)
└─ CSRFトークン生成
  ↓
ビューレンダリング (admin.dashboard)
  ↓
レイアウト適用 (admin.layout)
  ↓
HTML レスポンス
```

### 使用モデル

- **Post** - 投稿数の取得
- **Category** - カテゴリー数の取得
- **Tag** - タグ数の取得
- **Comment** - コメント数の取得
- **Session** - セッション管理・認証
- **CSRF** - CSRFトークン生成

## 次のステップへの推奨事項

1. **投稿管理画面の実装**
   - 投稿一覧表示
   - 投稿編集フォーム
   - 投稿削除機能

2. **カテゴリー・タグ管理画面の実装**
   - 一覧表示
   - 作成・編集・削除機能

3. **コメント管理画面の実装**
   - コメント一覧
   - 承認・拒否機能
   - スパムフィルター

4. **ユーザー管理画面の実装**
   - ユーザー一覧
   - ロール変更機能
   - ユーザー作成・編集

5. **設定画面の実装**
   - サイト設定
   - パーマリンク設定
   - テーマ設定

6. **ダッシュボードの機能拡張**
   - グラフ・チャートの追加
   - アクティビティログ
   - クイックアクション（投稿作成など）
   - システムアラート表示

## 関連ドキュメント

- [認証API仕様](README_AUTH.md)
- [投稿API仕様](README_POST_API.md)
- [テーマエンジン](README_THEME_ENGINE.md)
- [アーキテクチャ](ARCHITECTURE.md)
