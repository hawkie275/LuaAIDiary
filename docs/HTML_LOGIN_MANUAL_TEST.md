# HTMLログインフォーム 動作確認手順

## 概要

このドキュメントでは、管理画面用HTMLログインフォーム機能の動作確認手順を説明します。

## 実装内容

以下のファイルが実装されました：

1. **ログインフォームビュー**: [`app/views/auth/login.etlua`](../app/views/auth/login.etlua)
2. **認証コントローラー拡張**: [`app/controllers/auth_controller.lua`](../app/controllers/auth_controller.lua)
   - `login_form()` - ログインフォーム表示
   - `login()` - JSON/HTML両対応のログイン処理
3. **ルーティング**: [`app/init.lua`](../app/init.lua)
   - `GET /admin/login` - ログインフォーム表示
   - `POST /admin/login` - ログイン処理
   - `POST /auth/logout` - ログアウト処理
4. **管理画面コントローラー修正**: [`app/controllers/admin_controller.lua`](../app/controllers/admin_controller.lua)
   - 未認証時のリダイレクト先を `/admin/login` に変更

## 自動テスト

### E2Eテストの実行

HTMLログイン機能の自動テストが用意されています：

```bash
cd LuaAIDiary
./tests/e2e/test_html_login.sh
```

このテストでは以下を確認します：

- ✅ ログインフォームの表示
- ✅ フォーム要素（username_or_email、password、CSRF token）の存在
- ✅ HTMLフォームからのログイン成功
- ✅ ログイン後のダッシュボードアクセス
- ✅ エラーケース（間違ったパスワード、存在しないユーザー）
- ✅ 既存JSON APIの互換性維持

## 手動テスト手順

### 前提条件

1. アプリケーションが起動していること
   ```bash
   cd LuaAIDiary
   docker-compose up -d
   ```

2. 管理者ユーザーが作成されていること
   - デフォルト: `admin` / `admin123`
   - または、`postgresql/init/02_update_admin_password.sql` で設定されたユーザー

### テスト手順

#### 1. ログインフォームへのアクセス

1. ブラウザで `http://localhost:8080/admin/login` にアクセス
2. **期待される結果**:
   - ログインフォームが表示される
   - 「LuaAIDiary 管理画面へログイン」というタイトルが表示される
   - ユーザー名/メールアドレス入力フィールドが表示される
   - パスワード入力フィールドが表示される
   - ログインボタンが表示される
   - デザインは [`static/css/admin.css`](../static/css/admin.css) に準拠

#### 2. ログイン成功

1. ユーザー名に `admin` を入力
2. パスワードに `admin123` を入力
3. ログインボタンをクリック
4. **期待される結果**:
   - `/admin/dashboard` にリダイレクトされる
   - ダッシュボード画面が表示される
   - ヘッダーにユーザー名が表示される
   - ログアウトボタンが表示される

#### 3. 未認証でのダッシュボードアクセス

1. ブラウザのシークレットモード/プライベートブラウジングで新しいウィンドウを開く
2. `http://localhost:8080/admin/dashboard` に直接アクセス
3. **期待される結果**:
   - `/admin/login?redirect=/admin/dashboard` にリダイレクトされる
   - ログインフォームが表示される

#### 4. ログイン後のリダイレクト

1. 手順3のログインフォームで認証情報を入力してログイン
2. **期待される結果**:
   - `/admin/dashboard` にリダイレクトされる
   - リダイレクトパラメータが正しく処理される

#### 5. エラーケース: 間違ったパスワード

1. ログインフォームでユーザー名に `admin` を入力
2. パスワードに間違った値（例: `wrongpassword`）を入力
3. ログインボタンをクリック
4. **期待される結果**:
   - ログインフォームにリダイレクトされる
   - エラーメッセージ「ユーザー名またはパスワードが正しくありません」が表示される

#### 6. エラーケース: 存在しないユーザー

