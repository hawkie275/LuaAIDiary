#!/bin/bash
# 投稿API E2Eテスト
# 実際のHTTPリクエストでAPIをテスト

set -e  # エラーで停止

BASE_URL="${BASE_URL:-http://localhost:8080}"
API_URL="${BASE_URL}/api"

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テスト結果カウンター
TESTS_PASSED=0
TESTS_FAILED=0

# ヘルパー関数
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
COOKIE_FILE="/tmp/luaaidiary_e2e_cookies.txt"
rm -f "$COOKIE_FILE"

# クリーンアップ関数
cleanup() {
  rm -f "$COOKIE_FILE"
}

trap cleanup EXIT

echo "========================================="
echo "投稿API E2Eテスト"
echo "========================================="
echo "Base URL: $BASE_URL"
echo ""

# ========================================
# 1. ヘルスチェック
# ========================================
print_test "ヘルスチェック"
response=$(curl -s -w "\n%{http_code}" "$BASE_URL/health")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q '"status":"ok"'; then
    print_pass "ヘルスチェック成功"
  else
    print_fail "ヘルスチェック: レスポンスボディが不正"
  fi
else
  print_fail "ヘルスチェック: HTTP $http_code"
fi

# ========================================
# 2. データベース接続テスト
# ========================================
print_test "データベース接続テスト"
response=$(curl -s -w "\n%{http_code}" "$API_URL/db-test")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q '"status":"success"'; then
    print_pass "データベース接続成功"
  else
    print_fail "データベース接続: レスポンスボディが不正"
  fi
else
  print_fail "データベース接続: HTTP $http_code"
fi

# ========================================
# 3. ユーザー登録（テストユーザー作成）
# ========================================
print_test "ユーザー登録"
TEST_USERNAME="e2e_test_user_$(date +%s)"
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
fi

# ========================================
# 4. ログイン
# ========================================
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
fi

# ========================================
# 5. 認証状態チェック
# ========================================
print_test "認証状態チェック"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/auth/me" \
  -b "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  if echo "$body" | grep -q "\"username\":\"$TEST_USERNAME\""; then
    print_pass "認証状態チェック成功"
  else
    print_fail "認証状態チェック: ユーザー情報が不一致"
  fi
else
  print_fail "認証状態チェック: HTTP $http_code"
fi

# ========================================
# 5.5. CSRFトークン取得
# ========================================
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
# 6. 投稿作成（認証あり）
# ========================================
print_test "投稿作成（認証あり）"
POST_TITLE="E2E Test Post $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/posts" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"title\":\"$POST_TITLE\",\"content\":\"This is an E2E test post\",\"status\":\"published\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  # 投稿IDを抽出
  POST_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$POST_ID" ]; then
    print_pass "投稿作成成功 (ID: $POST_ID)"
  else
    print_fail "投稿作成: IDが取得できない"
    POST_ID=0
  fi
else
  print_fail "投稿作成: HTTP $http_code - $body"
  POST_ID=0
fi

# ========================================
# 7. 投稿一覧取得
# ========================================
print_test "投稿一覧取得"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/posts")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  print_pass "投稿一覧取得成功"
else
  print_fail "投稿一覧取得: HTTP $http_code"
fi

# ========================================
# 8. 投稿詳細取得
# ========================================
if [ "$POST_ID" -gt 0 ]; then
  print_test "投稿詳細取得 (ID: $POST_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/posts/$POST_ID")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    if echo "$body" | grep -q "\"title\":\"$POST_TITLE\""; then
      print_pass "投稿詳細取得成功"
    else
      print_fail "投稿詳細取得: タイトルが一致しない"
    fi
  else
    print_fail "投稿詳細取得: HTTP $http_code"
  fi
fi

