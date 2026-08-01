#!/bin/bash
# メディアAPI E2Eテスト
# 実際のHTTPリクエストでアップロード、重複検知、参照中削除ブロックを確認します。

set -e

BASE_URL="${BASE_URL:-http://localhost:8080}"
API_URL="${BASE_URL}/api"
ADMIN_USER="${ADMIN_USER:-media_e2e_admin_$(date +%s)}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"
ADMIN_EMAIL="${ADMIN_EMAIL:-${ADMIN_USER}@test.local}"
ADMIN_PASSWORD_HASH="${ADMIN_PASSWORD_HASH:-\$2b\$10\$Yt1OM2AKndiDQcVFgb5BTOPyUAmJUGnPCtkDS8ydVFlcxxQSgoPm.}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
COOKIE_FILE="/tmp/luaaidiary_media_e2e_cookies.txt"
TEST_IMAGE="/tmp/luaaidiary_media_e2e.png"
MEDIA_ID=0
POST_ID=0
ADMIN_CREATED=0
rm -f "$COOKIE_FILE" "$TEST_IMAGE"

cleanup() {
  rm -f "$COOKIE_FILE" "$TEST_IMAGE"
  if [ "$ADMIN_CREATED" -eq 1 ]; then
    docker compose exec -T db psql -U luaaidiary -d luaaidiary -v ON_ERROR_STOP=1 \
      -c "BEGIN; DELETE FROM media WHERE uploaded_by IN (SELECT id FROM users WHERE username = '$ADMIN_USER' AND email = '$ADMIN_EMAIL'); DELETE FROM users WHERE username = '$ADMIN_USER' AND email = '$ADMIN_EMAIL'; COMMIT;" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

print_test() { echo -e "${YELLOW}[TEST]${NC} $1"; }
print_pass() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

extract_json_string() {
  local key="$1"
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" | head -1
}

echo "========================================="
echo "メディアAPI E2Eテスト"
echo "========================================="
echo "Base URL: $BASE_URL"
echo ""

print_test "E2E用管理者ユーザー作成"
if docker compose exec -T db psql -U luaaidiary -d luaaidiary -v ON_ERROR_STOP=1 \
  -c "INSERT INTO users (username, email, password_hash, display_name, role) VALUES ('$ADMIN_USER', '$ADMIN_EMAIL', '$ADMIN_PASSWORD_HASH', 'Media E2E Admin', 'admin') ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, password_hash = EXCLUDED.password_hash, display_name = EXCLUDED.display_name, role = EXCLUDED.role;" >/dev/null; then
  ADMIN_CREATED=1
  print_pass "E2E用管理者ユーザー作成成功"
else
  print_fail "E2E用管理者ユーザー作成失敗"
fi

# 1x1 PNG
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=' | base64 -d > "$TEST_IMAGE"
printf 'e2e-%s' "$(date +%s%N)" >> "$TEST_IMAGE"

print_test "管理者ログイン"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -c "$COOKIE_FILE" \
  -b "$COOKIE_FILE" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)
if [ "$http_code" -eq 200 ]; then
  print_pass "管理者ログイン成功"
else
  print_fail "管理者ログイン: HTTP $http_code - $body"
fi