1. ログインフォームでユーザー名に `nonexistentuser` を入力
2. パスワードに任意の値を入力
3. ログインボタンをクリック
4. **期待される結果**:
   - ログインフォームにリダイレクトされる
   - エラーメッセージが表示される

#### 7. ログアウト

1. ログイン済みの状態でダッシュボード画面を表示
2. ヘッダーのログアウトボタンをクリック
3. **期待される結果**:
   - セッションが破棄される
   - ログインが必要なページにアクセスするとログインフォームにリダイレクトされる

#### 8. CSRF保護の確認

1. ブラウザの開発者ツールを開く
2. ログインフォームのHTMLソースを確認
3. **期待される結果**:
   - `<input type="hidden" name="_csrf_token" value="...">` が存在する
   - CSRFトークンの値が空でない

#### 9. 既存JSON APIの互換性確認

curlコマンドで既存のJSON APIが引き続き動作することを確認：

```bash
# JSON APIでのログイン
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' \
  -c cookies.txt

# レスポンスに "success":true が含まれることを確認
```

## トラブルシューティング

### ログインフォームが表示されない

- アプリケーションが起動しているか確認
- ルーティングが正しく設定されているか確認
- ログを確認: `docker-compose logs web`

### CSRFトークンエラー

- セッションが正しく機能しているか確認
- Redisが起動しているか確認: `docker-compose ps redis`

### ログイン後にダッシュボードが表示されない

- 管理者ユーザーのロールが `admin` または `editor` であることを確認
- データベースを確認:
  ```bash
  docker-compose exec db psql -U luaaidiary -d luaaidiary -c "SELECT id, username, email, role FROM users WHERE username='admin';"
  ```

### エラーメッセージが文字化けする

- ブラウザの文字エンコーディングがUTF-8に設定されているか確認
- テンプレートファイルのエンコーディングを確認

## 実装の詳細

### ログインフォーム ([`app/views/auth/login.etlua`](../app/views/auth/login.etlua))

- 管理画面スタイル（[`static/css/admin.css`](../static/css/admin.css)）を使用
- CSRFトークンをhiddenフィールドで送信
- リダイレクト先パラメータをサポート
- エラーメッセージの表示機能
- レスポンシブデザイン対応

### コントローラー ([`app/controllers/auth_controller.lua`](../app/controllers/auth_controller.lua))

#### `login_form(self)` 関数

- 既にログイン済みの場合はダッシュボードにリダイレクト
- CSRFトークンを生成してテンプレートに渡す
- リダイレクト先パラメータを処理

#### `login(self)` 関数の拡張

- `Content-Type` ヘッダーで JSON API と HTML フォームを判別
- **JSON API** (`Content-Type: application/json`):
  - JSONレスポンスを返す（既存の動作）
- **HTMLフォーム** (`Content-Type: application/x-www-form-urlencoded`):
  - ログイン成功時: リダイレクト先にリダイレクト
  - ログイン失敗時: エラーメッセージ付きでログインフォームにリダイレクト

### ルーティング ([`app/init.lua`](../app/init.lua))

```lua
-- ログインフォーム表示
app:get("/admin/login", function(self)
    return auth_controller.login_form(self)
end)

-- ログイン処理（JSON/HTML両対応）
app:post("/admin/login", function(self)
    return auth_controller.login(self)
end)

-- ログアウト処理
app:post("/auth/logout", function(self)
    return auth_controller.logout()
end)
```

### セキュリティ機能

1. **CSRF保護**: すべてのPOSTリクエストでCSRFトークンを検証
2. **セッション管理**: Redisベースのセッションストア
3. **パスワードハッシュ**: bcryptでハッシュ化
4. **定数時間比較**: CSRFトークン検証でタイミング攻撃を防止

## 関連ドキュメント

- [認証システムドキュメント](../README_AUTH.md)
- [管理画面ドキュメント](../README_ADMIN.md)
- [アーキテクチャドキュメント](../ARCHITECTURE.md)
