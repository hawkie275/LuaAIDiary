#!/bin/bash
# カテゴリー・タグ管理API E2Eテスト
# 実際のHTTPリクエストでAPIをテスト

set -e  # エラーで停止

BASE_URL="${BASE_URL:-http://localhost:8080}"
API_URL="${BASE_URL}/api"

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
COOKIE_FILE="/tmp/luaaidiary_category_tag_e2e_cookies.txt"
rm -f "$COOKIE_FILE"

# クリーンアップ関数
cleanup() {
  rm -f "$COOKIE_FILE"
}

trap cleanup EXIT

echo "========================================="
echo "カテゴリー・タグ管理API E2Eテスト"
echo "========================================="
echo "Base URL: $BASE_URL"
echo ""

# ========================================
# セットアップ: ユーザー登録とログイン
# ========================================
print_section "セットアップ"

print_test "ユーザー登録"
TEST_USERNAME="e2e_cat_tag_user_$(date +%s)"
TEST_EMAIL="${TEST_USERNAME}@test.com"
TEST_PASSWORD="TestPass123!"

response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -c "$COOKIE_FILE" \
  -d "{\"username\":\"$TEST_USERNAME\",\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
  print_pass "ユーザー登録成功"
else
  print_fail "ユーザー登録: HTTP $http_code - $body"
  exit 1
fi

print_test "ログイン"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -c "$COOKIE_FILE" \
  -b "$COOKIE_FILE" \
  -d "{\"username\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  print_pass "ログイン成功"
else
  print_fail "ログイン: HTTP $http_code - $body"
  exit 1
fi

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
    exit 1
  fi
else
  print_fail "CSRFトークン取得: HTTP $http_code"
  exit 1
fi

# ========================================
# カテゴリーAPIテスト
# ========================================
print_section "カテゴリーAPIテスト"

# 1. カテゴリー一覧取得（認証不要）
print_test "カテゴリー一覧取得（認証不要）"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/categories")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q '"success":true'; then
    print_pass "カテゴリー一覧取得成功"
  else
    print_fail "カテゴリー一覧取得: successフィールドが不正"
  fi
else
  print_fail "カテゴリー一覧取得: HTTP $http_code"
fi

# 2. カテゴリー作成（認証必須、CSRF保護）
print_test "カテゴリー作成（認証あり、CSRFトークンあり）"
CATEGORY_NAME="E2E Test Category $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/categories" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"name\":\"$CATEGORY_NAME\",\"description\":\"Test category description\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  CATEGORY_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$CATEGORY_ID" ]; then
    print_pass "カテゴリー作成成功 (ID: $CATEGORY_ID)"
  else
    print_fail "カテゴリー作成: IDが取得できない"
    CATEGORY_ID=0
  fi
else
  print_fail "カテゴリー作成: HTTP $http_code - $body"
  CATEGORY_ID=0
fi

# 3. 特定カテゴリー取得
if [ "$CATEGORY_ID" -gt 0 ]; then
  print_test "特定カテゴリー取得 (ID: $CATEGORY_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/categories/$CATEGORY_ID")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q "\"name\":\"$CATEGORY_NAME\""; then
      print_pass "特定カテゴリー取得成功"
    else
      print_fail "特定カテゴリー取得: 名前が一致しない"
    fi
  else
    print_fail "特定カテゴリー取得: HTTP $http_code"
  fi
fi

# 4. カテゴリー更新（認証必須、CSRF保護）
if [ "$CATEGORY_ID" -gt 0 ]; then
  print_test "カテゴリー更新 (ID: $CATEGORY_ID)"
  UPDATED_CATEGORY_NAME="$CATEGORY_NAME - UPDATED"
  response=$(curl -s -w "\n%{http_code}" \
    -X PUT "$API_URL/categories/$CATEGORY_ID" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"name\":\"$UPDATED_CATEGORY_NAME\",\"description\":\"Updated description\"}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q '"success":true'; then
      print_pass "カテゴリー更新成功"
    else
      print_fail "カテゴリー更新: successフィールドが不正"
    fi
  else
    print_fail "カテゴリー更新: HTTP $http_code - $body"
  fi
fi

# 7. 認証なしでカテゴリー作成（401エラー）
print_test "認証なしでカテゴリー作成（401が期待される）"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/categories" \
  -H "Content-Type: application/json" \
  -d '{"name":"Unauthorized Category","description":"This should fail"}')

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 401 ]; then
  print_pass "認証なしカテゴリー作成: 正しく401が返る"
else
  print_fail "認証なしカテゴリー作成: HTTP $http_code (401が期待される)"
fi

# 8. CSRFトークンなしでカテゴリー作成（403エラー）
print_test "CSRFトークンなしでカテゴリー作成（403が期待される）"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/categories" \
  -H "Content-Type: application/json" \
  -b "$COOKIE_FILE" \
  -d '{"name":"No CSRF Token Category","description":"This should fail"}')

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 403 ]; then
  print_pass "CSRFトークンなしカテゴリー作成: 正しく403が返る"
else
  print_fail "CSRFトークンなしカテゴリー作成: HTTP $http_code (403が期待される)"
fi

# 9. 重複した名前でカテゴリー作成（409エラー）
if [ "$CATEGORY_ID" -gt 0 ]; then
  print_test "重複した名前でカテゴリー作成（409が期待される）"
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/categories" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"name\":\"$UPDATED_CATEGORY_NAME\",\"description\":\"Duplicate name test\"}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 409 ]; then
    print_pass "重複カテゴリー作成: 正しく409が返る"
  else
    print_fail "重複カテゴリー作成: HTTP $http_code (409が期待される)"
  fi
fi

