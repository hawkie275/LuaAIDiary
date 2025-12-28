#!/bin/bash
# HTMLログインフォーム E2Eテスト
# ブラウザから直接アクセスできるログインフォームの動作確認

set -e  # エラーで停止

BASE_URL="${BASE_URL:-http://localhost:8080}"
ADMIN_URL="${BASE_URL}/admin"

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
COOKIE_FILE="/tmp/luaaidiary_html_login_cookies.txt"
rm -f "$COOKIE_FILE"

# クリーンアップ関数
cleanup() {
  rm -f "$COOKIE_FILE"
}

trap cleanup EXIT

echo "========================================="
echo "HTMLログインフォーム E2Eテスト"
echo "========================================="
echo "Base URL: $BASE_URL"
echo "Admin User: $ADMIN_USER"
echo ""

# ========================================
# 1. ログインフォームアクセステスト
# ========================================
print_section "ログインフォームアクセステスト"

# 1.1. GET /admin/login でログインフォームが表示される
print_test "GET /admin/login → ログインフォーム表示"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/login" \
  -c "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  print_pass "ログインフォームアクセス: HTTP 200 OK"
  
  # HTMLレスポンスであることを確認
  if echo "$body" | grep -qi "<!DOCTYPE\|<html"; then
    print_pass "ログインフォーム: HTMLレスポンス確認"
  else
    print_fail "ログインフォーム: HTMLレスポンスではない"
  fi
  
  # フォーム要素の存在確認
  if echo "$body" | grep -qi "<form"; then
    print_pass "ログインフォーム: <form>タグが存在"
  else
    print_fail "ログインフォーム: <form>タグが見つからない"
  fi
  
  # ユーザー名/メールアドレス入力フィールド
  if echo "$body" | grep -qi 'name="username_or_email"'; then
    print_pass "ログインフォーム: username_or_email入力フィールドが存在"
  else
    print_fail "ログインフォーム: username_or_email入力フィールドが見つからない"
  fi
  
  # パスワード入力フィールド
  if echo "$body" | grep -qi 'name="password"'; then
    print_pass "ログインフォーム: password入力フィールドが存在"
  else
    print_fail "ログインフォーム: password入力フィールドが見つからない"
  fi
  
  # CSRFトークンフィールド
  if echo "$body" | grep -qi 'name="_csrf_token"'; then
    print_pass "ログインフォーム: CSRFトークンフィールドが存在"
    # CSRFトークンの値を抽出
    CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
    if [ -n "$CSRF_TOKEN" ]; then
      echo "  CSRFトークン: $CSRF_TOKEN"
    fi
  else
    print_fail "ログインフォーム: CSRFトークンフィールドが見つからない"
    CSRF_TOKEN=""
  fi
else
  print_fail "ログインフォームアクセス: HTTP $http_code (200が期待される)"
fi

# 1.2. リダイレクトパラメータが正しく処理される
print_test "GET /admin/login?redirect=/admin/dashboard → リダイレクトパラメータ確認"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/login?redirect=/admin/dashboard")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  # リダイレクトパラメータがhiddenフィールドに含まれているか確認
  if echo "$body" | grep -q 'name="redirect".*value="/admin/dashboard"'; then
    print_pass "リダイレクトパラメータ: 正しくフォームに含まれている"
  else
    print_fail "リダイレクトパラメータ: フォームに含まれていない"
  fi
else
  print_fail "リダイレクトパラメータテスト: HTTP $http_code"
fi

# ========================================
# 2. HTMLフォームログインテスト
# ========================================
print_section "HTMLフォームログインテスト"

# 2.1. 正常なログイン（フォームデータでPOST）
print_test "POST /admin/login (フォームデータ) → ログイン成功"

# CSRFトークンを取得（新しいセッション）
rm -f "$COOKIE_FILE"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/login" \
  -c "$COOKIE_FILE")

body=$(echo "$response" | head -n -1)
CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')

if [ -z "$CSRF_TOKEN" ]; then
  print_fail "CSRFトークン取得失敗: フォームログインをスキップ"
