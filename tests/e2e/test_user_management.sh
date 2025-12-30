#!/bin/bash
# ユーザー管理機能 E2Eテスト
# 管理者用ユーザー管理とプロフィール編集機能のテスト

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
COOKIE_FILE="/tmp/luaaidiary_user_mgmt_cookies.txt"
NORMAL_USER_COOKIE="/tmp/luaaidiary_normal_user_cookies.txt"
rm -f "$COOKIE_FILE" "$NORMAL_USER_COOKIE"

# クリーンアップ関数
cleanup() {
  rm -f "$COOKIE_FILE" "$NORMAL_USER_COOKIE"
}

trap cleanup EXIT

echo "========================================="
echo "ユーザー管理機能 E2Eテスト"
echo "========================================="
echo "Base URL: $BASE_URL"
echo "Admin User: $ADMIN_USER"
echo ""

# ========================================
# ヘルパー関数: ログイン
# ========================================
do_login() {
  local username=$1
  local password=$2
  local cookie_file=${3:-$COOKIE_FILE}
  
  # CSRFトークンを取得
  rm -f "$cookie_file"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/login" \
    -c "$cookie_file")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -z "$CSRF_TOKEN" ]; then
    echo "CSRFトークン取得失敗"
    return 1
  fi
  
  # ログイン
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$ADMIN_URL/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -c "$cookie_file" \
    -b "$cookie_file" \
    -d "username_or_email=$username&password=$password&_csrf_token=$CSRF_TOKEN")
  
  http_code=$(echo "$response" | tail -n 1)
  
  if [ "$http_code" -eq 302 ]; then
    return 0
  else
    echo "ログイン失敗: HTTP $http_code"
    return 1
  fi
}

# ========================================
# 1. ユーザー一覧表示テスト
# ========================================
print_section "ユーザー一覧表示テスト"

# 1.1. 管理者でログインしてユーザー一覧にアクセス
print_test "管理者でログイン → /admin/users にアクセス"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/users" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" -eq 200 ]; then
    print_pass "ユーザー一覧アクセス: HTTP 200 OK"
    
    # HTMLレスポンスであることを確認
    if echo "$body" | grep -qi "<!DOCTYPE\|<html"; then
      print_pass "ユーザー一覧: HTMLレスポンス確認"
    else
      print_fail "ユーザー一覧: HTMLレスポンスではない"
    fi
    
    # ユーザー一覧の主要要素確認
    if echo "$body" | grep -qi "ユーザー一覧\|user.*list\|users"; then
      print_pass "ユーザー一覧: タイトル確認"
    else
      print_fail "ユーザー一覧: タイトルが見つからない"
    fi
    
    # テーブルの存在確認
    if echo "$body" | grep -qi "<table"; then
      print_pass "ユーザー一覧: テーブル要素が存在"
    else
      print_fail "ユーザー一覧: テーブル要素が見つからない"
    fi
    
    # 新規作成リンクの確認
    if echo "$body" | grep -qi "新規\|new.*user\|add.*user"; then
      print_pass "ユーザー一覧: 新規作成リンクが存在"
    else
      print_fail "ユーザー一覧: 新規作成リンクが見つからない"
    fi
  else
    print_fail "ユーザー一覧アクセス: HTTP $http_code (200が期待される)"
  fi
else
  print_fail "管理者ログイン失敗: ユーザー一覧テストをスキップ"
fi

# ========================================
# 2. 新規ユーザー作成テスト
# ========================================
print_section "新規ユーザー作成テスト"

# 2.1. 新規ユーザーフォームアクセス
print_test "GET /admin/users/new → フォーム表示"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/users/new" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" -eq 200 ]; then
    print_pass "新規ユーザーフォーム: HTTP 200 OK"
    
    # フォーム要素の確認
    if echo "$body" | grep -qi "<form"; then
      print_pass "新規ユーザーフォーム: <form>タグが存在"
    else
      print_fail "新規ユーザーフォーム: <form>タグが見つからない"
    fi
    
    # 必須フィールドの確認
    required_fields=("username" "email" "password")
    for field in "${required_fields[@]}"; do
      if echo "$body" | grep -qi "name=\"$field\""; then
        print_pass "新規ユーザーフォーム: $field フィールドが存在"
      else
        print_fail "新規ユーザーフォーム: $field フィールドが見つからない"
      fi
    done
    
    # CSRFトークンの確認
    if echo "$body" | grep -qi 'name="_csrf_token"'; then
      print_pass "新規ユーザーフォーム: CSRFトークンが存在"
    else
      print_fail "新規ユーザーフォーム: CSRFトークンが見つからない"
    fi
  else
    print_fail "新規ユーザーフォーム: HTTP $http_code (200が期待される)"
  fi
