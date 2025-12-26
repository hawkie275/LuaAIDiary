-- データベース接続設定モジュール
-- PostgreSQL接続の設定と接続プールの管理を行います

local pgmoon = require "pgmoon"
local cjson = require "cjson"

local _M = {}

-- 環境変数から設定を読み込み
local function get_env(key, default)
    local value = os.getenv(key)
    if value and value ~= "" then
        return value
    end
    return default
end

-- データベース接続設定
_M.config = {
    host = get_env("POSTGRES_HOST", "db"),
    port = tonumber(get_env("POSTGRES_PORT", "5432")),
    database = get_env("POSTGRES_DB", "luaaidiary"),
    user = get_env("POSTGRES_USER", "luaaidiary"),
    password = get_env("POSTGRES_PASSWORD", "luaaidiary_pass"),
    pool_size = tonumber(get_env("DB_POOL_SIZE", "100")),
    pool_timeout = tonumber(get_env("DB_POOL_TIMEOUT", "60000")),  -- ミリ秒
    connect_timeout = tonumber(get_env("DB_CONNECT_TIMEOUT", "3000")),  -- 3秒
    read_timeout = tonumber(get_env("DB_READ_TIMEOUT", "10000")),  -- 10秒
    send_timeout = tonumber(get_env("DB_SEND_TIMEOUT", "10000"))   -- 10秒
}

-- データベース接続を取得
-- @return db PostgreSQLコネクションオブジェクト
-- @return err エラーメッセージ（エラー時）
function _M.connect()
    local db = pgmoon.new({
        host = _M.config.host,
        port = _M.config.port,
        database = _M.config.database,
        user = _M.config.user,
        password = _M.config.password
    })
    
    -- タイムアウト設定
    db:settimeout(_M.config.connect_timeout)
    
    -- データベースへ接続
    local ok, err = db:connect()
    
    if not ok then
        ngx.log(ngx.ERR, "データベース接続エラー: ", err)
        return nil, err
    end
    
    -- クライアントエンコーディングをUTF-8に設定
    local res, err = db:query("SET client_encoding = 'UTF8'")
    if not res then
        ngx.log(ngx.ERR, "文字コード設定エラー: ", err)
        db:disconnect()
        return nil, err
    end
    
    ngx.log(ngx.INFO, "データベース接続成功")
    return db, nil
end

-- データベース接続を閉じる（接続プールに返却）
-- @param db PostgreSQLコネクションオブジェクト
function _M.close(db)
    if not db then
        return
    end
    
    -- 接続プールに返却
    local ok, err = db:keepalive(_M.config.pool_timeout, _M.config.pool_size)
    if not ok then
        ngx.log(ngx.WARN, "接続プールへの返却に失敗: ", err)
        -- エラー時は接続を閉じる
        db:disconnect()
    end
end

-- クエリを実行
-- @param query SQL文字列
-- @param params プリペアドステートメントのパラメータ（オプション）
-- @return result クエリ結果
-- @return err エラーメッセージ（エラー時）
function _M.query(query, params)
    local db, err = _M.connect()
    if not db then
        return nil, err
    end
    
    local res, err
    
    if params then
        -- プリペアドステートメントを使用
        -- PostgreSQLではパラメータ化クエリはサポートされているが、
        -- resty.postgresの実装によって異なる可能性があります
        res, err = db:query(query, params)
    else
        -- 通常のクエリ
        res, err = db:query(query)
    end
    
    if not res then
        ngx.log(ngx.ERR, "クエリ実行エラー: ", err)
        _M.close(db)
        return nil, err
    end
    
    _M.close(db)
    return res, nil
end

-- トランザクションを開始
-- @return db PostgreSQLコネクションオブジェクト
-- @return err エラーメッセージ（エラー時）
function _M.begin_transaction()
    local db, err = _M.connect()
    if not db then
        return nil, err
    end
    
    local res, err = db:query("BEGIN")
    if not res then
        ngx.log(ngx.ERR, "トランザクション開始エラー: ", err)
        _M.close(db)
        return nil, err
    end
    
    return db, nil
end

-- トランザクションをコミット
-- @param db PostgreSQLコネクションオブジェクト
-- @return ok 成功フラグ
-- @return err エラーメッセージ（エラー時）
function _M.commit(db)
    if not db then
        return false, "データベース接続が無効です"
    end
    
    local res, err = db:query("COMMIT")
    if not res then
        ngx.log(ngx.ERR, "コミットエラー: ", err)
        _M.close(db)
        return false, err
    end
    
    _M.close(db)
    return true, nil
end

-- トランザクションをロールバック
-- @param db PostgreSQLコネクションオブジェクト
-- @return ok 成功フラグ
-- @return err エラーメッセージ（エラー時）
function _M.rollback(db)
    if not db then
        return false, "データベース接続が無効です"
    end
    
    local res, err = db:query("ROLLBACK")
    if not res then
        ngx.log(ngx.ERR, "ロールバックエラー: ", err)
        _M.close(db)
        return false, err
    end
    
    _M.close(db)
    return true, nil
end

-- SQLインジェクション対策：文字列のエスケープ
-- @param str エスケープする文字列
-- @return escaped_str エスケープされた文字列
function _M.escape(str)
    if not str then
        return "NULL"
    end
    
    -- OpenRestyのngx.quote_sql_strを使用
    return ngx.quote_sql_str(str)
end

return _M
