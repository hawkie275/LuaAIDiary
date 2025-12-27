#!/bin/bash
# 管理画面ダッシュボード E2Eテスト
# 実際のHTTPリクエストで管理画面をテスト

set -e  # エラーで停止

BASE_URL="${BASE_URL:-http://localhost:8080}"
ADMIN_URL="${BASE_URL}/admin"
API_URL="${BASE_URL}/api"

# デフォルトのadminユーザー情報
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# テスト結果カウンター
TESTS_PASSED=0
TESTS_FAILED=0

# ヘルパー関数
print_section() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

print_test() {
  echo -e "${YELLOW}[TEST]${NC} $1"
}

print_pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# セッションCookieを保存
COOKIE_FILE="/tmp/luaaidiary_admin_e2e_cookies.txt"
rm -f "$COOKIE_FILE"

# クリーンアップ関数
cleanup() {
  rm -f "$COOKIE_FILE"
}

trap cleanup EXIT

echo "========================================="
echo "管理画面ダッシュボード E2Eテスト"
echo "========================================="
echo "Base URL: $BASE_URL"
echo "Admin User: $ADMIN_USER"
echo ""

# ========================================
# 1. 認証チェックテスト
# ========================================
print_section "認証チェックテスト"

# 1.1. 未認証でのアクセステスト
print_test "未認証でダッシュボードにアクセス（リダイレクトまたは401が期待される）"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/dashboard" \
  -L)  # リダイレクトを追跡

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

# 未認証の場合、401エラーまたはログインページへのリダイレクトが期待される
if [ "$http_code" -eq 401 ] || [ "$http_code" -eq 302 ] || [ "$http_code" -eq 200 ]; then
  # レスポンスにログインフォームやエラーメッセージが含まれているか確認
  if echo "$body" | grep -qi "unauthorized\|login\|認証"; then
    print_pass "未認証アクセス: 適切に拒否された"
  elif [ "$http_code" -eq 401 ]; then
    print_pass "未認証アクセス: 401エラーが返る"
  else
    # 認証なしでアクセスできる場合は警告
    print_fail "未認証アクセス: 認証なしでアクセスできてしまう"
  fi
else
  print_pass "未認証アクセス: HTTP $http_code で拒否された"
fi

# 1.2. 正常なログイン → セッション確立
print_test "管理者ユーザーでログイン"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -c "$COOKIE_FILE" \
  -b "$COOKIE_FILE" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  print_pass "ログイン成功"
else
  print_fail "ログイン失敗: HTTP $http_code - $body"
  echo "注意: ADMIN_USER と ADMIN_PASS の環境変数を確認してください"
  echo "または、以下のSQLで管理者ユーザーを作成してください:"
  echo "docker-compose exec db psql -U luaaidiary -d luaaidiary -c \"INSERT INTO users (username, email, password_hash, role) VALUES ('admin', 'admin@example.com', '\$2a\$10\$...', 'admin');\""
  exit 1
fi

# 1.3. 認証状態チェック
print_test "認証状態チェック"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/auth/me" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q "\"username\":\"$ADMIN_USER\""; then
    print_pass "認証状態確認: セッション確立済み"
  else
    print_fail "認証状態確認: ユーザー情報が一致しない"
  fi
else
  print_fail "認証状態確認: HTTP $http_code"
fi

# 1.4. CSRFトークン取得
print_test "CSRFトークン取得"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/csrf-token" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  CSRF_TOKEN=$(echo "$body" | grep -o '"csrf_token":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$CSRF_TOKEN" ]; then
    print_pass "CSRFトークン取得成功"
  else
    print_fail "CSRFトークン取得: トークンが空"
    CSRF_TOKEN=""
  fi
else
  print_fail "CSRFトークン取得: HTTP $http_code"
  CSRF_TOKEN=""
fi

# ========================================
# 2. ダッシュボードアクセステスト
# ========================================
print_section "ダッシュボードアクセステスト"

# 2.1. /admin へのアクセス（リダイレクトテスト）
print_test "GET /admin → /admin/dashboard へのリダイレクト確認"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL" \
  -b "$COOKIE_FILE" \
  --max-redirs 0)  # リダイレクトを追跡しない

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 302 ] || [ "$http_code" -eq 301 ]; then
  # Locationヘッダーを確認
  location=$(curl -s -I "$ADMIN_URL" -b "$COOKIE_FILE" | grep -i "^location:" | sed 's/location: //i' | tr -d '\r\n')
  if echo "$location" | grep -q "/admin/dashboard"; then
    print_pass "/admin リダイレクト: 正しく /admin/dashboard へリダイレクト"
  else
    print_fail "/admin リダイレクト: リダイレクト先が /admin/dashboard ではない (Location: $location)"
  fi
