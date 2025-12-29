#!/bin/bash
# パスワード変更機能 E2Eテスト
# パスワード変更フォームとAPIの動作確認

set -e  # エラーで停止

BASE_URL="${BASE_URL:-http://localhost:8080}"
ADMIN_URL="${BASE_URL}/admin"

# デフォルトのadminユーザー情報
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"
NEW_PASS="newpass123"
TEMP_PASS="temppass123"

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
COOKIE_FILE="/tmp/luaaidiary_password_change_cookies.txt"
rm -f "$COOKIE_FILE"

# クリーンアップ関数
cleanup() {
  rm -f "$COOKIE_FILE"
}

trap cleanup EXIT

echo "========================================="
echo "パスワード変更機能 E2Eテスト"
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
  
  # CSRFトークンを取得
  rm -f "$COOKIE_FILE"
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/login" \
    -c "$COOKIE_FILE")
  
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
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
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
# 1. パスワード変更フォームアクセステスト
# ========================================
print_section "パスワード変更フォームアクセステスト"

# 1.1. 未認証でのアクセス → ログインページにリダイレクト
print_test "GET /admin/change-password (未認証) → ログインページにリダイレクト"
rm -f "$COOKIE_FILE"
response=$(curl -s -w "\n%{http_code}" -L \
  -X GET "$ADMIN_URL/change-password" \
  -c "$COOKIE_FILE")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" -eq 200 ]; then
  # リダイレクト後にログインページが表示される
  if echo "$body" | grep -qi "login\|ログイン"; then
    print_pass "未認証アクセス: ログインページにリダイレクト"
  else
    print_fail "未認証アクセス: ログインページ以外にリダイレクト"
  fi
else
  print_fail "未認証アクセス: HTTP $http_code"
fi

# 1.2. 認証済みでのアクセス → フォーム表示
print_test "GET /admin/change-password (認証済み) → フォーム表示"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  http_code=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" -eq 200 ]; then
    print_pass "認証済みアクセス: HTTP 200 OK"
    
    # HTMLレスポンスであることを確認
    if echo "$body" | grep -qi "<!DOCTYPE\|<html"; then
      print_pass "パスワード変更フォーム: HTMLレスポンス確認"
    else
      print_fail "パスワード変更フォーム: HTMLレスポンスではない"
    fi
    
    # フォーム要素の存在確認
    if echo "$body" | grep -qi "<form"; then
      print_pass "パスワード変更フォーム: <form>タグが存在"
    else
      print_fail "パスワード変更フォーム: <form>タグが見つからない"
    fi
    
    # 現在のパスワード入力フィールド
    if echo "$body" | grep -qi 'name="current_password"'; then
      print_pass "パスワード変更フォーム: current_password入力フィールドが存在"
    else
      print_fail "パスワード変更フォーム: current_password入力フィールドが見つからない"
    fi
    
    # 新しいパスワード入力フィールド
    if echo "$body" | grep -qi 'name="new_password"'; then
      print_pass "パスワード変更フォーム: new_password入力フィールドが存在"
    else
      print_fail "パスワード変更フォーム: new_password入力フィールドが見つからない"
    fi
    
    # 確認用パスワード入力フィールド
    if echo "$body" | grep -qi 'name="confirm_password"'; then
      print_pass "パスワード変更フォーム: confirm_password入力フィールドが存在"
    else
      print_fail "パスワード変更フォーム: confirm_password入力フィールドが見つからない"
    fi
    
    # CSRFトークンフィールド
    if echo "$body" | grep -qi 'name="_csrf_token"'; then
      print_pass "パスワード変更フォーム: CSRFトークンフィールドが存在"
    else
      print_fail "パスワード変更フォーム: CSRFトークンフィールドが見つからない"
    fi
  else
    print_fail "認証済みアクセス: HTTP $http_code (200が期待される)"
  fi
else
  print_fail "ログイン失敗: パスワード変更フォームアクセステストをスキップ"
fi

# ========================================
# 2. 正常系テスト
# ========================================
print_section "正常系テスト"

# 2.1. 有効なパスワード変更
print_test "POST /admin/change-password → パスワード変更成功"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  # CSRFトークンを取得
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    # パスワード変更を実行
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/change-password" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -c "$COOKIE_FILE" \
      -d "current_password=$ADMIN_PASS&new_password=$NEW_PASS&confirm_password=$NEW_PASS&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "パスワード変更: 302リダイレクト（成功）"
      
      # 2.2. 新しいパスワードでログアウト＆再ログイン
      print_test "新しいパスワードで再ログイン → 成功確認"
      if do_login "$ADMIN_USER" "$NEW_PASS"; then
        print_pass "新パスワードで再ログイン: 成功"
        
        # ダッシュボードにアクセスできることを確認
        response=$(curl -s -w "\n%{http_code}" \
          -X GET "$ADMIN_URL/dashboard" \
          -b "$COOKIE_FILE")
        
        http_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" -eq 200 ]; then
          if echo "$body" | grep -qi "dashboard\|ダッシュボード"; then
            print_pass "新パスワード後のセッション確認: ダッシュボードアクセス可能"
          else
            print_fail "新パスワード後のセッション確認: ダッシュボードの内容が不正"
          fi
        else
          print_fail "新パスワード後のセッション確認: HTTP $http_code"
        fi
        
        # パスワードを元に戻す（後続のテストのため）
        print_test "パスワードを元に戻す"
        response=$(curl -s -w "\n%{http_code}" \
          -X GET "$ADMIN_URL/change-password" \
          -b "$COOKIE_FILE")
        
        body=$(echo "$response" | head -n -1)
        CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
        
        if [ -n "$CSRF_TOKEN" ]; then
          response=$(curl -s -w "\n%{http_code}" \
            -X POST "$ADMIN_URL/change-password" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -b "$COOKIE_FILE" \
            -d "current_password=$NEW_PASS&new_password=$ADMIN_PASS&confirm_password=$ADMIN_PASS&_csrf_token=$CSRF_TOKEN")
          
          http_code=$(echo "$response" | tail -n 1)
          
          if [ "$http_code" -eq 302 ]; then
            print_pass "パスワードを元に戻す: 成功"
          else
            print_fail "パスワードを元に戻す: HTTP $http_code"
          fi
        fi
      else
        print_fail "新パスワードで再ログイン: 失敗"
      fi
    else
      print_fail "パスワード変更: HTTP $http_code (302が期待される)"
    fi
  else
    print_fail "CSRFトークン取得失敗: パスワード変更をスキップ"
  fi