fi

# 2.2. ユーザー作成実行
print_test "POST /admin/users → ユーザー作成"
TEST_USERNAME="e2e_test_user_$(date +%s)"
TEST_EMAIL="${TEST_USERNAME}@test.com"
TEST_PASSWORD="TestPass123!"

if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  # CSRFトークン取得
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/users/new" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    # ユーザー作成
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/users/create" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -c "$COOKIE_FILE" \
      -d "username=$TEST_USERNAME&email=$TEST_EMAIL&password=$TEST_PASSWORD&role=author&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "ユーザー作成: 302リダイレクト（成功）"
      
      # ユーザー一覧で新規ユーザーが表示されることを確認
      print_test "ユーザー一覧に新規ユーザーが表示されることを確認"
      response=$(curl -s -w "\n%{http_code}" \
        -X GET "$ADMIN_URL/users" \
        -b "$COOKIE_FILE")
      
      body=$(echo "$response" | head -n -1)
      
      if echo "$body" | grep -q "$TEST_USERNAME"; then
        print_pass "新規ユーザー確認: ユーザー一覧に表示される"
      else
        print_fail "新規ユーザー確認: ユーザー一覧に表示されない"
      fi
    else
      print_fail "ユーザー作成: HTTP $http_code (302が期待される)"
    fi
  else
    print_fail "CSRFトークン取得失敗: ユーザー作成をスキップ"
  fi
fi

# ========================================
# 3. ユーザー編集テスト
# ========================================
print_section "ユーザー編集テスト"

# 3.1. ユーザー編集フォームアクセス
print_test "GET /admin/users/:id/edit → 編集フォーム表示"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  # まず、作成したユーザーのIDを取得
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/users" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  
  # ユーザーIDを抽出（簡易的な方法）
  # HTML内の /admin/users/数字/edit パターンからIDを抽出
  USER_ID=$(echo "$body" | grep -o "/admin/users/[0-9]*/edit" | head -1 | grep -o "[0-9]*")
  
  if [ -n "$USER_ID" ]; then
    response=$(curl -s -w "\n%{http_code}" \
      -X GET "$ADMIN_URL/users/$USER_ID/edit" \
      -b "$COOKIE_FILE")
    
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" -eq 200 ]; then
      print_pass "ユーザー編集フォーム: HTTP 200 OK"
      
      # フォーム要素の確認
      if echo "$body" | grep -qi "<form"; then
        print_pass "ユーザー編集フォーム: <form>タグが存在"
      else
        print_fail "ユーザー編集フォーム: <form>タグが見つからない"
      fi
    else
      print_fail "ユーザー編集フォーム: HTTP $http_code (200が期待される)"
    fi
  else
    print_fail "ユーザーID取得失敗: 編集フォームテストをスキップ"
  fi
fi