elif [ "$http_code" -eq 200 ]; then
  # リダイレクトなしで200が返る場合もOK（実装による）
  print_pass "/admin アクセス: HTTP 200 OK"
else
  print_fail "/admin アクセス: HTTP $http_code (302または200が期待される)"
fi

# 2.2. /admin/dashboard への直接アクセス（200 OK）
print_test "GET /admin/dashboard → 200 OK、HTMLレスポンス確認"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/dashboard" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  print_pass "ダッシュボードアクセス: HTTP 200 OK"
  
  # HTMLレスポンスであることを確認
  if echo "$body" | grep -qi "<!DOCTYPE\|<html"; then
    print_pass "ダッシュボードアクセス: HTMLレスポンス確認"
  else
    print_fail "ダッシュボードアクセス: HTMLレスポンスではない"
  fi
else
  print_fail "ダッシュボードアクセス: HTTP $http_code"
fi

# ========================================
# 3. レスポンス内容の検証
# ========================================
print_section "レスポンス内容の検証"

# 3.1. HTMLタイトルの確認
print_test "HTMLタイトルの存在確認"
if echo "$body" | grep -qi "<title>"; then
  title=$(echo "$body" | grep -i "<title>" | sed 's/<title>//i' | sed 's/<\/title>//i' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  print_pass "HTMLタイトル存在: $title"
else
  print_fail "HTMLタイトル: <title>タグが見つからない"
fi

# 3.2. ダッシュボードの主要要素確認
print_test "ダッシュボード文字列の存在確認"
if echo "$body" | grep -qi "dashboard\|ダッシュボード"; then
  print_pass "ダッシュボード文字列: 存在する"
else
  print_fail "ダッシュボード文字列: 見つからない"
fi

# 3.3. 統計情報カードの確認
print_test "統計情報の存在確認"
stat_keywords=("投稿\|posts\|記事" "カテゴリ\|categories" "タグ\|tags" "ユーザー\|users")
stats_found=0

for keyword in "${stat_keywords[@]}"; do
  if echo "$body" | grep -qi "$keyword"; then
    stats_found=$((stats_found + 1))
  fi
done

if [ $stats_found -ge 2 ]; then
  print_pass "統計情報: $stats_found 個のキーワードが見つかった"
else
  print_fail "統計情報: キーワードが少ない ($stats_found/4)"
fi

# 3.4. 最近の投稿テーブルの確認
print_test "最近の投稿セクションの存在確認"
if echo "$body" | grep -qi "recent.*post\|最近の投稿\|latest.*post"; then
  print_pass "最近の投稿セクション: 存在する"
else
  # テーブル要素の存在で確認
  if echo "$body" | grep -qi "<table"; then
    print_pass "最近の投稿セクション: テーブル要素が存在する"
  else
    print_fail "最近の投稿セクション: 見つからない"
  fi
fi

# 3.5. ナビゲーションメニューの確認
print_test "ナビゲーションメニューの存在確認"
if echo "$body" | grep -qi "<nav\|navigation\|menu\|メニュー"; then
  print_pass "ナビゲーションメニュー: 存在する"
else
  print_fail "ナビゲーションメニュー: 見つからない"
fi

# 3.6. ヘッダー・フッターの確認
print_test "ヘッダーの存在確認"
if echo "$body" | grep -qi "<header\|<head"; then
  print_pass "ヘッダー: 存在する"
else
  print_fail "ヘッダー: 見つからない"
fi

print_test "フッターの存在確認"
if echo "$body" | grep -qi "<footer"; then
  print_pass "フッター: 存在する"
else
  # フッターはオプションなので警告レベル
  print_pass "フッター: 見つからない（オプション要素）"
fi

# ========================================
# 4. 権限チェックのテスト
# ========================================
print_section "権限チェックのテスト"

# 4.1. Admin ロール（すでにログイン済み）
print_test "Admin ロール: ダッシュボードアクセス成功"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/dashboard" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)

if [ "$http_code" -eq 200 ]; then
  print_pass "Admin ロール: アクセス成功 (HTTP 200)"
else
  print_fail "Admin ロール: アクセス失敗 (HTTP $http_code)"
fi

# 4.2. Editor ロールのテスト
print_test "Editor ロール: テストユーザー作成とログイン"
EDITOR_USERNAME="e2e_editor_$(date +%s)"
EDITOR_EMAIL="${EDITOR_USERNAME}@test.com"
EDITOR_PASSWORD="EditorPass123!"

# Editorユーザー登録
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$EDITOR_USERNAME\",\"email\":\"$EDITOR_EMAIL\",\"password\":\"$EDITOR_PASSWORD\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
  # ユーザーIDを取得
  EDITOR_USER_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  
  if [ -n "$EDITOR_USER_ID" ]; then
    # データベースでロールを editor に変更
    echo "  ユーザーIDを取得: $EDITOR_USER_ID"
    echo "  ロールを editor に変更中..."
    
    # Docker環境でSQLを実行してロールを変更
    docker exec luaaidiary-db psql -U luaaidiary -d luaaidiary -c "UPDATE users SET role = 'editor' WHERE id = $EDITOR_USER_ID;" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
      echo "  ロール変更成功"
    else
      echo "  警告: ロール変更に失敗しました。docker-composeコマンドを試します..."
      docker-compose exec -T db psql -U luaaidiary -d luaaidiary -c "UPDATE users SET role = 'editor' WHERE id = $EDITOR_USER_ID;" > /dev/null 2>&1
    fi
    
    # 一時的なCookieファイル
    EDITOR_COOKIE_FILE="/tmp/luaaidiary_editor_cookies.txt"
    rm -f "$EDITOR_COOKIE_FILE"
    
    # Editorでログイン
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$API_URL/auth/login" \
      -H "Content-Type: application/json" \
      -c "$EDITOR_COOKIE_FILE" \
      -d "{\"username\":\"$EDITOR_USERNAME\",\"password\":\"$EDITOR_PASSWORD\"}")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 200 ]; then
      # ダッシュボードにアクセス（editorロールなので200が期待される）
      response=$(curl -s -w "\n%{http_code}" \
        -X GET "$ADMIN_URL/dashboard" \
        -b "$EDITOR_COOKIE_FILE")
      
      http_code=$(echo "$response" | tail -n 1)
      
      if [ "$http_code" -eq 200 ]; then
        print_pass "Editor ロール: アクセス成功 (HTTP 200)"
      else
        print_fail "Editor ロール: アクセス失敗 (HTTP $http_code、200が期待される)"
      fi
    else
      print_fail "Editor ログイン失敗: HTTP $http_code"
    fi
    
    rm -f "$EDITOR_COOKIE_FILE"
  else
    print_fail "Editorユーザー作成: ユーザーIDを取得できませんでした"
  fi
