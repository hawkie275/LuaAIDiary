# 投稿API仕様書

## 概要
LuaAIDiaryプロジェクトの投稿CRUD APIの完全なドキュメントです。Week 4-5で実装された編集・削除機能を含みます。

## セキュリティ機能

### 認証
すべての投稿作成・更新・削除操作には認証が必要です。
- セッションベースの認証を使用
- 認証されていないユーザーは401エラーを受け取ります

### 権限チェック
- **投稿編集**: 投稿の作成者のみが編集可能
- **投稿削除**: 投稿の作成者のみが削除可能
- 権限がない場合は403エラーを返します

### CSRF保護
POST、PUT、DELETEリクエストにはCSRFトークンが必要です。

#### CSRFトークンの取得
```bash
GET /api/csrf-token
```

**レスポンス例:**
```json
{
  "csrf_token": "a1b2c3d4e5f6..."
}
```

#### CSRFトークンの使用方法

**方法1: HTTPヘッダー（推奨）**
```bash
curl -X POST /api/posts \
  -H "X-CSRF-Token: YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"title":"新しい投稿","content":"本文"}'
```

**方法2: リクエストボディ**
```bash
curl -X POST /api/posts \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"_csrf_token":"YOUR_TOKEN_HERE","title":"新しい投稿","content":"本文"}'
```

## エンドポイント一覧

### 1. 投稿一覧取得
```
GET /api/posts
```

**認証**: 任意（認証済みの場合はすべてのステータスの投稿を取得可能）

**クエリパラメータ:**
- `limit` (number, optional): 取得件数（デフォルト: 10）
- `offset` (number, optional): オフセット（デフォルト: 0）
- `status` (string, optional): ステータスフィルター（draft/published/trash）

**レスポンス例:**
```json
{
  "success": true,
  "posts": [
    {
      "id": 1,
      "title": "投稿タイトル",
      "slug": "post-title",
      "content": "本文内容",
      "excerpt": "抜粋",
      "author_id": 1,
      "user_id": 1,
      "status": "published",
      "published_at": "2024-01-01 12:00:00",
      "created_at": "2024-01-01 12:00:00",
      "updated_at": "2024-01-01 12:00:00",
      "categories": [],
      "tags": []
    }
  ],
  "pagination": {
    "limit": 10,
    "offset": 0,
    "total": 1
  }
}
```

### 2. 投稿詳細取得
```
GET /api/posts/:id
```

**認証**: 任意（公開投稿は認証不要、下書きは作成者のみ）

**パスパラメータ:**
- `id` (number, required): 投稿ID

**レスポンス例:**
```json
{
  "success": true,
  "post": {
    "id": 1,
    "title": "投稿タイトル",
    "slug": "post-title",
    "content": "本文内容",
    "excerpt": "抜粋",
    "author_id": 1,
    "user_id": 1,
    "status": "published",
    "published_at": "2024-01-01 12:00:00",
    "created_at": "2024-01-01 12:00:00",
    "updated_at": "2024-01-01 12:00:00",
    "categories": [],
    "tags": []
  }
}
```

**エラーレスポンス:**
- `400`: 無効な投稿ID
- `403`: アクセス権限なし（下書き投稿で作成者以外）
- `404`: 投稿が見つかりません

### 3. 投稿作成
```
POST /api/posts
```

**認証**: 必須  
**CSRF保護**: 必須

**リクエストボディ:**
```json
{
  "title": "投稿タイトル",
  "content": "本文内容",
  "excerpt": "抜粋（オプション）",
  "status": "draft",
  "slug": "custom-slug（オプション）",
  "category_ids": [1, 2],
  "tag_ids": [3, 4]
}
```

**フィールド詳細:**
- `title` (string, required): 1-255文字
- `content` (string, required): 本文
- `excerpt` (string, optional): 0-500文字
- `status` (enum, optional): draft/published/trash（デフォルト: draft）
- `slug` (string, optional): URL用スラッグ（未指定時は自動生成）
- `category_ids` (array, optional): カテゴリーIDの配列
- `tag_ids` (array, optional): タグIDの配列