# 5. カテゴリー削除（認証必須、CSRF保護）
if [ "$CATEGORY_ID" -gt 0 ]; then
  print_test "カテゴリー削除 (ID: $CATEGORY_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/categories/$CATEGORY_ID" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q '"success":true'; then
      print_pass "カテゴリー削除成功"
    else
      print_fail "カテゴリー削除: successフィールドが不正"
    fi
  else
    print_fail "カテゴリー削除: HTTP $http_code - $body"
  fi
  
  # 6. 削除確認（404が返ることを確認）
  print_test "削除確認 (ID: $CATEGORY_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/categories/$CATEGORY_ID")

  http_code=$(echo "$response" | tail -n 1)

  if [ "$http_code" -eq 404 ]; then
    print_pass "削除確認成功（404が返る）"
  else
    print_fail "削除確認: HTTP $http_code (404が期待されるが)"
  fi
fi

# ========================================
# タグAPIテスト
# ========================================
print_section "タグAPIテスト"

# 1. タグ一覧取得（認証不要）
print_test "タグ一覧取得（認証不要）"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/tags")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q '"success":true'; then
    print_pass "タグ一覧取得成功"
  else
    print_fail "タグ一覧取得: successフィールドが不正"
  fi
else
  print_fail "タグ一覧取得: HTTP $http_code"
fi

# 2. タグ作成（認証必須、CSRF保護）
print_test "タグ作成（認証あり、CSRFトークンあり）"
TAG_NAME="E2E Test Tag $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/tags" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"name\":\"$TAG_NAME\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  TAG_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$TAG_ID" ]; then
    print_pass "タグ作成成功 (ID: $TAG_ID)"
  else
    print_fail "タグ作成: IDが取得できない"
    TAG_ID=0
  fi
else
  print_fail "タグ作成: HTTP $http_code - $body"
  TAG_ID=0
fi

# 3. 特定タグ取得
if [ "$TAG_ID" -gt 0 ]; then
  print_test "特定タグ取得 (ID: $TAG_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/tags/$TAG_ID")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q "\"name\":\"$TAG_NAME\""; then
      print_pass "特定タグ取得成功"
    else
      print_fail "特定タグ取得: 名前が一致しない"
    fi
  else
    print_fail "特定タグ取得: HTTP $http_code"
  fi
fi

# 4. タグ更新（認証必須、CSRF保護）
if [ "$TAG_ID" -gt 0 ]; then
  print_test "タグ更新 (ID: $TAG_ID)"
  UPDATED_TAG_NAME="$TAG_NAME - UPDATED"
  response=$(curl -s -w "\n%{http_code}" \
    -X PUT "$API_URL/tags/$TAG_ID" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"name\":\"$UPDATED_TAG_NAME\"}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q '"success":true'; then
      print_pass "タグ更新成功"
    else
      print_fail "タグ更新: successフィールドが不正"
    fi
  else
    print_fail "タグ更新: HTTP $http_code - $body"
  fi
fi

# 7. 認証なしでタグ作成（401エラー）
print_test "認証なしでタグ作成（401が期待される）"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/tags" \
  -H "Content-Type: application/json" \
  -d '{"name":"Unauthorized Tag"}')

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 401 ]; then
  print_pass "認証なしタグ作成: 正しく401が返る"
else
  print_fail "認証なしタグ作成: HTTP $http_code (401が期待される)"
fi

# 8. CSRFトークンなしでタグ作成（403エラー）
print_test "CSRFトークンなしでタグ作成（403が期待される）"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/tags" \
  -H "Content-Type: application/json" \
  -b "$COOKIE_FILE" \
  -d '{"name":"No CSRF Token Tag"}')

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 403 ]; then
  print_pass "CSRFトークンなしタグ作成: 正しく403が返る"
else
  print_fail "CSRFトークンなしタグ作成: HTTP $http_code (403が期待される)"
fi

# 9. 重複した名前でタグ作成（409エラー）
if [ "$TAG_ID" -gt 0 ]; then
  print_test "重複した名前でタグ作成（409が期待される）"
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/tags" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"name\":\"$UPDATED_TAG_NAME\"}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 409 ]; then
    print_pass "重複タグ作成: 正しく409が返る"
  else
    print_fail "重複タグ作成: HTTP $http_code (409が期待される)"
  fi
fi

# 5. タグ削除（認証必須、CSRF保護）
if [ "$TAG_ID" -gt 0 ]; then
  print_test "タグ削除 (ID: $TAG_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/tags/$TAG_ID" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q '"success":true'; then
      print_pass "タグ削除成功"
    else
      print_fail "タグ削除: successフィールドが不正"
    fi
  else
    print_fail "タグ削除: HTTP $http_code - $body"
  fi
  
  # 6. 削除確認（404が返ることを確認）
  print_test "削除確認 (ID: $TAG_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/tags/$TAG_ID")

  http_code=$(echo "$response" | tail -n 1)

  if [ "$http_code" -eq 404 ]; then
    print_pass "削除確認成功（404が返る）"
  else
    print_fail "削除確認: HTTP $http_code (404が期待されるが)"
  fi
fi

# ========================================
# クリーンアップ: ログアウト
# ========================================
print_section "クリーンアップ"

print_test "ログアウト"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/logout" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)

if [ "$http_code" -eq 200 ]; then
  print_pass "ログアウト成功"
else
  print_fail "ログアウト: HTTP $http_code"
fi

print_test "テストユーザーのクリーンアップ"
echo ""
echo "  テストユーザー情報:"
echo "  ユーザー名: $TEST_USERNAME"
echo "  メールアドレス: $TEST_EMAIL"
echo ""
echo "  注: テスト後、以下のSQLでテストユーザーを削除してください:"
echo "  docker-compose exec db psql -U luaaidiary -d luaaidiary -c \"DELETE FROM users WHERE username = '$TEST_USERNAME';\""
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
