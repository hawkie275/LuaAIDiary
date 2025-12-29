# パスワード変更機能 設計ドキュメント

**プロジェクト**: LuaAIDiary  
**作成日**: 2025-12-29  
**ステータス**: 設計フェーズ  
**目的**: 既存の認証機能を分析し、パスワード変更機能の完全な設計を提供する

---

## 📋 目次

1. [既存認証機能の現状分析](#既存認証機能の現状分析)
2. [パスワード変更機能の現状](#パスワード変更機能の現状)
3. [不足している要素](#不足している要素)
4. [パスワード変更機能の完全設計](#パスワード変更機能の完全設計)
5. [セキュリティ要件](#セキュリティ要件)
6. [実装計画](#実装計画)
7. [テスト計画](#テスト計画)

---

## 既存認証機能の現状分析

### アーキテクチャ概要

LuaAIDiaryの認証システムは、以下のレイヤー構造で実装されています：

```
┌─────────────────────────────────────────────┐
│            プレゼンテーション層               │
│  - auth_controller.lua (HTTPエンドポイント)  │
└─────────────┬───────────────────────────────┘
              │
┌─────────────▼───────────────────────────────┐
│            ビジネスロジック層                 │
│  - auth_service.lua (認証・認可ロジック)      │
└─────────────┬───────────────────────────────┘
              │
        ┌─────┴─────┬──────────────┐
        ▼           ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Model層  │  │ Utils層   │  │ Store層  │
│  user.lua │  │ crypto    │  │  Redis   │
│           │  │ session   │  │          │
│           │  │ validator │  │          │
└─────┬─────┘  └──────────┘  └──────────┘
      │
      ▼
┌──────────┐
│PostgreSQL│
└──────────┘
```

### 既存の認証機能一覧

| 機能 | エンドポイント | 実装状況 | ファイル |
|------|--------------|---------|---------|
| ユーザー登録 | `POST /api/auth/register` | ✅ 実装済み | [`auth_controller.lua:39-121`](app/controllers/auth_controller.lua:39) |
| ログイン（JSON API） | `POST /api/auth/login` | ✅ 実装済み | [`auth_controller.lua:186-276`](app/controllers/auth_controller.lua:186) |
| ログイン（HTML Form） | `POST /admin/login` | ✅ 実装済み | [`auth_controller.lua:186-276`](app/controllers/auth_controller.lua:186) |
| ログインフォーム表示 | `GET /admin/login` | ✅ 実装済み | [`auth_controller.lua:125-181`](app/controllers/auth_controller.lua:125) |
| ログアウト | `POST /api/auth/logout` | ✅ 実装済み | [`auth_controller.lua:281-309`](app/controllers/auth_controller.lua:281) |
| 現在のユーザー情報取得 | `GET /api/auth/me` | ✅ 実装済み | [`auth_controller.lua:313-340`](app/controllers/auth_controller.lua:313) |
| **パスワード変更（API）** | `POST /api/auth/change-password` | ✅ **実装済み** | [`auth_controller.lua:344-405`](app/controllers/auth_controller.lua:344) |
| 認証状態チェック | `GET /api/auth/check` | ✅ 実装済み | [`auth_controller.lua:409-422`](app/controllers/auth_controller.lua:409) |

### セキュリティ機能

#### 1. パスワードセキュリティ
- **ハッシュアルゴリズム**: bcrypt
- **コストファクタ**: 12 rounds
- **実装箇所**: [`app/utils/crypto.lua:147-165`](app/utils/crypto.lua:147)

```lua
function _M.hash_password(password, rounds)
    local bcrypt = require("bcrypt")
    rounds = rounds or 12
    local hash, err = bcrypt.digest(password, rounds)
    return hash, err
end
```

#### 2. セッション管理
- **ストレージ**: Redis
- **有効期限**: 7日間（604,800秒）
- **Cookie設定**:
  - `HttpOnly`: ✅ 有効（JavaScriptからアクセス不可）
  - `SameSite`: Lax（CSRF軽減）
  - `Secure`: ⚠️ 本番環境で要設定
- **実装箇所**: [`app/utils/session.lua`](app/utils/session.lua)

#### 3. バリデーション
- **パスワード強度**: [`app/utils/validator.lua:88-114`](app/utils/validator.lua:88)
  - 最小長: 8文字
  - 最大長: 100文字
  - 必須要素: 英字 + 数字

```lua
function _M.validate_password(password)
    if #password < 8 then
        return false, "パスワードは8文字以上にしてください"
    end
    local has_letter = password:match("[%a]")
    local has_digit = password:match("[%d]")
    if not has_letter or not has_digit then
        return false, "パスワードは英字と数字を含む必要があります"
    end
    return true, nil
end
```

#### 4. 権限管理（RBAC）
- **ロールヒエラルキー**: 
  - `admin` (5) > `editor` (4) > `author` (3) > `contributor` (2) > `subscriber` (1)
- **ミドルウェア**: [`app/middleware/auth.lua`](app/middleware/auth.lua)

---

## パスワード変更機能の現状

### ✅ 既に実装済みの要素

#### 1. バックエンドAPI

**エンドポイント**: `POST /api/auth/change-password`

**リクエスト仕様**:
```json
{
  "old_password": "CurrentPassword123",
  "new_password": "NewSecurePassword456"
}
```

**レスポンス仕様**:
```json
{
  "success": true,
  "message": "Password changed successfully"
}
```

**実装箇所**: [`app/controllers/auth_controller.lua:344-405`](app/controllers/auth_controller.lua:344)

**実装内容**:
1. ✅ セッション認証チェック
2. ✅ 入力バリデーション
   - `old_password` の存在確認
   - `new_password` の存在確認
   - 新パスワードの長さチェック（8文字以上）
3. ✅ パスワード変更処理（`AuthService.change_password()`）
4. ✅ セッション再生成（セキュリティ対策）

#### 2. サービス層

**実装箇所**: [`app/services/auth_service.lua:186-194`](app/services/auth_service.lua:186)

```lua
function AuthService.change_password(user_id, old_password, new_password)
  return User.change_password(user_id, old_password, new_password)
end
```

#### 3. モデル層

**実装箇所**: [`app/models/user.lua:195-225`](app/models/user.lua:195)

**実装内容**:
1. ✅ 現在のパスワード検証
2. ✅ 新パスワードのバリデーション（`validator.validate_password()`）
3. ✅ 新パスワードのハッシュ化（bcrypt）
4. ✅ データベース更新

#### 4. ルーティング

**実装箇所**: [`app/init.lua:262`](app/init.lua:262)

```lua
app:match("auth_change_password", "/api/auth/change-password", auth_controller.change_password)
```

#### 5. ドキュメント

**ドキュメント**: [`README_AUTH.md:220-244`](README_AUTH.md:220)

APIの使用方法が記載済み。

---

## 不足している要素

### ❌ UI/UXレイヤー

#### 1. パスワード変更ビュー（HTML）が存在しない

**現状**: 
- `app/views/auth/` ディレクトリには [`login.etlua`](app/views/auth/login.etlua) のみ
- パスワード変更用のビューテンプレートが未作成

**必要なファイル**:
- `app/views/auth/change_password.etlua` （新規作成）
- または `app/views/admin/settings/change_password_section.etlua` （設定画面の一部として）

#### 2. 管理画面からのアクセス導線がない

**現状**: 
- [`app/views/admin/settings/index.etlua`](app/views/admin/settings/index.etlua) にパスワード変更セクションなし
- 管理画面ダッシュボードからのリンクなし

**必要な要素**:
- 設定画面にパスワード変更セクションの追加
- または専用のパスワード変更ページへのリンク

#### 3. HTMLフォーム対応のコントローラーメソッドがない

**現状**: 
- JSON APIのみ実装
- HTMLフォームからのPOSTに対応するメソッドがない

**必要な要素**:
- フォーム表示用のGETエンドポイント（例: `GET /admin/change-password`）
- フォーム送信用のPOSTエンドポイント（例: `POST /admin/change-password`）
  - リダイレクト処理
  - フラッシュメッセージ

---

## パスワード変更機能の完全設計

### アーキテクチャ方針

既存のログイン機能と同様に、以下の2つのインターフェースを提供：

1. **JSON API**: 外部アプリケーション・SPA向け（既存）
2. **HTML Form**: 管理画面からの直接利用（新規実装が必要）

### 設計オプション

#### オプションA: 独立したパスワード変更ページ

**特徴**:
- 専用のURLとビュー（`/admin/change-password`）
- セキュリティを重視した独立したページ
- ユーザーが意識的にパスワード変更を行う

**推奨度**: ⭐⭐⭐⭐⭐ （推奨）

**メリット**:
- セキュリティフォーカス（他の設定と分離）
- CSRF保護が実装しやすい
- 変更確認画面を追加しやすい

**デメリット**:
- ページ数が増える

#### オプションB: 設定画面の一部として統合

**特徴**:
- 既存の `/admin/settings` にセクションとして追加
- 他のサイト設定と同じページで管理

**推奨度**: ⭐⭐⭐

**メリット**:
- UI統一性
- ページ遷移が少ない

**デメリット**:
- セキュリティ的に他の設定と混在
- パスワード変更の重要性が薄れる

### 推奨設計: オプションA（独立ページ）

以下、オプションAに基づいた詳細設計を提示します。

---

## 詳細設計

### 1. エンドポイント設計

#### 新規追加が必要なエンドポイント

| メソッド | パス | 説明 | コントローラーメソッド |
|---------|------|------|---------------------|
| GET | `/admin/change-password` | パスワード変更フォーム表示 | `auth_controller.change_password_form()` |
| POST | `/admin/change-password` | パスワード変更処理（HTML Form） | `auth_controller.change_password_submit()` |

#### 既存のAPIエンドポイント（変更不要）

| メソッド | パス | 説明 |
|---------|------|------|
| POST | `/api/auth/change-password` | パスワード変更（JSON API） |

### 2. ビュー設計

#### 2.1 パスワード変更フォーム

**ファイル**: `app/views/auth/change_password.etlua`

**必要な要素**:
```html
<form method="POST" action="/admin/change-password">
  <!-- CSRFトークン -->
  <input type="hidden" name="_csrf_token" value="<%= csrf_token %>">
  
  <!-- 現在のパスワード -->
  <div class="form-group">
    <label for="old_password">現在のパスワード</label>
    <input type="password" id="old_password" name="old_password" 
           class="form-control" required autocomplete="current-password">
  </div>
  
  <!-- 新しいパスワード -->
  <div class="form-group">
    <label for="new_password">新しいパスワード</label>
    <input type="password" id="new_password" name="new_password" 
           class="form-control" required autocomplete="new-password"
           minlength="8" pattern="^(?=.*[A-Za-z])(?=.*\d).{8,}$">
    <small class="form-text text-muted">
      8文字以上、英字と数字を含む必要があります
    </small>
  </div>
  
  <!-- 新しいパスワード（確認） -->
  <div class="form-group">
    <label for="new_password_confirmation">新しいパスワード（確認）</label>
    <input type="password" id="new_password_confirmation" 
           name="new_password_confirmation" class="form-control" 
           required autocomplete="new-password">
  </div>
  
  <!-- エラーメッセージ表示 -->
  <% if error_message then %>
    <div class="alert alert-danger"><%= error_message %></div>
  <% end %>
  
  <!-- 成功メッセージ表示 -->
  <% if success_message then %>
    <div class="alert alert-success"><%= success_message %></div>
  <% end %>
  
  <!-- 送信ボタン -->
  <button type="submit" class="btn btn-primary">パスワードを変更</button>
  <a href="/admin/dashboard" class="btn btn-secondary">キャンセル</a>
</form>
```

**セキュリティ考慮事項**:
- `autocomplete="current-password"` / `"new-password"` でブラウザのパスワード管理に対応
- HTML5バリデーション（`minlength`, `pattern`, `required`）
- CSRFトークン必須

#### 2.2 レイアウト

既存の管理画面レイアウト（[`app/views/admin/layout.etlua`](app/views/admin/layout.etlua)）を使用。

### 3. コントローラー設計

#### 3.1 `change_password_form()` - フォーム表示

**ファイル**: `app/controllers/auth_controller.lua`

**処理フロー**:
```mermaid
graph TD
    A[GET /admin/change-password] --> B[セッション開始]
    B --> C{認証済み?}
    C -->|No| D[/admin/loginにリダイレクト]
    C -->|Yes| E[CSRFトークン生成]
    E --> F[テンプレートレンダリング]
    F --> G[HTMLレスポンス]
```

**実装仕様**:
```lua
function AuthController.change_password_form(self)
  -- セッション取得
  local session = Session.new()
  local ok = session:start()
  
  -- 認証チェック
  if not ok or not session:is_authenticated() then
    return {
      redirect_to = "/admin/login?redirect=/admin/change-password",
      status = 302
    }
  end
  
  -- CSRFトークン生成
  local csrf_token = csrf.get_token(session)
  
  -- テンプレートレンダリング
  local template = etlua.compile(template_content)
  local html = template({
    csrf_token = csrf_token,
    error_message = self.params.error or nil,
    success_message = self.params.success or nil
  })
  
  self.res.headers["Content-Type"] = "text/html; charset=utf-8"
  return html
end
```

#### 3.2 `change_password_submit()` - フォーム送信処理

**処理フロー**:
```mermaid
graph TD
    A[POST /admin/change-password] --> B[セッション取得]
    B --> C{認証済み?}
    C -->|No| D[/admin/loginにリダイレクト]
    C -->|Yes| E[CSRFトークン検証]
    E --> F{CSRF OK?}
    F -->|No| G[エラー: 不正なリクエスト]
    F -->|Yes| H[入力バリデーション]
    H --> I{バリデーションOK?}
    I -->|No| J[エラーメッセージ付きでフォームに戻る]
    I -->|Yes| K{確認パスワード一致?}
    K -->|No| L[エラー: パスワード不一致]
    K -->|Yes| M[AuthService.change_password呼び出し]
    M --> N{変更成功?}
    N -->|No| O[エラーメッセージ付きでフォームに戻る]
    N -->|Yes| P[セッション再生成]
    P --> Q[成功メッセージ付きでリダイレクト]
```

**実装仕様**:
```lua
function AuthController.change_password_submit(self)
  -- セッション取得
  local session = Session.new()
  local ok = session:start()
  
  -- 認証チェック
  if not ok or not session:is_authenticated() then
    return {
      redirect_to = "/admin/login",
      status = 302
    }
  end
  
  -- CSRFトークン検証
  local csrf_valid = csrf.verify_token(session, self.params._csrf_token)
  if not csrf_valid then
    return {
      redirect_to = "/admin/change-password?error=" .. 
        ngx.escape_uri("不正なリクエストです"),
      status = 302
    }
  end
  
  -- 入力バリデーション
  local old_password = self.params.old_password
  local new_password = self.params.new_password
  local new_password_confirmation = self.params.new_password_confirmation
  
  if not old_password or old_password == "" then
    return {
      redirect_to = "/admin/change-password?error=" .. 
        ngx.escape_uri("現在のパスワードを入力してください"),
      status = 302
    }
  end
  
  if not new_password or new_password == "" then
    return {
      redirect_to = "/admin/change-password?error=" .. 
        ngx.escape_uri("新しいパスワードを入力してください"),
      status = 302
    }
  end
  
  -- 新しいパスワードのバリデーション
  local valid, err = validator.validate_password(new_password)
  if not valid then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri(err),
      status = 302
    }
  end
  
  -- 確認パスワードチェック
  if new_password ~= new_password_confirmation then
    return {
      redirect_to = "/admin/change-password?error=" .. 
        ngx.escape_uri("新しいパスワードが一致しません"),
      status = 302
    }
  end
  
  -- パスワード変更
  local user_id = session:get_user_id()
  local ok, err = AuthService.change_password(user_id, old_password, new_password)
  
  if not ok then
    return {
      redirect_to = "/admin/change-password?error=" .. 
        ngx.escape_uri(err or "パスワードの変更に失敗しました"),
      status = 302
    }
  end
  
  -- セッション再生成（セキュリティ対策）
  session:regenerate()
  
  -- 成功リダイレクト
  return {
    redirect_to = "/admin/change-password?success=" .. 
      ngx.escape_uri("パスワードを変更しました"),
    status = 302
  }
end
```

### 4. ルーティング設計

**追加が必要なルート**: `app/init.lua`

```lua
-- パスワード変更フォーム表示
app:get("/admin/change-password", function(self)
    return auth_controller.change_password_form(self)
end)

-- パスワード変更処理
app:post("/admin/change-password", function(self)
    return auth_controller.change_password_submit(self)
end)
```

### 5. ナビゲーション設計

#### 5.1 管理画面ダッシュボードからのリンク

**ファイル**: `app/views/admin/dashboard.etlua`

**追加箇所**:
```html
<div class="dashboard-card">
  <h3>⚙️ アカウント設定</h3>
  <ul>
    <li><a href="/admin/change-password">パスワード変更</a></li>
    <li><a href="/admin/settings">サイト設定</a></li>
  </ul>
</div>
```

#### 5.2 ヘッダー/メニューからのリンク

**ファイル**: `app/views/admin/layout.etlua`

ユーザーメニュー（ドロップダウン）に追加:
```html
<div class="user-menu">
  <a href="/admin/change-password">パスワード変更</a>
  <form method="POST" action="/auth/logout">
    <button type="submit">ログアウト</button>
  </form>
</div>
```

---

## セキュリティ要件

### 1. CSRF保護

**必須要件**:
- すべてのPOSTリクエストでCSRFトークンを検証
- トークン不一致時はエラーレスポンス

**実装箇所**: [`app/middleware/csrf.lua`](app/middleware/csrf.lua)

### 2. セッション管理

**要件**:
- パスワード変更後は必ずセッションIDを再生成
- セッション固定攻撃（Session Fixation）の防止

**実装**: `session:regenerate()`

### 3. パスワード強度チェック

**現在の要件**:
- 最小8文字
- 英字と数字を含む

**推奨の追加要件**:
- 特殊文字の推奨（必須にはしない）
- パスワード強度インジケーターの表示（UI改善）

### 4. レート制限（推奨）

**目的**: ブルートフォース攻撃の防止

**実装方針**:
- パスワード変更試行回数の制限（例: 5回/時間）
- Redis を使用したカウンター

**注**: 現在は未実装。将来の拡張として検討。

### 5. 監査ログ（推奨）

**記録すべき情報**:
- パスワード変更日時
- ユーザーID
- IPアドレス
- User-Agent

**注**: 現在は未実装。将来の拡張として検討。

---

## バリデーション設計

### 1. フロントエンド（HTML5）

```html
<input type="password" 
       name="new_password" 
       required 
       minlength="8" 
       pattern="^(?=.*[A-Za-z])(?=.*\d).{8,}$">
```

**目的**: 即座のフィードバック、UX向上

### 2. バックエンド（Lua）

**必須チェック項目**:
1. ✅ すべてのフィールドが入力されているか
2. ✅ 新しいパスワードが8文字以上か
3. ✅ 新しいパスワードに英字と数字が含まれるか
4. ✅ 新しいパスワードと確認パスワードが一致するか
5. ✅ 現在のパスワードが正しいか

**実装箇所**:
- [`app/utils/validator.lua:validate_password()`](app/utils/validator.lua:88)
- [`app/controllers/auth_controller.lua`](app/controllers/auth_controller.lua) （新規追加メソッド内）

### 3. エラーメッセージ設計

| エラー条件 | メッセージ |
|-----------|-----------|
| 現在のパスワードが空 | 「現在のパスワードを入力してください」 |
| 新しいパスワードが空 | 「新しいパスワードを入力してください」 |
| 新しいパスワードが8文字未満 | 「パスワードは8文字以上にしてください」 |
| 英字または数字が含まれない | 「パスワードは英字と数字を含む必要があります」 |
| 確認パスワード不一致 | 「新しいパスワードが一致しません」 |
| 現在のパスワードが間違っている | 「現在のパスワードが正しくありません」 |
| その他のエラー | 「パスワードの変更に失敗しました」 |

**成功メッセージ**:
- 「パスワードを変更しました」

---

## UI/UX設計

### 1. ページレイアウト

```
┌─────────────────────────────────────────┐
│ 管理画面ヘッダー                          │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ パスワード変更                            │
│                                         │
│ [成功/エラーメッセージ]                    │
│                                         │
│ ┌─────────────────────────────────┐     │
│ │ 現在のパスワード                  │     │
│ │ [●●●●●●●●]                       │     │
│ └─────────────────────────────────┘     │
│                                         │
│ ┌─────────────────────────────────┐     │
│ │ 新しいパスワード                  │     │
│ │ [●●●●●●●●]                       │     │
│ │ 8文字以上、英字と数字を含む       │     │
│ └─────────────────────────────────┘     │
│                                         │
│ ┌─────────────────────────────────┐     │
│ │ 新しいパスワード（確認）           │     │
│ │ [●●●●●●●●]                       │     │
│ └─────────────────────────────────┘     │
│                                         │
│ [パスワードを変更]  [キャンセル]          │
└─────────────────────────────────────────┘
```

### 2. インタラクション

**フォーム送信時**:
1. クライアント側バリデーション（HTML5）
2. 送信ボタンを無効化（二重送信防止）
3. サーバー側バリデーション
4. エラー時: フォームに戻る + エラーメッセージ表示
5. 成功時: 同じページにリダイレクト + 成功メッセージ表示

### 3. アクセシビリティ

- ラベルとinputの関連付け（`for`属性）
- `aria-describedby` でヘルプテキストを関連付け
- エラーメッセージは `role="alert"` で通知

---

## 実装計画

### フェーズ1: ビュー作成

#### タスク1.1: パスワード変更フォームテンプレート作成
- **ファイル**: `app/views/auth/change_password.etlua`
- **内容**: 
  - フォームHTML
  - CSRFトークン埋め込み
  - エラー/成功メッセージ表示
  - バリデーションルール

#### タスク1.2: 管理画面レイアウトの確認
- **ファイル**: `app/views/admin/layout.etlua`
- **内容**: 既存レイアウトが使用可能か確認

### フェーズ2: コントローラー実装

#### タスク2.1: `change_password_form()` 実装
- **ファイル**: `app/controllers/auth_controller.lua`
- **内容**:
  - セッション認証チェック
  - CSRFトークン生成
  - テンプレートレンダリング

#### タスク2.2: `change_password_submit()` 実装
- **ファイル**: `app/controllers/auth_controller.lua`
- **内容**:
  - CSRFトークン検証
  - 入力バリデーション
  - パスワード確認チェック
  - `AuthService.change_password()` 呼び出し
  - セッション再生成
  - リダイレクト処理

### フェーズ3: ルーティング設定

#### タスク3.1: ルート追加
- **ファイル**: `app/init.lua`
- **内容**:
  - `GET /admin/change-password`
  - `POST /admin/change-password`

### フェーズ4: ナビゲーション追加

#### タスク4.1: ダッシュボードにリンク追加
- **ファイル**: `app/views/admin/dashboard.etlua`
- **内容**: パスワード変更へのリンク

#### タスク4.2: 管理画面メニューにリンク追加（オプション）
- **ファイル**: `app/views/admin/layout.etlua`
- **内容**: ユーザーメニューにパスワード変更リンク

### フェーズ5: CSS/スタイリング

#### タスク5.1: スタイル調整
- **ファイル**: `static/css/admin.css`
- **内容**: フォームスタイリング（必要に応じて）

### フェーズ6: テスト

#### タスク6.1: 手動テスト
- ログイン状態での動作確認
- 未ログイン時のリダイレクト確認
- バリデーションエラーの確認
- CSRF検証の確認
- パスワード変更成功の確認

#### タスク6.2: 自動テスト作成（オプション）
- **ファイル**: `tests/controllers/test_auth_change_password_spec.lua`
- **内容**: 
  - フォーム表示テスト
  - 正常系テスト
  - 異常系テスト

### フェーズ7: ドキュメント更新

#### タスク7.1: README_AUTH.md 更新
- **ファイル**: `README_AUTH.md`
- **内容**: HTML Formベースのパスワード変更手順を追加

---

## テスト計画

### 1. 単体テスト

#### 1.1 バリデーションテスト
```lua
describe("パスワードバリデーション", function()
  it("8文字以上であること", function()
    local valid, err = validator.validate_password("Pass123")
    assert.is_false(valid)
    assert.equals("パスワードは8文字以上にしてください", err)
  end)
  
  it("英字と数字を含むこと", function()
    local valid, err = validator.validate_password("password")
    assert.is_false(valid)
  end)
  
  it("有効なパスワード", function()
    local valid, err = validator.validate_password("SecurePass123")
    assert.is_true(valid)
  end)
end)
```

### 2. 統合テスト

#### 2.1 パスワード変更フロー
```lua
describe("パスワード変更機能", function()
  it("正常にパスワードを変更できる", function()
    -- セットアップ: ユーザー作成とログイン
    -- パスワード変更リクエスト
    -- 検証: 新しいパスワードでログインできる
  end)
  
  it("現在のパスワードが間違っている場合はエラー", function()
    -- 間違ったold_passwordでリクエスト
    -- エラーレスポンスを確認
  end)
  
  it("新しいパスワードが弱い場合はエラー", function()
    -- 短いパスワードでリクエスト
    -- エラーレスポンスを確認
  end)
end)
```

### 3. E2Eテスト

#### 3.1 ブラウザテスト（手動）
- [ ] ログイン画面からログイン
- [ ] ダッシュボードからパスワード変更ページへ遷移
- [ ] 現在のパスワードを入力
- [ ] 新しいパスワードを入力
- [ ] 確認パスワードを入力
- [ ] 送信ボタンをクリック
- [ ] 成功メッセージが表示される
- [ ] 一度ログアウト
- [ ] 新しいパスワードでログインできる

#### 3.2 セキュリティテスト
- [ ] CSRFトークンなしでPOSTした場合、エラーになる
- [ ] 未ログイン状態でアクセスした場合、ログイン画面にリダイレクトされる
- [ ] パスワード変更後、セッションIDが変更される

### 4. パフォーマンステスト

#### 4.1 負荷テスト
- パスワード変更リクエストの処理時間測定
- bcryptのコストファクタ（12 rounds）の妥当性確認

---

## データベーススキーマ

### 既存スキーマ（変更不要）

**テーブル**: `users`

| カラム | 型 | 説明 |
|--------|-----|------|
| id | SERIAL PRIMARY KEY | ユーザーID |
| username | VARCHAR(50) UNIQUE | ユーザー名 |
| email | VARCHAR(100) UNIQUE | メールアドレス |
| password_hash | VARCHAR(255) | パスワードハッシュ（bcrypt） |
| display_name | VARCHAR(100) | 表示名 |
| role | VARCHAR(20) | ロール |
| created_at | TIMESTAMP | 作成日時 |
| updated_at | TIMESTAMP | 更新日時 |

**変更の必要性**: なし（既存スキーマで対応可能）

### 将来の拡張（オプション）

パスワード変更履歴を記録する場合:

**新テーブル**: `password_change_logs`

```sql
CREATE TABLE password_change_logs (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip_address VARCHAR(45),
  user_agent TEXT
);
```

**注**: 現在の要件には含まれない。セキュリティ監査が必要な場合に実装。

---

## 追加検討事項

### 1. パスワードリセット機能

**現状**: 未実装

**必要性**: 
- パスワードを忘れた場合の救済措置
- メール経由のリセットトークン発行

**実装範囲**: 
- 今回のスコープ外
- 別タスクとして検討

### 2. 二要素認証（2FA）

**現状**: 未実装

**必要性**: 
- セキュリティ強化
- TOTPベースの追加認証

**実装範囲**: 
- 今回のスコープ外
- 将来の拡張として検討

### 3. パスワード強度インジケーター

**目的**: UX向上

**実装方法**:
- JavaScriptでリアルタイム表示
- zxcvbn ライブラリの使用を検討

**実装優先度**: 低（Nice to have）

### 4. パスワード履歴管理

**目的**: 
- 過去N回分のパスワードの再利用を防止

**実装範囲**: 
- 今回のスコープ外
- 高セキュリティ要件がある場合に実装

---

## まとめ

### 既存実装の評価

| 項目 | 実装状況 | 品質 |
|------|---------|------|
| パスワード変更API | ✅ 完了 | ⭐⭐⭐⭐⭐ 優秀 |
| パスワードハッシュ化 | ✅ 完了 | ⭐⭐⭐⭐⭐ bcrypt 12 rounds |
| セッション管理 | ✅ 完了 | ⭐⭐⭐⭐ Redis + HttpOnly Cookie |
| バリデーション | ✅ 完了 | ⭐⭐⭐⭐ 基本要件を満たす |
| CSRF保護 | ✅ 完了 | ⭐⭐⭐⭐ 実装済み |

### 不足している要素

| 項目 | 優先度 | 作業量 |
|------|-------|-------|
| パスワード変更ビュー | 🔴 高 | 中 |
| HTMLフォーム対応コントローラー | 🔴 高 | 中 |
| ルーティング設定 | 🔴 高 | 小 |
| ナビゲーションリンク | 🟡 中 | 小 |
| E2Eテスト | 🟡 中 | 中 |
| ドキュメント更新 | 🟢 低 | 小 |

### 推奨実装順序

1. **フェーズ1**: ビュー作成（change_password.etlua）
2. **フェーズ2**: コントローラー実装
3. **フェーズ3**: ルーティング設定
4. **フェーズ4**: ナビゲーション追加
5. **フェーズ5**: テスト実施
6. **フェーズ6**: ドキュメント更新

### セキュリティレビュー

**現在の実装で満たされているセキュリティ要件**:
- ✅ パスワードハッシュ化（bcrypt）
- ✅ セッション管理（Redis + HttpOnly Cookie）
- ✅ CSRF保護
- ✅ 入力バリデーション
- ✅ セッション再生成（パスワード変更後）

**追加推奨事項**:
- ⚠️ レート制限（ブルートフォース攻撃対策）
- ⚠️ 監査ログ（パスワード変更履歴）
- ⚠️ 本番環境でのSecure Cookie設定

---

## 次のステップ

### Code モードでの実装

この設計書に基づいて、以下のファイルを実装:

1. `app/views/auth/change_password.etlua` - パスワード変更フォーム
2. `app/controllers/auth_controller.lua` - 2つのメソッド追加
   - `change_password_form()`
   - `change_password_submit()`
3. `app/init.lua` - ルーティング追加
4. `app/views/admin/dashboard.etlua` - ナビゲーションリンク追加

### 実装時の注意点

- 既存のログイン機能（`login_form()`, `login()`）を参考にする
- CSRF保護を必ず実装
- エラーメッセージは日本語で統一
- セッション再生成を忘れずに実装

---

**設計完了日**: 2025-12-29  
**レビュー推奨**: 実装前にこのドキュメントをレビューしてください  
**ドキュメントバージョン**: 1.0