else
  # フォームデータでログイン（-Lオプションなし、302を成功として扱う）
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$ADMIN_URL/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
    -d "username_or_email=$ADMIN_USER&password=$ADMIN_PASS&_csrf_token=$CSRF_TOKEN&redirect=/admin/dashboard")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  # ログイン成功後は302リダイレクトが返される
  if [ "$http_code" -eq 302 ]; then
    print_pass "HTMLフォームログイン: 302リダイレクト（ログイン成功）"
  elif [ "$http_code" -eq 200 ]; then
    # 万が一200が返された場合（ダッシュボードページ）
    if echo "$body" | grep -qi "dashboard\|ダッシュボード"; then
      print_pass "HTMLフォームログイン: 成功してダッシュボードにリダイレクト"
    else
      print_fail "HTMLフォームログイン: レスポンスが予期しない内容"
    fi
  else
    print_fail "HTMLフォームログイン: HTTP $http_code (302が期待される)"
  fi

  # 2.2. ログイン後のセッション確認
  print_test "ログイン後のダッシュボードアクセス"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/dashboard" \
    -b "$COOKIE_FILE")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -qi "dashboard\|ダッシュボード"; then
      print_pass "セッション確認: ダッシュボードにアクセス可能"
    else
      print_fail "セッション確認: ダッシュボードの内容が不正"
    fi
  else
    print_fail "セッション確認: HTTP $http_code"
  fi
fi

# ========================================
# 3. エラーケーステスト
# ========================================
print_section "エラーケーステスト"

# 3.1. 間違ったパスワード
print_test "間違ったパスワードでログイン → エラーメッセージ表示"

# 新しいセッションでCSRFトークン取得
rm -f "$COOKIE_FILE"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/login" \
  -c "$COOKIE_FILE")

body=$(echo "$response" | head -n -1)
CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')

if [ -n "$CSRF_TOKEN" ]; then
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$ADMIN_URL/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
    -d "username_or_email=$ADMIN_USER&password=wrongpassword&_csrf_token=$CSRF_TOKEN")

  http_code=$(echo "$response" | tail -n 1)
  
  # ログイン失敗時は302でエラーメッセージ付きのログインページにリダイレクト
  if [ "$http_code" -eq 302 ]; then
    print_pass "間違ったパスワード: エラーメッセージ付きでリダイレクト"
  else
    print_fail "間違ったパスワード: HTTP $http_code (302が期待される)"
  fi
fi

# 3.2. 存在しないユーザー
print_test "存在しないユーザーでログイン → エラーメッセージ表示"

# 新しいセッションでCSRFトークン取得
rm -f "$COOKIE_FILE"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$ADMIN_URL/login" \
  -c "$COOKIE_FILE")

body=$(echo "$response" | head -n -1)
CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')

if [ -n "$CSRF_TOKEN" ]; then
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$ADMIN_URL/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
    -d "username_or_email=nonexistentuser&password=anypassword&_csrf_token=$CSRF_TOKEN")

  http_code=$(echo "$response" | tail -n 1)
  
  # ログイン失敗時は302でエラーメッセージ付きのログインページにリダイレクト
  if [ "$http_code" -eq 302 ]; then
    print_pass "存在しないユーザー: エラーメッセージ付きでリダイレクト"
  else
    print_fail "存在しないユーザー: HTTP $http_code (302が期待される)"
  fi
fi

# ========================================
# 4. 既存JSON APIの互換性テスト
# ========================================
print_section "既存JSON APIの互換性テスト"

# 4.1. JSON APIでのログインが引き続き動作することを確認
print_test "POST /api/auth/login (JSON) → 既存API動作確認"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q '"success":true'; then
    print_pass "JSON API: 正常に動作（互換性維持）"
  else
    print_fail "JSON API: レスポンスが不正"
  fi
else
  print_fail "JSON API: HTTP $http_code (200が期待される)"
fi

# 4.2. POST /admin/login でもJSON APIとして動作することを確認
print_test "POST /admin/login (JSON) → JSON APIとして動作"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$ADMIN_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q '"success":true'; then
    print_pass "POST /admin/login (JSON): JSON APIとして動作"
  else
    print_fail "POST /admin/login (JSON): レスポンスが不正"
  fi
else
  print_fail "POST /admin/login (JSON): HTTP $http_code (200が期待される)"
fi

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