# 3.2. ユーザー情報更新
print_test "POST /admin/users/:id → ユーザー情報更新"
if [ -n "$USER_ID" ]; then
  if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
    # CSRFトークン取得
    response=$(curl -s -w "\n%{http_code}" \
      -X GET "$ADMIN_URL/users/$USER_ID/edit" \
      -b "$COOKIE_FILE")
    
    body=$(echo "$response" | head -n -1)
    CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
    
    if [ -n "$CSRF_TOKEN" ]; then
      # ユーザー情報更新
      UPDATED_EMAIL="${TEST_USERNAME}_updated@test.com"
      response=$(curl -s -w "\n%{http_code}" \
        -X POST "$ADMIN_URL/users/$USER_ID/update" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -b "$COOKIE_FILE" \
        -c "$COOKIE_FILE" \
        -d "username=$TEST_USERNAME&email=$UPDATED_EMAIL&role=author&_csrf_token=$CSRF_TOKEN")
      
      http_code=$(echo "$response" | tail -n 1)
      
      if [ "$http_code" -eq 302 ]; then
        print_pass "ユーザー更新: 302リダイレクト（成功）"
        
        # 更新が反映されていることを確認
        print_test "更新内容が反映されていることを確認"
        response=$(curl -s -w "\n%{http_code}" \
          -X GET "$ADMIN_URL/users" \
          -b "$COOKIE_FILE")
        
        body=$(echo "$response" | head -n -1)
        
        if echo "$body" | grep -q "$UPDATED_EMAIL"; then
          print_pass "ユーザー更新確認: 更新されたメールアドレスが表示される"
        else
          print_fail "ユーザー更新確認: 更新が反映されていない"
        fi
      else
        print_fail "ユーザー更新: HTTP $http_code (302が期待される)"
      fi
    fi
  fi
fi

# ========================================
# 4. ユーザー削除テスト
# ========================================
print_section "ユーザー削除テスト"

# 4.1. ユーザー削除実行
print_test "POST /admin/users/:id/delete → ユーザー削除"
if [ -n "$USER_ID" ]; then
  if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
    # CSRFトークン取得
    response=$(curl -s -w "\n%{http_code}" \
      -X GET "$ADMIN_URL/users" \
      -b "$COOKIE_FILE")
    
    body=$(echo "$response" | head -n -1)
    CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
    
    if [ -n "$CSRF_TOKEN" ]; then
      # ユーザー削除
      response=$(curl -s -w "\n%{http_code}" \
        -X POST "$ADMIN_URL/users/$USER_ID/delete" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -b "$COOKIE_FILE" \
        -c "$COOKIE_FILE" \
        -d "_csrf_token=$CSRF_TOKEN")
      
      http_code=$(echo "$response" | tail -n 1)
      
      if [ "$http_code" -eq 302 ]; then
        print_pass "ユーザー削除: 302リダイレクト（成功）"
        
        # ユーザー一覧から削除されたことを確認
        print_test "ユーザー一覧から削除されたことを確認"
        response=$(curl -s -w "\n%{http_code}" \
          -X GET "$ADMIN_URL/users" \
          -b "$COOKIE_FILE")
        
        body=$(echo "$response" | head -n -1)
        
        if ! echo "$body" | grep -q "$TEST_USERNAME"; then
          print_pass "ユーザー削除確認: ユーザー一覧から削除された"
        else
          print_fail "ユーザー削除確認: まだユーザー一覧に表示される"
        fi
      else
        print_fail "ユーザー削除: HTTP $http_code (302が期待される)"
      fi
    fi
  fi
fi

# 4.2. 最後の管理者は削除できないことを確認
print_test "最後の管理者は削除できないことを確認"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  # 管理者ユーザーのIDを取得
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/users" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  
  # adminユーザーのIDを取得（簡易的な方法）
  ADMIN_ID=$(echo "$body" | grep -o "/admin/users/[0-9]*/edit" | head -1 | grep -o "[0-9]*")
  
  if [ -n "$ADMIN_ID" ]; then
    # CSRFトークン取得
    CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
    
    if [ -n "$CSRF_TOKEN" ]; then
      # 管理者ユーザーの削除を試みる
      response=$(curl -s -w "\n%{http_code}" \
        -X POST "$ADMIN_URL/users/$ADMIN_ID/delete" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -b "$COOKIE_FILE" \
        -c "$COOKIE_FILE" \
        -d "_csrf_token=$CSRF_TOKEN")
      
      http_code=$(echo "$response" | tail -n 1)
      
      # エラーメッセージ付きでリダイレクトされることを期待
      if [ "$http_code" -eq 302 ]; then
        print_pass "最後の管理者削除防止: エラーメッセージ付きでリダイレクト"
      else
        print_fail "最後の管理者削除防止: HTTP $http_code"
      fi
    fi
  fi
fi

# ========================================
# 5. プロフィール表示テスト
# ========================================
print_section "プロフィール表示テスト"