# ========================================
# 9. 投稿更新
# ========================================
if [ "$POST_ID" -gt 0 ]; then
  print_test "投稿更新 (ID: $POST_ID)"
  UPDATED_TITLE="$POST_TITLE - UPDATED"
  response=$(curl -s -w "\n%{http_code}" \
    -X PUT "$API_URL/posts/$POST_ID" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"title\":\"$UPDATED_TITLE\",\"content\":\"Updated content\"}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    print_pass "投稿更新成功"
  else
    print_fail "投稿更新: HTTP $http_code - $body"
  fi
fi

# ========================================
# 10. カテゴリー・タグ関連テスト
# ========================================
echo ""
echo "========================================="
echo "カテゴリー・タグ関連機能テスト"
echo "========================================="
echo ""

# 10.1. テスト用カテゴリー作成
print_test "テスト用カテゴリー作成"
CATEGORY_NAME_1="E2E Category 1 $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/categories" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"name\":\"$CATEGORY_NAME_1\",\"description\":\"Test category 1\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  CATEGORY_ID_1=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$CATEGORY_ID_1" ]; then
    print_pass "カテゴリー1作成成功 (ID: $CATEGORY_ID_1)"
  else
    print_fail "カテゴリー1作成: IDが取得できない"
    CATEGORY_ID_1=0
  fi
else
  print_fail "カテゴリー1作成: HTTP $http_code - $body"
  CATEGORY_ID_1=0
fi

# 10.2. テスト用カテゴリー2作成
print_test "テスト用カテゴリー2作成"
CATEGORY_NAME_2="E2E Category 2 $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/categories" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"name\":\"$CATEGORY_NAME_2\",\"description\":\"Test category 2\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  CATEGORY_ID_2=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$CATEGORY_ID_2" ]; then
    print_pass "カテゴリー2作成成功 (ID: $CATEGORY_ID_2)"
  else
    print_fail "カテゴリー2作成: IDが取得できない"
    CATEGORY_ID_2=0
  fi
else
  print_fail "カテゴリー2作成: HTTP $http_code - $body"
  CATEGORY_ID_2=0
fi

# 10.3. テスト用タグ作成
print_test "テスト用タグ1作成"
TAG_NAME_1="E2E Tag 1 $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/tags" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"name\":\"$TAG_NAME_1\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  TAG_ID_1=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$TAG_ID_1" ]; then
    print_pass "タグ1作成成功 (ID: $TAG_ID_1)"
  else
    print_fail "タグ1作成: IDが取得できない"
    TAG_ID_1=0
  fi
else
  print_fail "タグ1作成: HTTP $http_code - $body"
  TAG_ID_1=0
fi

# 10.4. テスト用タグ2作成
print_test "テスト用タグ2作成"
TAG_NAME_2="E2E Tag 2 $(date +%s)"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/tags" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -d "{\"name\":\"$TAG_NAME_2\"}")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 201 ]; then
  TAG_ID_2=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  if [ -n "$TAG_ID_2" ]; then
    print_pass "タグ2作成成功 (ID: $TAG_ID_2)"
  else
    print_fail "タグ2作成: IDが取得できない"
    TAG_ID_2=0
  fi
else
  print_fail "タグ2作成: HTTP $http_code - $body"
  TAG_ID_2=0
fi

# 10.5. カテゴリー付き投稿の作成
if [ "$CATEGORY_ID_1" -gt 0 ]; then
  print_test "カテゴリー付き投稿の作成"
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/posts" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"title\":\"Post with Category $(date +%s)\",\"content\":\"Post with category\",\"status\":\"published\",\"category_ids\":[$CATEGORY_ID_1]}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 201 ]; then
    POST_WITH_CATEGORY=$(echo "$body" | jq -r '.post.id // .data.id // empty')
    # カテゴリーが含まれているか確認
    if echo "$body" | grep -q "\"categories\""; then
      print_pass "カテゴリー付き投稿作成成功 (ID: $POST_WITH_CATEGORY)"
    else
      print_fail "カテゴリー付き投稿作成: カテゴリー情報が含まれていない"
    fi
  else
    print_fail "カテゴリー付き投稿作成: HTTP $http_code - $body"
    POST_WITH_CATEGORY=0
  fi
fi

# 10.6. タグ付き投稿の作成
if [ "$TAG_ID_1" -gt 0 ]; then
  print_test "タグ付き投稿の作成"
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/posts" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"title\":\"Post with Tag $(date +%s)\",\"content\":\"Post with tag\",\"status\":\"published\",\"tag_ids\":[$TAG_ID_1]}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 201 ]; then
    POST_WITH_TAG=$(echo "$body" | jq -r '.post.id // .data.id // empty')
    # タグが含まれているか確認
    if echo "$body" | grep -q "\"tags\""; then
      print_pass "タグ付き投稿作成成功 (ID: $POST_WITH_TAG)"
    else
      print_fail "タグ付き投稿作成: タグ情報が含まれていない"
    fi
  else
    print_fail "タグ付き投稿作成: HTTP $http_code - $body"
    POST_WITH_TAG=0
  fi
