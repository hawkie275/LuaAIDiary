# E2Eテスト（End-to-End Tests）

このディレクトリには、HTTPリクエストを使用したエンドツーエンド（E2E）テストが含まれています。実際のAPIエンドポイントに対してHTTPリクエストを送信し、レスポンスを検証します。

## 概要

E2Eテストは以下の特徴を持ちます：

- **実際のHTTPリクエスト**: curlを使用してAPIを呼び出し
- **完全なスタック**: Web層、コントローラー層、モデル層、データベースまで全て実行
- **実際の認証フロー**: セッションCookieを使用した認証
- **リアルワールドシナリオ**: ユーザーが実際に行う操作をシミュレート

## 実装済みテスト

### 管理画面ダッシュボード E2Eテスト (`test_admin_dashboard.sh`)

実際のHTTPリクエストで管理画面の動作をテストします：

#### 1. 認証チェックテスト
- ✅ 未認証でのアクセス → リダイレクトまたは401エラー
- ✅ 管理者ユーザーでログイン → セッション確立
- ✅ 認証状態チェック → ユーザー情報確認
- ✅ CSRFトークン取得

#### 2. ダッシュボードアクセステスト
- ✅ `GET /admin` → 302リダイレクト（/admin/dashboard へ）
- ✅ `GET /admin/dashboard` → 200 OK、HTMLレスポンス

#### 3. レスポンス内容の検証
- ✅ HTMLタイトル、ヘッダー、フッターの存在確認
- ✅ 統計情報カードの表示確認（投稿、カテゴリー、タグ、ユーザー）
- ✅ 最近の投稿テーブルの表示確認
- ✅ ナビゲーションメニューの表示確認

#### 4. 権限チェックのテスト
- ✅ admin ロール → アクセス成功（200 OK）
- ✅ editor ロール → アクセス成功（200 OK）※要ロール変更
- ✅ author ロール → 403エラー
- ✅ subscriber ロール → 403エラー

#### 5. ログアウトテスト
- ✅ ログアウト → セッション破棄
- ✅ ログアウト後のアクセス → 401エラー

#### 6. クリーンアップ
- ✅ テストユーザー情報の表示（手動削除用）

### 投稿API E2Eテスト (`test_post_api.sh`)

実際のHTTPリクエストで以下のシナリオをテストします：

#### 1. ヘルスチェック
- ✅ `/health` エンドポイントが正常に応答

#### 2. データベース接続テスト
- ✅ `/api/db-test` でデータベース接続を確認

#### 3. 認証フロー
- ✅ ユーザー登録（POST `/api/auth/register`）
- ✅ ログイン（POST `/api/auth/login`）
- ✅ 認証状態チェック（GET `/api/auth/me`）
- ✅ ログアウト（POST `/api/auth/logout`）

#### 4. 投稿CRUD操作
- ✅ 投稿作成（POST `/api/posts`） - 認証あり
- ✅ 投稿一覧取得（GET `/api/posts`）
- ✅ 投稿詳細取得（GET `/api/posts/:id`）
- ✅ 投稿更新（PUT `/api/posts/:id`） - 認証あり
- ✅ 投稿削除（DELETE `/api/posts/:id`） - 認証あり
- ✅ 削除確認（404レスポンスの検証）

#### 5. 認証チェック
- ✅ 認証なしで投稿作成（401エラーを期待）

#### 6. クリーンアップ
- ✅ テストユーザー情報の表示（手動削除用）

## テストの実行方法

### 前提条件

1. **サービスの起動**: アプリケーションが起動している必要があります
   ```bash
   make up
   # または
   make dev
   ```

2. **サービスの確認**: エンドポイントが応答すること
   ```bash
   make health
   # または
   curl http://localhost:8080/health
   ```

### E2Eテストの実行

```bash
# E2Eテストのみを実行
make test-e2e

# または直接スクリプトを実行
./tests/e2e/test_post_api.sh
./tests/e2e/test_category_tag_api.sh
./tests/e2e/test_admin_dashboard.sh

# カスタムURLを指定
BASE_URL=http://localhost:8080 ./tests/e2e/test_post_api.sh

# 管理画面テストで管理者ユーザーを指定
ADMIN_USER=admin ADMIN_PASS=your_password ./tests/e2e/test_admin_dashboard.sh
```