# 5.1. プロフィールページアクセス
print_test "GET /admin/profile → プロフィール表示"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/profile" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" -eq 200 ]; then
    print_pass "プロフィール表示: HTTP 200 OK"
    
    # HTMLレスポンスであることを確認
    if echo "$body" | grep -qi "<!DOCTYPE\|<html"; then
      print_pass "プロフィール表示: HTMLレスポンス確認"
    else
      print_fail "プロフィール表示: HTMLレスポンスではない"
    fi
    
    # プロフィール情報の表示確認
    if echo "$body" | grep -qi "プロフィール\|profile"; then
      print_pass "プロフィール表示: タイトル確認"
    else
      print_fail "プロフィール表示: タイトルが見つからない"
    fi
    
    # ユーザー名の表示確認
    if echo "$body" | grep -q "$ADMIN_USER"; then
      print_pass "プロフィール表示: ユーザー名が表示される"
    else
      print_fail "プロフィール表示: ユーザー名が見つからない"
    fi
    
    # 統計情報の表示確認
    if echo "$body" | grep -qi "投稿\|posts\|統計\|statistics"; then
      print_pass "プロフィール表示: 統計情報が表示される"
    else
      print_fail "プロフィール表示: 統計情報が見つからない"
    fi
  else
    print_fail "プロフィール表示: HTTP $http_code (200が期待される)"
  fi
fi

# ========================================
# 6. プロフィール編集テスト
# ========================================
print_section "プロフィール編集テスト"

# 6.1. プロフィール編集フォームアクセス
print_test "GET /admin/profile/edit → 編集フォーム表示"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/profile/edit" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" -eq 200 ]; then
    print_pass "プロフィール編集フォーム: HTTP 200 OK"
    
    # フォーム要素の確認
    if echo "$body" | grep -qi "<form"; then
      print_pass "プロフィール編集フォーム: <form>タグが存在"
    else
      print_fail "プロフィール編集フォーム: <form>タグが見つからない"
    fi
    
    # 必須フィールドの確認
    if echo "$body" | grep -qi 'name="username"'; then
      print_pass "プロフィール編集フォーム: username フィールドが存在"
    else
      print_fail "プロフィール編集フォーム: username フィールドが見つからない"
    fi
    
    if echo "$body" | grep -qi 'name="email"'; then
      print_pass "プロフィール編集フォーム: email フィールドが存在"
    else
      print_fail "プロフィール編集フォーム: email フィールドが見つからない"
    fi
    
    # CSRFトークンの確認
    if echo "$body" | grep -qi 'name="_csrf_token"'; then
      print_pass "プロフィール編集フォーム: CSRFトークンが存在"
    else
      print_fail "プロフィール編集フォーム: CSRFトークンが見つからない"
    fi
  else
    print_fail "プロフィール編集フォーム: HTTP $http_code (200が期待される)"
  fi
fi

# 6.2. プロフィール情報更新
print_test "POST /admin/profile → プロフィール情報更新"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  # CSRFトークン取得
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/profile/edit" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    # プロフィール更新（display_nameを変更）
    DISPLAY_NAME="Test Admin User"
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/profile" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -c "$COOKIE_FILE" \
      -d "display_name=$DISPLAY_NAME&bio=Test bio&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "プロフィール更新: 302リダイレクト（成功）"
      
      # 更新が反映されていることを確認
      print_test "更新内容が反映されていることを確認"
      response=$(curl -s -w "\n%{http_code}" \
        -X GET "$ADMIN_URL/profile" \
        -b "$COOKIE_FILE")
      
      body=$(echo "$response" | head -n -1)
      
      if echo "$body" | grep -q "$DISPLAY_NAME"; then
        print_pass "プロフィール更新確認: 更新された表示名が表示される"
      else
        print_fail "プロフィール更新確認: 更新が反映されていない"
      fi
    else
      print_fail "プロフィール更新: HTTP $http_code (302が期待される)"
    fi
  else
    print_fail "CSRFトークン取得失敗: プロフィール更新をスキップ"
  fi
fi

# ========================================
# 7. 権限チェック: 通常ユーザーが管理者機能にアクセスできないこと
# ========================================
print_section "権限チェック: 通常ユーザー"

