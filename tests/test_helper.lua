-- テストヘルパー関数
local _M = {}

-- データベース接続のセットアップ
function _M.setup_db()
    local database = require("app.config.database")
    
    local db, err = database.connect()
    
    if not db then
        error("Failed to connect to database: " .. err)
    end
    
    return db
end

-- データベース接続のクリーンアップ
function _M.teardown_db(db)
    if db then
        local database = require("app.config.database")
        database.close(db)
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