### すべてのテストを実行

```bash
# ユニット、統合、E2Eすべてのテストを実行
make test-all
```

## テスト結果の例

```
=========================================
投稿API E2Eテスト
=========================================
Base URL: http://localhost:8080

[TEST] ヘルスチェック
[PASS] ヘルスチェック成功
[TEST] データベース接続テスト
[PASS] データベース接続成功
[TEST] ユーザー登録
[PASS] ユーザー登録成功
[TEST] ログイン
[PASS] ログイン成功
[TEST] 認証状態チェック
[PASS] 認証状態チェック成功
[TEST] 投稿作成（認証あり）
[PASS] 投稿作成成功 (ID: 42)
[TEST] 投稿一覧取得
[PASS] 投稿一覧取得成功
[TEST] 投稿詳細取得 (ID: 42)
[PASS] 投稿詳細取得成功
[TEST] 投稿更新 (ID: 42)
[PASS] 投稿更新成功
[TEST] 投稿削除 (ID: 42)
[PASS] 投稿削除成功
[TEST] 削除確認 (ID: 42)
[PASS] 削除確認成功（404が返る）
[TEST] 認証なしで投稿作成（401が期待される）
[PASS] 認証なし投稿作成: 正しく401が返る
[TEST] ログアウト
[PASS] ログアウト成功
[TEST] テストユーザーのクリーンアップ

  テストユーザー情報:
  ユーザー名: e2e_test_user_1735211234
  メールアドレス: e2e_test_user_1735211234@test.com

  注: テスト後、以下のSQLでテストユーザーを削除してください:
  docker-compose exec db psql -U luaaidiary -d luaaidiary -c "DELETE FROM users WHERE username = 'e2e_test_user_1735211234';"

[PASS] テストユーザー情報を表示（手動削除を推奨）

=========================================
テスト結果
=========================================
成功: 14
失敗: 0
合計: 14

✓ すべてのテストが成功しました！
```

## スクリプトの構造

### ヘルパー関数

```bash
print_test()   # テスト名を黄色で表示
print_pass()   # 成功を緑色で表示（カウンターを増加）
print_fail()   # 失敗を赤色で表示（カウンターを増加）
```

### セッション管理

- Cookie ファイル: `/tmp/luaaidiary_e2e_cookies.txt`
- 自動クリーンアップ: テスト終了時に削除

### HTTPリクエストパターン

```bash
# レスポンスとHTTPステータスコードを両方取得
response=$(curl -s -w "\n%{http_code}" URL)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

# 認証付きリクエスト
curl -b "$COOKIE_FILE" URL

# JSONボディを送信
curl -H "Content-Type: application/json" \
     -d '{"key":"value"}' URL
```

## テストユーザーのクリーンアップ

E2Eテストは実際のデータベースにテストユーザーを作成します。テスト完了後、以下の方法でクリーンアップしてください：

### 方法1: PostgreSQLクライアント経由

```bash
make psql

# PostgreSQLプロンプトで
DELETE FROM users WHERE username LIKE 'e2e_test_user_%';
```

### 方法2: docker-compose経由

```bash
docker-compose exec db psql -U luaaidiary -d luaaidiary \
  -c "DELETE FROM users WHERE username LIKE 'e2e_test_user_%';"
```

### 方法3: テスト出力のコマンドをコピー

テスト終了時に表示されるSQLコマンドをコピーして実行：

```bash
docker-compose exec db psql -U luaaidiary -d luaaidiary \
  -c "DELETE FROM users WHERE username = 'e2e_test_user_1735211234';"
```

## 環境変数

### BASE_URL

テスト対象のベースURLを変更できます：

```bash
# デフォルト: http://localhost:8080
BASE_URL=http://localhost:8080 ./tests/e2e/test_post_api.sh

# 別のポートでテスト
BASE_URL=http://localhost:3000 ./tests/e2e/test_post_api.sh

# リモート環境でテスト
BASE_URL=https://staging.example.com ./tests/e2e/test_post_api.sh
```

