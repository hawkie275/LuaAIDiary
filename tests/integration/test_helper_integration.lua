-- 統合テスト用ヘルパー
-- 実際のデータベース接続とテストデータのクリーンアップを提供

local _M = {}

-- ngxモックのセットアップ（モデルがngxに依存する場合）
function _M.setup_ngx_mock()
  if not _G.ngx then
    _G.ngx = {
      log = function(level, ...)
        -- テスト時はログを抑制（必要に応じてprintに変更）
        -- print(...)
      end,
      ERR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4,
      quote_sql_str = function(str)
        if not str then return "NULL" end
        -- シンプルなSQLエスケープ
        local escaped = str:gsub("'", "''")
        return "'" .. escaped .. "'"
      end
    }
  end
end

-- 環境変数の設定
function _M.setup_env()
  if not os.getenv("POSTGRES_HOST") then
    os.setenv("POSTGRES_HOST", "localhost")
  end
  if not os.getenv("POSTGRES_PORT") then
    os.setenv("POSTGRES_PORT", "5432")
  end
  if not os.getenv("POSTGRES_DB") then
    os.setenv("POSTGRES_DB", "luaaidiary")
  end
  if not os.getenv("POSTGRES_USER") then
    os.setenv("POSTGRES_USER", "luaaidiary")
  end
  if not os.getenv("POSTGRES_PASSWORD") then
    os.setenv("POSTGRES_PASSWORD", "luaaidiary_pass")
  end
end

-- データベース接続のセットアップ
function _M.setup_db()
  _M.setup_ngx_mock()
  _M.setup_env()
  
  local pgmoon = require("pgmoon")
  
  local db = pgmoon.new({
    host = os.getenv("POSTGRES_HOST"),
    port = tonumber(os.getenv("POSTGRES_PORT")),
    database = os.getenv("POSTGRES_DB"),
    user = os.getenv("POSTGRES_USER"),
    password = os.getenv("POSTGRES_PASSWORD")
  })
  
  local ok, err = db:connect()
  
  if not ok then
    error("データベース接続エラー: " .. (err or "unknown"))
  end
  
  -- UTF-8設定
  db:query("SET client_encoding = 'UTF8'")
  
  return db
end

-- データベース接続のクリーンアップ
function _M.teardown_db(db)
  if db then
    db:disconnect()
  end
end

-- トランザクション開始
function _M.begin_transaction(db)
  local res, err = db:query("BEGIN")
  if not res then
    error("トランザクション開始エラー: " .. (err or "unknown"))
  end
  return true
end

-- トランザクションロールバック
function _M.rollback_transaction(db)
  local res, err = db:query("ROLLBACK")
  if not res then
    error("ロールバックエラー: " .. (err or "unknown"))
  end
  return true
end

-- トランザクションコミット
function _M.commit_transaction(db)
  local res, err = db:query("COMMIT")
  if not res then
    error("コミットエラー: " .. (err or "unknown"))
  end
  return true
end

-- テストユーザーを作成
function _M.create_test_user(db, username, email)
  username = username or "test_user_" .. os.time()
  email = email or username .. "@test.com"
  
  -- パスワードハッシュ（簡易的なダミー）
  local password_hash = "$2a$10$dummy_hash_for_testing"
  
  local query = string.format([[
    INSERT INTO users (username, email, password_hash, created_at, updated_at)
    VALUES ('%s', '%s', '%s', NOW(), NOW())
    RETURNING id
  ]], username, email, password_hash)
  
  local res, err = db:query(query)
  
  if not res or #res == 0 then
    error("テストユーザー作成エラー: " .. (err or "unknown"))
  end
  
  return res[1].id, username
end

-- テスト投稿を作成
function _M.create_test_post(db, user_id, title, content)
  title = title or "TEST_POST_" .. os.time()
  content = content or "Test content"
  
  local query = string.format([[
    INSERT INTO posts (title, slug, content, excerpt, author_id, status, created_at, updated_at)
    VALUES ('%s', '%s', '%s', '', %d, 'published', NOW(), NOW())
    RETURNING id
  ]], title, title:lower():gsub(" ", "-"), content, user_id)
  
  local res, err = db:query(query)
  
  if not res or #res == 0 then
    error("テスト投稿作成エラー: " .. (err or "unknown"))
  end
  
  return res[1].id
end

-- テストカテゴリーを作成
function _M.create_test_category(db, name)
  name = name or "TEST_CATEGORY_" .. os.time()
  
  local query = string.format([[
    INSERT INTO categories (name, slug, created_at, updated_at)
    VALUES ('%s', '%s', NOW(), NOW())
    RETURNING id
  ]], name, name:lower():gsub(" ", "-"))
  
  local res, err = db:query(query)
  
  if not res or #res == 0 then
    error("テストカテゴリー作成エラー: " .. (err or "unknown"))
  end
  
  return res[1].id
end

-- テストタグを作成
function _M.create_test_tag(db, name)
  name = name or "TEST_TAG_" .. os.time()
  
  local query = string.format([[
    INSERT INTO tags (name, slug, created_at, updated_at)
    VALUES ('%s', '%s', NOW(), NOW())
    RETURNING id
  ]], name, name:lower():gsub(" ", "-"))
  
  local res, err = db:query(query)
  
  if not res or #res == 0 then
    error("テストタグ作成エラー: " .. (err or "unknown"))
  end
  
  return res[1].id
end

-- テストデータのクリーンアップ（パターンマッチ）
function _M.clean_test_data(db)
  -- TEST_で始まるデータを削除
  db:query("DELETE FROM post_tags WHERE post_id IN (SELECT id FROM posts WHERE title LIKE 'TEST_%')")
  db:query("DELETE FROM post_categories WHERE post_id IN (SELECT id FROM posts WHERE title LIKE 'TEST_%')")
  db:query("DELETE FROM posts WHERE title LIKE 'TEST_%'")
  db:query("DELETE FROM users WHERE username LIKE 'test_%'")
  db:query("DELETE FROM categories WHERE name LIKE 'TEST_%'")
  db:query("DELETE FROM tags WHERE name LIKE 'TEST_%'")
end

-- アサーション関数
function _M.assert_not_nil(value, message)
  assert(value ~= nil, message or "Value should not be nil")
end

function _M.assert_equal(expected, actual, message)
  assert(expected == actual, 
    message or string.format("Expected %s but got %s", tostring(expected), tostring(actual)))
end

function _M.assert_true(value, message)
  assert(value == true, message or "Value should be true")
end

function _M.assert_false(value, message)
  assert(value == false, message or "Value should be false")
end

function _M.assert_table_has_key(tbl, key, message)
  assert(tbl[key] ~= nil, message or "Table does not have key: " .. tostring(key))
end

function _M.assert_greater_than(actual, expected, message)
  assert(actual > expected,
    message or string.format("%s should be greater than %s", tostring(actual), tostring(expected)))
end

return _M