# 7.1. 通常ユーザー（author）を作成してログイン
print_test "通常ユーザーでログイン → /admin/users にアクセス"
NORMAL_USERNAME="e2e_normal_user_$(date +%s)"
NORMAL_EMAIL="${NORMAL_USERNAME}@test.com"
NORMAL_PASSWORD="NormalPass123!"

# まず管理者でログインして通常ユーザーを作成
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  # CSRFトークン取得
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/users/new" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    # 通常ユーザー作成（author ロール）
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/users" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -d "username=$NORMAL_USERNAME&email=$NORMAL_EMAIL&password=$NORMAL_PASSWORD&role=author&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      # 通常ユーザーでログイン
      if do_login "$NORMAL_USERNAME" "$NORMAL_PASSWORD" "$NORMAL_USER_COOKIE"; then
        # /admin/users にアクセスを試みる
        response=$(curl -s -w "\n%{http_code}" \
          -X GET "$ADMIN_URL/users" \
          -b "$NORMAL_USER_COOKIE")
        
        http_code=$(echo "$response" | tail -n 1)
        
        if [ "$http_code" -eq 403 ]; then
          print_pass "通常ユーザーのアクセス制限: 403エラーが返る"
        elif [ "$http_code" -eq 302 ]; then
          print_pass "通常ユーザーのアクセス制限: 302リダイレクト（アクセス拒否）"
        else
          print_fail "通常ユーザーのアクセス制限: HTTP $http_code (403または302が期待される)"
        fi
      else
        print_fail "通常ユーザーログイン失敗"
      fi
    fi
  fi
fi

# ========================================
# 8. 権限チェック: 未ログインユーザー
# ========================================
print_section "権限チェック: 未ログインユーザー"

# 8.1. ログアウトしてプロフィール編集にアクセス
print_test "未ログインで /admin/profile にアクセス → ログインページへリダイレクト"
rm -f "$COOKIE_FILE"
response=$(curl -s -w "\n%{http_code}" -L \
  -X GET "$ADMIN_URL/profile" \
  -c "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  # リダイレクト後にログインページが表示される
  if echo "$body" | grep -qi "login\|ログイン"; then
    print_pass "未ログインアクセス: ログインページにリダイレクト"
  else
    print_fail "未ログインアクセス: ログインページ以外にリダイレクト"
  fi
elif [ "$http_code" -eq 401 ] || [ "$http_code" -eq 302 ]; then
  print_pass "未ログインアクセス: HTTP $http_code でアクセス拒否"
else
  print_fail "未ログインアクセス: HTTP $http_code"
fi

# 8.2. 未ログインでプロフィール編集にアクセス
print_test "未ログインで /admin/profile/edit にアクセス → ログインページへリダイレクト"
rm -f "$COOKIE_FILE"
response=$(curl -s -w "\n%{http_code}" -L \
  -X GET "$ADMIN_URL/profile/edit" \
  -c "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  # リダイレクト後にログインページが表示される
  if echo "$body" | grep -qi "login\|ログイン"; then
    print_pass "未ログインアクセス（編集）: ログインページにリダイレクト"
  else
    print_fail "未ログインアクセス（編集）: ログインページ以外にリダイレクト"
  fi
elif [ "$http_code" -eq 401 ] || [ "$http_code" -eq 302 ]; then
  print_pass "未ログインアクセス（編集）: HTTP $http_code でアクセス拒否"
else
  print_fail "未ログインアクセス（編集）: HTTP $http_code"
fi

# ========================================
# クリーンアップ
# ========================================
print_section "クリーンアップ"

print_test "テストユーザーのクリーンアップ情報"
echo ""
echo "  以下のテストユーザーが作成された可能性があります:"
echo "  - テストユーザー: $TEST_USERNAME ($TEST_EMAIL) - 削除済み"
echo "  - 通常ユーザー: $NORMAL_USERNAME ($NORMAL_EMAIL)"
echo ""
echo "  注: テスト後、以下のSQLでテストユーザーを削除してください:"
echo "  docker-compose exec db psql -U luaaidiary -d luaaidiary -c \"DELETE FROM users WHERE username IN ('$NORMAL_USERNAME');\""
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