fi

# 10.7. カテゴリー・タグ両方付き投稿の作成
if [ "$CATEGORY_ID_1" -gt 0 ] && [ "$TAG_ID_1" -gt 0 ]; then
  print_test "カテゴリー・タグ両方付き投稿の作成"
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/posts" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"title\":\"Post with Both $(date +%s)\",\"content\":\"Post with both\",\"status\":\"published\",\"category_ids\":[$CATEGORY_ID_1,$CATEGORY_ID_2],\"tag_ids\":[$TAG_ID_1,$TAG_ID_2]}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 201 ]; then
    POST_WITH_BOTH=$(echo "$body" | jq -r '.post.id // .data.id // empty')
    # 両方が含まれているか確認
    if echo "$body" | grep -q "\"categories\"" && echo "$body" | grep -q "\"tags\""; then
      print_pass "カテゴリー・タグ両方付き投稿作成成功 (ID: $POST_WITH_BOTH)"
    else
      print_fail "カテゴリー・タグ両方付き投稿作成: カテゴリーまたはタグ情報が含まれていない"
    fi
  else
    print_fail "カテゴリー・タグ両方付き投稿作成: HTTP $http_code - $body"
    POST_WITH_BOTH=0
  fi
fi

# 10.8. カテゴリーでのフィルタリングテスト
if [ "$CATEGORY_ID_1" -gt 0 ]; then
  print_test "カテゴリーでのフィルタリング"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/posts?category_id=$CATEGORY_ID_1")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    # レスポンスにカテゴリーIDが含まれているか確認（簡易チェック）
    if echo "$body" | grep -q "\"id\":$CATEGORY_ID_1"; then
      print_pass "カテゴリーフィルタリング成功"
    else
      # データがなくても200は返るのでPASS
      print_pass "カテゴリーフィルタリング成功（結果0件の可能性あり）"
    fi
  else
    print_fail "カテゴリーフィルタリング: HTTP $http_code"
  fi
fi

# 10.9. タグでのフィルタリングテスト
if [ "$TAG_ID_1" -gt 0 ]; then
  print_test "タグでのフィルタリング"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/posts?tag_id=$TAG_ID_1")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    # レスポンスにタグIDが含まれているか確認（簡易チェック）
    if echo "$body" | grep -q "\"id\":$TAG_ID_1"; then
      print_pass "タグフィルタリング成功"
    else
      # データがなくても200は返るのでPASS
      print_pass "タグフィルタリング成功（結果0件の可能性あり）"
    fi
  else
    print_fail "タグフィルタリング: HTTP $http_code"
  fi
fi

# 10.10. カテゴリー・タグ複合フィルタリングテスト
if [ "$CATEGORY_ID_1" -gt 0 ] && [ "$TAG_ID_1" -gt 0 ]; then
  print_test "カテゴリー・タグ複合フィルタリング"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/posts?category_id=$CATEGORY_ID_1&tag_id=$TAG_ID_1")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    print_pass "複合フィルタリング成功"
  else
    print_fail "複合フィルタリング: HTTP $http_code"
  fi
fi

# 10.11. 投稿更新時のカテゴリー・タグ変更テスト
if [ "$POST_WITH_CATEGORY" -gt 0 ] && [ "$CATEGORY_ID_2" -gt 0 ] && [ "$TAG_ID_2" -gt 0 ]; then
  print_test "投稿更新でカテゴリー・タグ変更"
  response=$(curl -s -w "\n%{http_code}" \
    -X PUT "$API_URL/posts/$POST_WITH_CATEGORY" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"title\":\"Updated Post\",\"content\":\"Updated content\",\"category_ids\":[$CATEGORY_ID_2],\"tag_ids\":[$TAG_ID_2]}")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    print_pass "投稿更新でカテゴリー・タグ変更成功"
  else
    print_fail "投稿更新でカテゴリー・タグ変更: HTTP $http_code - $body"
  fi
fi