**レスポンス例:**
```json
{
  "success": true,
  "post": {
    "id": 2,
    "title": "投稿タイトル",
    "slug": "post-title",
    "content": "本文内容",
    "excerpt": "抜粋",
    "author_id": 1,
    "user_id": 1,
    "status": "draft",
    "created_at": "2024-01-01 13:00:00",
    "updated_at": "2024-01-01 13:00:00",
    "categories": [],
    "tags": []
  }
}
```

**エラーレスポンス:**
- `400`: バリデーションエラー
- `401`: 認証が必要です
- `403`: CSRF検証エラー
- `500`: 投稿の作成に失敗しました

### 4. 投稿更新
```
PUT /api/posts/:id
```

**認証**: 必須（投稿の作成者のみ）  
**CSRF保護**: 必須

**パスパラメータ:**
- `id` (number, required): 投稿ID

**リクエストボディ:**
```json
{
  "title": "更新されたタイトル",
  "content": "更新された本文",
  "excerpt": "更新された抜粋",
  "status": "published",
  "slug": "updated-slug",
  "category_ids": [1, 3],
  "tag_ids": [2, 5]
}
```

**注意:**
- すべてのフィールドはオプションです
- 指定されたフィールドのみが更新されます
- `status`をdraftからpublishedに変更すると、公開日時が自動設定されます

**レスポンス例:**
```json
{
  "success": true,
  "post": {
    "id": 2,
    "title": "更新されたタイトル",
    "slug": "updated-slug",
    "content": "更新された本文",
    "excerpt": "更新された抜粋",
    "author_id": 1,
    "user_id": 1,
    "status": "published",
    "published_at": "2024-01-01 14:00:00",
    "created_at": "2024-01-01 13:00:00",
    "updated_at": "2024-01-01 14:00:00",
    "categories": [
      {"id": 1, "name": "カテゴリー1", "slug": "category-1"}
    ],
    "tags": [
      {"id": 2, "name": "タグ2", "slug": "tag-2"}
    ]
  }
}
```

**エラーレスポンス:**
- `400`: 無効な投稿IDまたはバリデーションエラー
- `401`: 認証が必要です
- `403`: CSRF検証エラーまたは権限なし
- `404`: 投稿が見つかりません
- `500`: 投稿の更新に失敗しました

### 5. 投稿削除
```
DELETE /api/posts/:id
```

**認証**: 必須（投稿の作成者のみ）  
**CSRF保護**: 必須

**パスパラメータ:**
- `id` (number, required): 投稿ID

**削除タイプ**: 物理削除（データベースから完全に削除）

**リクエスト例:**
```bash
curl -X DELETE /api/posts/2 \
  -H "X-CSRF-Token: YOUR_TOKEN" \
  -b cookies.txt
```

**レスポンス例:**
```json
{
  "success": true,
  "message": "投稿を削除しました"
}
```

**エラーレスポンス:**
- `400`: 無効な投稿ID
- `401`: 認証が必要です
- `403`: CSRF検証エラーまたは権限なし
- `404`: 投稿が見つかりません
- `500`: 投稿の削除に失敗しました

## 使用例

### 完全なワークフロー

#### 1. ログイン
```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -c cookies.txt \
  -d '{"username":"admin","password":"your_password"}'
```

#### 2. CSRFトークン取得
```bash
curl -X GET http://localhost:8080/api/csrf-token \
  -b cookies.txt
```

#### 3. 投稿作成
```bash
curl -X POST http://localhost:8080/api/posts \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: YOUR_TOKEN" \
  -b cookies.txt \
  -d '{
    "title": "新しいブログ投稿",
    "content": "これは新しい投稿の本文です。",
    "status": "published"
  }'
```

#### 4. 投稿更新
```bash
curl -X PUT http://localhost:8080/api/posts/1 \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: YOUR_TOKEN" \
  -b cookies.txt \
  -d '{
    "title": "更新されたタイトル",
    "content": "更新された本文"
  }'
```