else
  print_fail "Editorユーザー登録失敗: HTTP $http_code - $body"
fi

# 4.3. Author ロールのテスト（403エラー期待）
print_test "Author ロール: テストユーザー作成とログイン"
AUTHOR_USERNAME="e2e_author_$(date +%s)"
AUTHOR_EMAIL="${AUTHOR_USERNAME}@test.com"
AUTHOR_PASSWORD="AuthorPass123!"

# Authorユーザー登録（デフォルトロールが author の場合）
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$AUTHOR_USERNAME\",\"email\":\"$AUTHOR_EMAIL\",\"password\":\"$AUTHOR_PASSWORD\"}")

http_code=$(echo "$response" | tail -n 1)

if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
  AUTHOR_COOKIE_FILE="/tmp/luaaidiary_author_cookies.txt"
  rm -f "$AUTHOR_COOKIE_FILE"
  
  # Authorでログイン
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/auth/login" \
    -H "Content-Type: application/json" \
    -c "$AUTHOR_COOKIE_FILE" \
    -d "{\"username\":\"$AUTHOR_USERNAME\",\"password\":\"$AUTHOR_PASSWORD\"}")
  
  http_code=$(echo "$response" | tail -n 1)
  
  if [ "$http_code" -eq 200 ]; then
    # ダッシュボードにアクセス（403エラー期待）
    response=$(curl -s -w "\n%{http_code}" \
      -X GET "$ADMIN_URL/dashboard" \
      -b "$AUTHOR_COOKIE_FILE")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 403 ]; then
      print_pass "Author ロール: 正しく403エラーが返る"
    elif [ "$http_code" -eq 200 ]; then
      print_fail "Author ロール: アクセスできてしまう (403が期待される)"
    else
      print_fail "Author ロール: HTTP $http_code (403が期待される)"
    fi
  else
    print_fail "Author ログイン失敗: HTTP $http_code"
  fi
  
  rm -f "$AUTHOR_COOKIE_FILE"
else
  print_fail "Authorユーザー登録失敗: HTTP $http_code"
fi

# 4.4. Subscriber ロールのテスト（403エラー期待）
print_test "Subscriber ロール: テストユーザー作成とログイン"
SUBSCRIBER_USERNAME="e2e_subscriber_$(date +%s)"
SUBSCRIBER_EMAIL="${SUBSCRIBER_USERNAME}@test.com"
SUBSCRIBER_PASSWORD="SubscriberPass123!"

