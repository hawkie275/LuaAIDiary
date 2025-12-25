-- テストヘルパー関数
local _M = {}

-- データベース接続のセットアップ
function _M.setup_db()
    local mysql = require("resty.mysql")
    local db = mysql:new()
    
    db:set_timeout(1000)
    
    local ok, err = db:connect({
        host = os.getenv("MYSQL_HOST") or "db",
        port = tonumber(os.getenv("MYSQL_PORT")) or 3306,
        database = os.getenv("MYSQL_DATABASE") or "luwordpress",
        user = os.getenv("MYSQL_USER") or "luwordpress",
        password = os.getenv("MYSQL_PASSWORD") or "luwordpress_pass",
        charset = "utf8mb4"
    })
    
    if not ok then
        error("Failed to connect to database: " .. err)
    end
    
    return db
end

-- データベース接続のクリーンアップ
function _M.teardown_db(db)
    if db then
        db:close()
    end
end

-- テストデータのクリーンアップ
function _M.clean_test_data(db)
    -- テストで作成したデータを削除
    db:query("DELETE FROM posts WHERE title LIKE 'TEST_%'")
    db:query("DELETE FROM users WHERE username LIKE 'test_%'")
    db:query("DELETE FROM categories WHERE name LIKE 'TEST_%'")
    db:query("DELETE FROM tags WHERE name LIKE 'TEST_%'")
end

-- アサーション関数
function _M.assert_table_has_key(tbl, key)
    assert(tbl[key] ~= nil, "Table does not have key: " .. key)
end

function _M.assert_not_nil(value, message)
    assert(value ~= nil, message or "Value is nil")
end

function _M.assert_equal(expected, actual, message)
    assert(expected == actual, 
        message or string.format("Expected %s but got %s", tostring(expected), tostring(actual)))
end

return _M