print_test "CSRFトークン取得"
response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/csrf-token" -b "$COOKIE_FILE")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)
if [ "$http_code" -eq 200 ]; then
  CSRF_TOKEN=$(echo "$body" | grep -o '"csrf_token":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$CSRF_TOKEN" ]; then
    print_pass "CSRFトークン取得成功"
  else
    print_fail "CSRFトークン取得: トークンが空"
  fi
else
  print_fail "CSRFトークン取得: HTTP $http_code - $body"
fi

print_test "メディアアップロード"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/media" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -F "file=@$TEST_IMAGE;type=image/png;filename=e2e-media.png")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)
if [ "$http_code" -eq 201 ]; then
  MEDIA_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  MEDIA_URL=$(echo "$body" | extract_json_string "url")
  if [ -n "$MEDIA_ID" ] && [ -n "$MEDIA_URL" ]; then
    print_pass "メディアアップロード成功 (ID: $MEDIA_ID)"
  else
    print_fail "メディアアップロード: IDまたはURLが取得できない - $body"
    MEDIA_ID=0
  fi
else
  print_fail "メディアアップロード: HTTP $http_code - $body"
  MEDIA_ID=0
fi

print_test "重複アップロード検知"
response=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/media" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b "$COOKIE_FILE" \
  -F "file=@$TEST_IMAGE;type=image/png;filename=e2e-media-duplicate.png")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)
if [ "$http_code" -eq 200 ] && echo "$body" | grep -q '"deduplicated":true'; then
  print_pass "重複アップロード検知成功"
else
  print_fail "重複アップロード検知: HTTP $http_code - $body"
fi

print_test "メディア一覧取得"
response=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/media" -b "$COOKIE_FILE")
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)
if [ "$http_code" -eq 200 ] && echo "$body" | grep -q '"items"'; then
  print_pass "メディア一覧取得成功"
else
  print_fail "メディア一覧取得: HTTP $http_code - $body"
fi

if [ "$MEDIA_ID" -gt 0 ]; then
  print_test "メディア名称変更"
  response=$(curl -s -w "\n%{http_code}" \
    -X PATCH "$API_URL/media/$MEDIA_ID" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d '{"file_name":"renamed-e2e-media.png"}')
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  if [ "$http_code" -eq 200 ] && echo "$body" | grep -q 'renamed-e2e-media.png'; then
    print_pass "メディア名称変更成功"
  else
    print_fail "メディア名称変更: HTTP $http_code - $body"
  fi

  print_test "記事本文参照による利用状況同期"
  POST_TITLE="Media E2E $(date +%s)"
  POST_CONTENT="本文 ![image]($MEDIA_URL)"
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_URL/posts" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE" \
    -d "{\"title\":\"$POST_TITLE\",\"content\":\"$POST_CONTENT\",\"status\":\"draft\"}")
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  if [ "$http_code" -eq 201 ]; then
    POST_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
    print_pass "記事本文参照による利用状況同期成功"
  else
    print_fail "記事本文参照による利用状況同期: HTTP $http_code - $body"
  fi

  print_test "参照中メディア削除ブロック"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/media/$MEDIA_ID" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  if [ "$http_code" -eq 409 ]; then
    print_pass "参照中メディア削除ブロック成功"
  else
    print_fail "参照中メディア削除ブロック: HTTP $http_code - $body"
  fi

  if [ "$POST_ID" -gt 0 ]; then
    print_test "E2E作成記事クリーンアップ"
    response=$(curl -s -w "\n%{http_code}" \
      -X DELETE "$API_URL/posts/$POST_ID" \
      -H "X-CSRF-Token: $CSRF_TOKEN" \
      -b "$COOKIE_FILE")
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | head -n -1)
    if [ "$http_code" -eq 200 ]; then
      print_pass "E2E作成記事クリーンアップ成功"
    else
      print_fail "E2E作成記事クリーンアップ: HTTP $http_code - $body"
    fi
  fi

  print_test "E2E作成メディアクリーンアップ"
  response=$(curl -s -w "\n%{http_code}" \
    -X DELETE "$API_URL/media/$MEDIA_ID" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -b "$COOKIE_FILE")
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  if [ "$http_code" -eq 200 ]; then
    print_pass "E2E作成メディアクリーンアップ成功"
  else
    print_fail "E2E作成メディアクリーンアップ: HTTP $http_code - $body"
  fi
fi

echo ""
echo "========================================="
echo "テスト結果"
echo "========================================="
echo -e "${GREEN}成功: $TESTS_PASSED${NC}"
echo -e "${RED}失敗: $TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi

exit 0