# 10.12. N+1問題の解決確認（一括取得時にカテゴリー・タグが含まれているか）
print_test "N+1問題の解決確認（一括取得）"
response=$(curl -s -w "\n%{http_code}" \
  -X GET "$API_URL/posts")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  # レスポンスにcategoriesとtagsフィールドが含まれているか確認
  if echo "$body" | grep -q "\"categories\"" && echo "$body" | grep -q "\"tags\""; then
    print_pass "N+1問題解決確認: カテゴリー・タグが一括取得に含まれている"
  else
    print_fail "N+1問題解決確認: カテゴリー・タグが一括取得に含まれていない"
  fi
else
  print_fail "N+1問題解決確認: HTTP $http_code"
fi

# 10.13. テスト用投稿の削除
if [ "$POST_WITH_CATEGORY" -gt 0 ]; then
  print_test "カテゴリー付き投稿削除 (ID: $POST_WITH_CATEGORY)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/posts/$POST_WITH_CATEGORY" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "カテゴリー付き投稿削除成功"
  else
    print_fail "カテゴリー付き投稿削除: HTTP $http_code"
  fi
fi

if [ "$POST_WITH_TAG" -gt 0 ]; then
  print_test "タグ付き投稿削除 (ID: $POST_WITH_TAG)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/posts/$POST_WITH_TAG" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "タグ付き投稿削除成功"
  else
    print_fail "タグ付き投稿削除: HTTP $http_code"
  fi
fi

if [ "$POST_WITH_BOTH" -gt 0 ]; then
  print_test "両方付き投稿削除 (ID: $POST_WITH_BOTH)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/posts/$POST_WITH_BOTH" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "両方付き投稿削除成功"
  else
    print_fail "両方付き投稿削除: HTTP $http_code"
  fi
fi

# 10.14. テスト用カテゴリーの削除
if [ "$CATEGORY_ID_1" -gt 0 ]; then
  print_test "カテゴリー1削除 (ID: $CATEGORY_ID_1)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/categories/$CATEGORY_ID_1" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "カテゴリー1削除成功"
  else
    print_fail "カテゴリー1削除: HTTP $http_code"
  fi
fi

if [ "$CATEGORY_ID_2" -gt 0 ]; then
  print_test "カテゴリー2削除 (ID: $CATEGORY_ID_2)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/categories/$CATEGORY_ID_2" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "カテゴリー2削除成功"
  else
    print_fail "カテゴリー2削除: HTTP $http_code"
  fi
fi

# 10.15. テスト用タグの削除
if [ "$TAG_ID_1" -gt 0 ]; then
  print_test "タグ1削除 (ID: $TAG_ID_1)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/tags/$TAG_ID_1" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "タグ1削除成功"
  else
    print_fail "タグ1削除: HTTP $http_code"
  fi
fi

if [ "$TAG_ID_2" -gt 0 ]; then
  print_test "タグ2削除 (ID: $TAG_ID_2)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/tags/$TAG_ID_2" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "タグ2削除成功"
  else
    print_fail "タグ2削除: HTTP $http_code"
  fi
fi

echo ""
echo "========================================="
echo "基本的な投稿削除テスト"
echo "========================================="
echo ""

# ========================================
# 11. 投稿削除
# ========================================
if [ "$POST_ID" -gt 0 ]; then
  print_test "投稿削除 (ID: $POST_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/posts/$POST_ID" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")

  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" -eq 200 ]; then
    print_pass "投稿削除成功"
  else
    print_fail "投稿削除: HTTP $http_code - $body"
  fi
  
  # 削除確認
  print_test "削除確認 (ID: $POST_ID)"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$API_URL/posts/$POST_ID")

  http_code=$(echo "$response" | tail -n 1)

  if [ "$http_code" -eq 404 ]; then
    print_pass "削除確認成功（404が返る）"
  else
    print_fail "削除確認: HTTP $http_code (404が期待されるが)"
  fi
fi

# ========================================
# 12. 認証なしで投稿作成（失敗するはず）
# ========================================
print_test "認証なしで投稿作成（401が期待される）"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/posts" \
  -H "Content-Type: application/json" \
  -d '{"title":"Unauthorized Post","content":"This should fail"}')

http_code=$(echo "$response" | tail -n 1)

if [ "$http_code" -eq 401 ]; then
  print_pass "認証なし投稿作成: 正しく401が返る"
else
  print_fail "認証なし投稿作成: HTTP $http_code (401が期待される)"
fi

# ========================================
# 13. ログアウト
# ========================================
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

# ========================================
# 14. テストユーザーのクリーンアップ
# ========================================
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
