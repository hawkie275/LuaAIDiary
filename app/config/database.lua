-- データベース接続設定モジュール
-- MySQL接続の設定と接続プールの管理を行います

local mysql = require "resty.mysql"
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
    host = get_env("MYSQL_HOST", "db"),
    port = tonumber(get_env("MYSQL_PORT", "3306")),
    database = get_env("MYSQL_DATABASE", "luaaidiary"),
    user = get_env("MYSQL_USER", "luaaidiary"),
    password = get_env("MYSQL_PASSWORD", "luaaidiary_pass"),
    charset = "utf8mb4",
    max_packet_size = 1024 * 1024 * 16,  -- 16MB
    pool_size = tonumber(get_env("DB_POOL_SIZE", "100")),
    pool_timeout = tonumber(get_env("DB_POOL_TIMEOUT", "60000")),  -- ミリ秒
    connect_timeout = tonumber(get_env("DB_CONNECT_TIMEOUT", "3000")),  -- 3秒
    read_timeout = tonumber(get_env("DB_READ_TIMEOUT", "10000")),  -- 10秒
    send_timeout = tonumber(get_env("DB_SEND_TIMEOUT", "10000"))   -- 10秒
}

-- データベース接続を取得
-- @return db MySQLコネクションオブジェクト
-- @return err エラーメッセージ（エラー時）
function _M.connect()
    local db, err = mysql:new()
    if not db then
        ngx.log(ngx.ERR, "MySQLオブジェクトの作成に失敗: ", err)
        return nil, err
    end
    
    -- タイムアウト設定
    db:set_timeout(_M.config.connect_timeout)
    
    -- データベースへ接続
    local ok, err, errcode, sqlstate = db:connect(_M.config)
    
    if not ok then
        ngx.log(ngx.ERR, "データベース接続エラー: ", err, ": ", errcode, " ", sqlstate)
        return nil, err
    end
    
    -- 文字コードを明示的に設定
    local res, err = db:query("SET NAMES utf8mb4")
    if not res then
        ngx.log(ngx.ERR, "文字コード設定エラー: ", err)
        db:close()
        return nil, err
    end
    
    ngx.log(ngx.INFO, "データベース接続成功")
    return db, nil
end

-- データベース接続を閉じる（接続プールに返却）
-- @param db MySQLコネクションオブジェクト
function _M.close(db)
    if not db then
        return
    end
    
    -- 接続プールに返却
    local ok, err = db:set_keepalive(_M.config.pool_timeout, _M.config.pool_size)
    if not ok then
        ngx.log(ngx.WARN, "接続プールへの返却に失敗: ", err)
        -- エラー時は接続を閉じる
        db:close()
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
    
    local res, err, errcode, sqlstate
    
    if params then
        -- プリペアドステートメントを使用
        res, err, errcode, sqlstate = db:query(query, params)
    else
        -- 通常のクエリ
        res, err, errcode, sqlstate = db:query(query)
    end
    
    if not res then
        ngx.log(ngx.ERR, "クエリ実行エラー: ", err, ": ", errcode, " ", sqlstate)
        _M.close(db)
        return nil, err
    end
    
    _M.close(db)
    return res, nil
end

-- トランザクションを開始
-- @return db MySQLコネクションオブジェクト
-- @return err エラーメッセージ（エラー時）
function _M.begin_transaction()
    local db, err = _M.connect()
    if not db then
        return nil, err
    end
    
    local res, err = db:query("START TRANSACTION")
    if not res then
        ngx.log(ngx.ERR, "トランザクション開始エラー: ", err)
        _M.close(db)
        return nil, err
    end
    
    return db, nil
end

-- トランザクションをコミット
-- @param db MySQLコネクションオブジェクト
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
-- @param db MySQLコネクションオブジェクト
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