# Subscriberユーザー登録
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$SUBSCRIBER_USERNAME\",\"email\":\"$SUBSCRIBER_EMAIL\",\"password\":\"$SUBSCRIBER_PASSWORD\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
  SUBSCRIBER_USER_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  
  if [ -n "$SUBSCRIBER_USER_ID" ]; then
    echo "  ユーザーIDを取得: $SUBSCRIBER_USER_ID"
    echo "  ロールを subscriber に変更中..."
    
    # Docker環境でSQLを実行してロールを変更
    docker exec luaaidiary-db psql -U luaaidiary -d luaaidiary -c "UPDATE users SET role = 'subscriber' WHERE id = $SUBSCRIBER_USER_ID;" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
      echo "  ロール変更成功"
    else
      echo "  警告: ロール変更に失敗しました。docker-composeコマンドを試します..."
      docker-compose exec -T db psql -U luaaidiary -d luaaidiary -c "UPDATE users SET role = 'subscriber' WHERE id = $SUBSCRIBER_USER_ID;" > /dev/null 2>&1
    fi
    
    SUBSCRIBER_COOKIE_FILE="/tmp/luaaidiary_subscriber_cookies.txt"
    rm -f "$SUBSCRIBER_COOKIE_FILE"
    
    # Subscriberでログイン
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$API_URL/auth/login" \
      -H "Content-Type: application/json" \
      -c "$SUBSCRIBER_COOKIE_FILE" \
      -d "{\"username\":\"$SUBSCRIBER_USERNAME\",\"password\":\"$SUBSCRIBER_PASSWORD\"}")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 200 ]; then
      # ダッシュボードにアクセス（subscriberロールなので403が期待される）
      response=$(curl -s -w "\n%{http_code}" \
        -X GET "$ADMIN_URL/dashboard" \
        -b "$SUBSCRIBER_COOKIE_FILE")
      
      http_code=$(echo "$response" | tail -n 1)
      
      if [ "$http_code" -eq 403 ]; then
        print_pass "Subscriber ロール: 正しく403エラーが返る"
      else
        print_fail "Subscriber ロール: HTTP $http_code (403が期待される)"
      fi
    else
      print_fail "Subscriber ログイン失敗: HTTP $http_code"
    fi
    
    rm -f "$SUBSCRIBER_COOKIE_FILE"
  else
    print_fail "Subscriberユーザー作成: ユーザーIDを取得できませんでした"
  fi
else
  print_fail "Subscriberユーザー登録失敗: HTTP $http_code - $body"
fi

# ========================================
# 5. ログアウトテスト
# ========================================
print_section "ログアウトテスト"

# 元の管理者セッションに戻る
print_test "ログアウト → セッション破棄確認"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/logout" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)

if [ "$http_code" -eq 200 ]; then
  print_pass "ログアウト成功"
  
  # ログアウト後のアクセステスト
  print_test "ログアウト後のダッシュボードアクセス（401が期待される）"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/dashboard" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  
  if [ "$http_code" -eq 401 ] || [ "$http_code" -eq 302 ]; then
    print_pass "ログアウト後アクセス: 正しく拒否された (HTTP $http_code)"
  else
    print_fail "ログアウト後アクセス: HTTP $http_code (401または302が期待される)"
  fi
else
  print_fail "ログアウト失敗: HTTP $http_code"
fi

# ========================================
# クリーンアップ
# ========================================
print_section "クリーンアップ"

print_test "テストユーザーのクリーンアップ情報"
echo ""
echo "  以下のテストユーザーが作成されました:"
echo "  - Editor: $EDITOR_USERNAME ($EDITOR_EMAIL)"
echo "  - Author: $AUTHOR_USERNAME ($AUTHOR_EMAIL)"
echo "  - Subscriber: $SUBSCRIBER_USERNAME ($SUBSCRIBER_EMAIL)"
echo ""
echo "  注: テスト後、以下のSQLでテストユーザーを削除してください:"
echo "  docker-compose exec db psql -U luaaidiary -d luaaidiary -c \"DELETE FROM users WHERE username IN ('$EDITOR_USERNAME', '$AUTHOR_USERNAME', '$SUBSCRIBER_USERNAME');\""
echo ""
print_pass "テストユーザー情報を表示（手動削除を推奨）"

# ========================================
# テスト結果サマリー
# ========================================
echo ""
echo "========================================="
echo "テスト結果"
echo "========================================="
echo -e "${GREEN}成功: $TESTS_PASSED${NC}"
echo -e "${RED}失敗: $TESTS_FAILED${NC}"
echo "合計: $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo -e "${GREEN}✓ すべてのテストが成功しました！${NC}"
  exit 0
else
  echo -e "${RED}✗ $TESTS_FAILED 件のテストが失敗しました${NC}"
  exit 1
fi