#### 5. 投稿削除
```bash
curl -X DELETE http://localhost:8080/api/posts/1 \
  -H "X-CSRF-Token: YOUR_TOKEN" \
  -b cookies.txt
```

## モデルメソッド

### Post.create_post(data)
投稿を作成します。

**パラメータ:**
- `data.title` (string, required)
- `data.content` (string, required)
- `data.author_id` (number, required)
- `data.excerpt` (string, optional)
- `data.status` (string, optional)
- `data.slug` (string, optional)
- `data.categories` (array, optional)
- `data.tags` (array, optional)

**戻り値:**
- 成功: `post_id`, `nil`
- 失敗: `nil`, `error_message`

### Post.update_post(id, data)
投稿を更新します。

**パラメータ:**
- `id` (number, required): 投稿ID
- `data` (table, required): 更新データ

**戻り値:**
- 成功: `true`, `nil`
- 失敗: `false`, `error_message`

### Post:delete(id)
投稿を削除します（物理削除）。

**パラメータ:**
- `id` (number, required): 投稿ID

**戻り値:**
- 成功: `true`, `nil`
- 失敗: `false`, `error_message`

## バリデーションルール

### タイトル
- 必須
- 1-255文字
- 空文字不可

### 本文
- 必須
- 空文字不可

### 抜粋
- オプション
- 0-500文字

### ステータス
- オプション
- 有効な値: `draft`, `published`, `trash`
- デフォルト: `draft`

### カテゴリーID
- オプション
- 配列形式
- 各IDは正の整数
- 存在するカテゴリーIDのみ有効

### タグID
- オプション
- 配列形式
- 各IDは正の整数
- 存在するタグIDのみ有効

## エラーハンドリング

すべてのエラーレスポンスは以下の形式で返されます:

```json
{
  "success": false,
  "error": "エラーメッセージ",
  "errors": {
    "field_name": "フィールド固有のエラー"
  }
}
```

### 一般的なHTTPステータスコード
- `200 OK`: 成功（GET、PUT、DELETE）
- `201 Created`: 投稿が作成されました（POST）
- `400 Bad Request`: バリデーションエラー
- `401 Unauthorized`: 認証が必要
- `403 Forbidden`: アクセス権限なし、またはCSRF検証失敗
- `404 Not Found`: リソースが見つかりません
- `500 Internal Server Error`: サーバーエラー

## テスト

E2Eテストスクリプトを実行:

```bash
# アプリケーションを起動
docker-compose up -d

# テストを実行
bash tests/e2e/test_post_api.sh
```

テストには以下が含まれます:
- 投稿の作成
- 投稿の一覧取得
- 投稿の詳細取得
- 投稿の更新（CSRFトークン付き）
- 投稿の削除（CSRFトークン付き）
- 認証なしでのアクセス制限確認
- CSRFトークン検証

## 実装ファイル

- **コントローラー**: [`app/controllers/post_controller.lua`](app/controllers/post_controller.lua)
- **モデル**: [`app/models/post.lua`](app/models/post.lua)
- **ルーティング**: [`app/init.lua`](app/init.lua)
- **CSRFミドルウェア**: [`app/middleware/csrf.lua`](app/middleware/csrf.lua)
- **E2Eテスト**: [`tests/e2e/test_post_api.sh`](tests/e2e/test_post_api.sh)

## セキュリティ考慮事項

1. **セッション管理**: Redisベースのセッションストレージを使用
2. **CSRF保護**: すべての変更操作でトークン検証を実施
3. **権限チェック**: 投稿の所有者のみが編集・削除可能
4. **入力検証**: すべての入力データをサーバー側で検証
5. **SQLインジェクション対策**: パラメータ化クエリを使用
6. **XSS対策**: 出力時のエスケープ処理（フロントエンド側で実装）

## 今後の拡張

- [ ] 論理削除のサポート（trashステータスの活用）
- [ ] 投稿のバージョン管理
- [ ] 一括操作API（複数投稿の削除など）
- [ ] 投稿の複製機能
- [ ] メディアアップロードとの連携
- [ ] コメント機能との統合