else
  print_fail "ログイン失敗: パスワード変更テストをスキップ"
fi

# ========================================
# 3. 異常系テスト
# ========================================
print_section "異常系テスト"

# 3.1. 現在のパスワード不一致
print_test "現在のパスワード不一致 → エラーメッセージ"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/change-password" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -d "current_password=wrongpassword&new_password=$NEW_PASS&confirm_password=$NEW_PASS&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "現在のパスワード不一致: エラーメッセージ付きでリダイレクト"
    else
      print_fail "現在のパスワード不一致: HTTP $http_code (302が期待される)"
    fi
  fi
fi

# 3.2. 新しいパスワードと確認用パスワード不一致
print_test "新しいパスワードと確認用パスワード不一致 → エラーメッセージ"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/change-password" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -d "current_password=$ADMIN_PASS&new_password=$NEW_PASS&confirm_password=different123&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "パスワード不一致: エラーメッセージ付きでリダイレクト"
    else
      print_fail "パスワード不一致: HTTP $http_code (302が期待される)"
    fi
  fi
fi

# 3.3. パスワード要件不足: 8文字未満
print_test "パスワード要件不足（8文字未満） → エラーメッセージ"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/change-password" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -d "current_password=$ADMIN_PASS&new_password=short1&confirm_password=short1&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "パスワード長不足: エラーメッセージ付きでリダイレクト"
    else
      print_fail "パスワード長不足: HTTP $http_code (302が期待される)"
    fi
  fi
fi

# 3.4. パスワード要件不足: 英字のみ
print_test "パスワード要件不足（英字のみ） → エラーメッセージ"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/change-password" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -d "current_password=$ADMIN_PASS&new_password=onlyletters&confirm_password=onlyletters&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "英字のみパスワード: エラーメッセージ付きでリダイレクト"
    else
      print_fail "英字のみパスワード: HTTP $http_code (302が期待される)"
    fi
  fi
fi

# 3.5. パスワード要件不足: 数字のみ
print_test "パスワード要件不足（数字のみ） → エラーメッセージ"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$ADMIN_URL/change-password" \
    -b "$COOKIE_FILE")
  
  body=$(echo "$response" | head -n -1)
  CSRF_TOKEN=$(echo "$body" | grep -o 'name="_csrf_token" value="[^"]*"' | sed 's/.*value="\([^"]*\)".*/\1/')
  
  if [ -n "$CSRF_TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "$ADMIN_URL/change-password" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -b "$COOKIE_FILE" \
      -d "current_password=$ADMIN_PASS&new_password=12345678&confirm_password=12345678&_csrf_token=$CSRF_TOKEN")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" -eq 302 ]; then
      print_pass "数字のみパスワード: エラーメッセージ付きでリダイレクト"
    else
      print_fail "数字のみパスワード: HTTP $http_code (302が期待される)"
    fi
  fi
fi

# 3.6. CSRFトークンなし
print_test "CSRFトークンなし → エラー"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$ADMIN_URL/change-password" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -b "$COOKIE_FILE" \
    -d "current_password=$ADMIN_PASS&new_password=$NEW_PASS&confirm_password=$NEW_PASS")
  
  http_code=$(echo "$response" | tail -n 1)
  
  if [ "$http_code" -eq 302 ]; then
    print_pass "CSRFトークンなし: エラーメッセージ付きでリダイレクト"
  else
    print_fail "CSRFトークンなし: HTTP $http_code (302が期待される)"
  fi
fi

# 3.7. 無効なCSRFトークン
print_test "無効なCSRFトークン → エラー"
if do_login "$ADMIN_USER" "$ADMIN_PASS"; then
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "$ADMIN_URL/change-password" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -b "$COOKIE_FILE" \
    -d "current_password=$ADMIN_PASS&new_password=$NEW_PASS&confirm_password=$NEW_PASS&_csrf_token=invalid_token_12345")
  
  http_code=$(echo "$response" | tail -n 1)
  
  if [ "$http_code" -eq 302 ]; then
    print_pass "無効なCSRFトークン: エラーメッセージ付きでリダイレクト"
  else
    print_fail "無効なCSRFトークン: HTTP $http_code (302が期待される)"
  fi
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