### ADMIN_USER / ADMIN_PASS

管理画面テスト用の管理者ユーザー情報：

```bash
# デフォルト: admin / admin_password
ADMIN_USER=admin ADMIN_PASS=admin_password ./tests/e2e/test_admin_dashboard.sh

# カスタム管理者ユーザーでテスト
ADMIN_USER=myadmin ADMIN_PASS=mypassword ./tests/e2e/test_admin_dashboard.sh

# 環境変数をまとめて指定
BASE_URL=http://localhost:8080 \
ADMIN_USER=admin \
ADMIN_PASS=admin_password \
./tests/e2e/test_admin_dashboard.sh
```

## 統合テストとの違い

| 項目 | E2Eテスト | 統合テスト |
|------|----------|-----------|
| 対象 | API全体（HTTP経由） | モデル層、ビジネスロジック |
| プロトコル | HTTP | 直接DB接続 |
| ツール | curl/bash | Busted + pgmoon |
| 認証 | 実際のセッション | モックまたは直接DB |
| 速度 | やや低速 | 高速 |
| 範囲 | 広い（全レイヤー） | 狭い（モデルのみ） |
| 実行環境 | ホストマシン | Dockerコンテナ内 |

## カバレッジ

### テストされる層

```
┌─────────────────────────┐
│   HTTPリクエスト         │ ← E2Eテスト
├─────────────────────────┤
│   ルーティング           │
├─────────────────────────┤
│   ミドルウェア           │
│   - 認証                │
│   - CSRF                │
├─────────────────────────┤
│   コントローラー         │
├─────────────────────────┤
│   モデル                │
├─────────────────────────┤
│   データベース           │
└─────────────────────────┘
```

### テストされるコンポーネント

- ✅ Nginxルーティング
- ✅ Lapis routing
- ✅ 認証ミドルウェア
- ✅ セッション管理（Redis）
- ✅ 投稿コントローラー
- ✅ 認証コントローラー
- ✅ 投稿モデル
- ✅ ユーザーモデル
- ✅ PostgreSQLデータベース

## ベストプラクティス

1. **独立性**: 各テストは他のテストに依存しない
2. **クリーンアップ**: テストデータの削除方法を明示
3. **エラーハンドリング**: HTTPステータスコードを確認
4. **カラフルな出力**: 成功/失敗を視覚的に識別
5. **詳細なログ**: 失敗時の詳細情報を表示

## トラブルシューティング

### サービスが応答しない

```bash
# サービスの状態を確認
make status
docker-compose ps

# ログを確認
make logs-web

# ヘルスチェック
make health
curl http://localhost:8080/health
```

### 認証エラー

```bash
# Redisの状態を確認
docker-compose ps redis
make logs-redis

# Redisに接続してセッションを確認
make redis-cli
KEYS *
```

### データベースエラー

```bash
# データベースの状態を確認
make logs-db

# データベースに接続
make psql
\dt  # テーブル一覧
SELECT * FROM users LIMIT 5;
```

### Cookieファイルの問題

```bash
# Cookieファイルを削除
rm -f /tmp/luaaidiary_e2e_cookies.txt

# テストを再実行
make test-e2e
```

## 拡張のアイデア

以下の機能を追加できます：

- [ ] カテゴリーAPIのE2Eテスト
- [ ] タグAPIのE2Eテスト
- [ ] コメントAPIのE2Eテスト
- [ ] パスワード変更のE2Eテスト
- [ ] ファイルアップロードのE2Eテスト
- [ ] ページネーションのE2Eテスト
- [ ] 検索機能のE2Eテスト
- [ ] パフォーマンステスト（応答時間測定）
- [ ] 並行リクエストのテスト

## CI/CDでの使用

### GitHub Actions例

```yaml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Start services
        run: |
          cp .env.example .env
          make up
          sleep 10
      
      - name: Run E2E tests
        run: make test-e2e
      
      - name: Cleanup
        if: always()
        run: make down
```

## 参考資料

- [curl Documentation](https://curl.se/docs/)
- [Bash Testing Best Practices](https://github.com/bats-core/bats-core)
- [REST API Testing Guide](https://www.postman.com/api-testing/)
