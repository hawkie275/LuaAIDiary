# LuaAIDiary 認証システム

LuaAIDiaryの認証システムは、セキュアなユーザー認証とセッション管理を提供します。

## 📋 目次

- [概要](#概要)
- [アーキテクチャ](#アーキテクチャ)
- [APIエンドポイント](#apiエンドポイント)
- [使用方法](#使用方法)
- [ミドルウェア](#ミドルウェア)
- [セキュリティ](#セキュリティ)
- [テスト](#テスト)

## 概要

### 主な機能

- **ユーザー認証**: bcryptを使用した安全なパスワードハッシュ化
- **セッション管理**: Redisベースの高速セッションストレージ
- **権限管理**: 5段階のロールベースアクセス制御（RBAC）
- **セキュアなAPI**: CSRF対策とHTTPOnly Cookieによる保護

### 技術スタック

| コンポーネント | 技術 |
|--------------|------|
| パスワードハッシュ | bcrypt (12 rounds) |
| セッションストア | Redis |
| Cookie設定 | HttpOnly, SameSite=Lax |
| 権限管理 | Role-Based Access Control |

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│           認証システムアーキテクチャ               │
└─────────────────────────────────────────────────┘

┌──────────────┐
│   クライアント  │
└──────┬───────┘
       │ HTTP Request + Cookie
       ▼
┌──────────────────────────────────────┐
│    app/controllers/auth_controller    │ ◄─── APIエンドポイント
│  - login()                            │
│  - logout()                           │
│  - register()                         │
│  - me()                               │
│  - change_password()                  │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│    app/services/auth_service          │ ◄─── ビジネスロジック
│  - authenticate()                     │
│  - register()                         │
│  - hash_password()                    │
│  - verify_password()                  │
│  - check_permission()                 │
└──────────┬───────────────────────────┘
           │
           ├─────────────┬─────────────┐
           ▼             ▼             ▼
┌──────────────┐  ┌─────────────┐  ┌──────────┐
│ app/models/  │  │  app/utils/ │  │  Redis   │
│   user       │  │   session   │  │  Store   │
└──────────────┘  └─────────────┘  └──────────┘
      │
      ▼
┌──────────────┐
│  PostgreSQL  │
│   Database   │
└──────────────┘
```

### ファイル構成

```
app/
├── controllers/
│   └── auth_controller.lua      # HTTPエンドポイント定義
├── services/
│   └── auth_service.lua         # 認証ビジネスロジック
├── middleware/
│   └── auth.lua                 # 認証・権限チェックミドルウェア
├── utils/
│   └── session.lua              # Redisセッション管理
└── models/
    └── user.lua                 # ユーザーモデル

tests/
└── auth/
    └── test_auth_spec.lua       # 認証システムテスト
```

## APIエンドポイント

### 1. ユーザー登録

**エンドポイント**: `POST /api/auth/register`

**リクエストボディ**:
```json
{
  "username": "johndoe",
  "email": "john@example.com",
  "password": "SecurePassword123",
  "display_name": "John Doe"
}
```

**レスポンス（成功）**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": 1,
      "username": "johndoe",
      "email": "john@example.com",
      "display_name": "John Doe",
      "role": "subscriber",
      "created_at": "2025-12-26T04:00:00Z"
    }
  },
  "message": "Registration successful"
}
```

**バリデーションルール**:
- ユーザー名: 3-30文字、英数字とアンダースコアのみ
- メールアドレス: 有効な形式
- パスワード: 8文字以上

---

### 2. ログイン

**エンドポイント**: `POST /api/auth/login`

**リクエストボディ**:
```json
{
  "username_or_email": "johndoe",
  "password": "SecurePassword123"
}
```

**レスポンス（成功）**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": 1,
      "username": "johndoe",
      "email": "john@example.com",
      "display_name": "John Doe",
      "role": "subscriber"
    }
  },
  "message": "Login successful"
}
```

**HTTPヘッダー**:
```
Set-Cookie: luaaidiary_session=<session_id>; Path=/; Max-Age=604800; HttpOnly; SameSite=Lax
```

---

### 3. ログアウト

**エンドポイント**: `POST /api/auth/logout`

**リクエストヘッダー**:
```
Cookie: luaaidiary_session=<session_id>
```

**レスポンス**:
```json
{
  "success": true,
  "message": "Logout successful"
}
```

---

### 4. 現在のユーザー情報取得

**エンドポイント**: `GET /api/auth/me`

**リクエストヘッダー**:
```
Cookie: luaaidiary_session=<session_id>
```

**レスポンス**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": 1,
      "username": "johndoe",
      "email": "john@example.com",
      "display_name": "John Doe",
      "role": "subscriber"
    }
  }
}
```

---

### 5. パスワード変更

**エンドポイント**: `POST /api/auth/change-password`

**リクエストヘッダー**:
```
Cookie: luaaidiary_session=<session_id>
```

**リクエストボディ**:
```json
{
  "old_password": "SecurePassword123",
  "new_password": "NewSecurePassword456"
}
```

**レスポンス**:
```json
{
  "success": true,
  "message": "Password changed successfully"
}
```

---

### 6. 認証状態チェック

**エンドポイント**: `GET /api/auth/check`

**レスポンス**:
```json
{
  "success": true,
  "data": {
    "authenticated": true
  }
}
```

## 使用方法

### ユーザー登録の例

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "TestPassword123",
    "display_name": "Test User"
  }'
```

### ログインの例

```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -c cookies.txt \
  -d '{
    "username_or_email": "testuser",
    "password": "TestPassword123"
  }'
```

### 認証が必要なエンドポイントへのアクセス

```bash
curl http://localhost:8080/api/auth/me \
  -b cookies.txt
```

## ミドルウェア

### 基本的な認証ミドルウェア

```lua
local AuthMiddleware = require("app.middleware.auth")

-- 認証が必要なエンドポイント
app:get("/api/posts/my-posts", function(self)
  AuthMiddleware.require_auth(self)
  -- ここに処理を記述
end)
```

### 権限レベル別ミドルウェア

#### 1. 管理者のみ

```lua
-- 管理者権限が必要
app:delete("/api/users/:id", function(self)
  AuthMiddleware.require_admin(self)
  -- ユーザー削除処理
end)
```

#### 2. エディター以上

```lua
-- エディター権限以上が必要
app:post("/api/posts/publish", function(self)
  AuthMiddleware.require_editor(self)
  -- 記事公開処理
end)
```

#### 3. 著者以上

```lua
-- 著者権限以上が必要
app:post("/api/posts", function(self)
  AuthMiddleware.require_author(self)
  -- 記事作成処理
end)
```

#### 4. カスタム権限レベル

```lua
-- カスタム権限レベル
app:get("/api/contributors/stats", function(self)
  AuthMiddleware.require_role("contributor")(self)
  -- 統計情報取得
end)
```

### オプショナル認証

認証されている場合のみユーザー情報を取得（未認証でもエラーにしない）:

```lua
app:get("/api/posts", function(self)
  AuthMiddleware.optional_auth(self)
  
  -- self.current_user が存在する場合は認証済み
  if self.current_user then
    -- 認証済みユーザー向けの処理
  else
    -- 未認証ユーザー向けの処理
  end
end)
```

### リソース所有者チェック

```lua
-- 自分自身または管理者のみアクセス可能
app:put("/api/users/:id", function(self)
  AuthMiddleware.require_self_or_admin(function(self)
    return self.params.id
  end)(self)
  
  -- ユーザー情報更新処理
end)
```

## 権限管理

### ロールヒエラルキー

```
admin (5)        ─┐
                  │  全ての権限
editor (4)       ─┤
                  │  コンテンツ管理
author (3)       ─┤
                  │  自分の記事管理
contributor (2)  ─┤
                  │  記事下書き作成
subscriber (1)   ─┘  閲覧のみ
```

### 権限チェック例

```lua
local AuthService = require("app.services.auth_service")

local user = {
  id = 1,
  username = "editor_user",
  role = "editor"
}

-- editor権限を持っているか？
local has_editor = AuthService.check_permission(user, "editor")
-- => true

-- admin権限を持っているか？
local has_admin = AuthService.check_permission(user, "admin")
-- => false

-- subscriber権限を持っているか？
local has_subscriber = AuthService.check_permission(user, "subscriber")
-- => true (editorはsubscriber以上の権限を持つ)
```

## セキュリティ

### パスワードセキュリティ

- **ハッシュアルゴリズム**: bcrypt
- **ソルトラウンド**: 12
- **最小パスワード長**: 8文字
- **保存**: パスワードは暗号化されてデータベースに保存

### セッションセキュリティ

- **ストレージ**: Redis（インメモリ）
- **有効期限**: 7日間
- **Cookie設定**:
  - `HttpOnly`: JavaScriptからアクセス不可
  - `SameSite=Lax`: CSRF攻撃を軽減
  - `Secure`: 本番環境ではHTTPSのみ（要設定）

### セキュリティベストプラクティス

1. **パスワードハッシュを絶対に返さない**
   ```lua
   -- ❌ 悪い例
   return { user = user } -- password_hashが含まれる可能性

   -- ✅ 良い例
   local safe_user = {
     id = user.id,
     username = user.username,
     email = user.email,
     role = user.role
   }
   return { user = safe_user }
   ```

2. **セッション再生成**
   ```lua
   -- パスワード変更後はセッションを再生成
   session:regenerate()
   ```

3. **入力バリデーション**
   ```lua
   local validator = require("app.utils.validator")
   
   if not validator.is_valid_email(email) then
     return nil, "Invalid email format"
   end
   ```

## テスト

### テストの実行

```bash
# 全テストを実行
make test

# 認証テストのみ実行
busted tests/auth/test_auth_spec.lua
```

### テストカバレッジ

現在のテストカバレッジ:

- ✅ パスワードハッシュ化
- ✅ パスワード検証
- ✅ 権限チェック（全ロールレベル）
- ⏳ ユーザー登録（統合テスト - 要モック）
- ⏳ ログイン/ログアウト（統合テスト - 要モック）
- ⏳ セッション管理（統合テスト - 要モック）

### ユニットテスト例

```lua
describe("パスワードハッシュ化", function()
  it("パスワードをハッシュ化できる", function()
    local password = "TestPassword123"
    local hash = AuthService.hash_password(password)
    
    assert.is_not_nil(hash)
    assert.is_string(hash)
    assert.is_not_equal(password, hash)
  end)
end)
```

## トラブルシューティング

### よくある問題

#### 1. セッションが保存されない

**症状**: ログイン後もすぐにログアウトされる

**原因**: Redisに接続できていない

**解決策**:
```bash
# Redisの状態を確認
curl http://localhost:8080/api/redis-test

# Dockerコンテナを再起動
make restart
```

#### 2. パスワードハッシュ化エラー

**症状**: `Failed to hash password`エラー

**原因**: bcryptライブラリが正しくインストールされていない

**解決策**:
```bash
# OpenRestyコンテナでbcryptを再インストール
docker-compose exec web luarocks install bcrypt
```

#### 3. 認証ミドルウェアが動作しない

**症状**: 保護されたエンドポイントにアクセスできてしまう

**原因**: ミドルウェアが正しく適用されていない

**解決策**:
```lua
-- before_filterを使用
app:match("protected", "/api/protected", function(self)
  AuthMiddleware.require_auth(self)
  -- 処理
end)
```

## 今後の拡張

### 計画中の機能

- [ ] **二要素認証（2FA）**: TOTPベースの追加認証
- [ ] **パスワードリセット**: メール経由のパスワードリセット
- [ ] **OAuth連携**: Google/GitHub等での認証
- [ ] **API Key認証**: 外部アプリケーション向け
- [ ] **セッション管理画面**: アクティブセッションの一覧と削除
- [ ] **ログイン履歴**: ログイン試行の記録と監視

## 参考資料

- [bcrypt公式ドキュメント](https://github.com/philipnrmn/bcrypt-lua)
- [lua-resty-redis](https://github.com/openresty/lua-resty-redis)
- [Lapis セッション管理](http://leafo.net/lapis/reference/actions.html#request-object-session)
- [OWASP 認証チートシート](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)

---

**作成日**: 2025-12-26  
**バージョン**: 0.1.0  
**メンテナー**: LuaAIDiary Team
