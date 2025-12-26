-- ベースモデルクラス
-- すべてのモデルが継承する共通機能を提供します

local db_config = require("config.database")

local _M = {}
_M.__index = _M

-- 新しいモデルインスタンスを作成
-- @param table_name テーブル名
-- @return モデルインスタンス
function _M.new(table_name)
    local self = setmetatable({}, _M)
    self.table_name = table_name
    self.primary_key = "id"
    return self
end

-- ========================================
-- CRUD操作
-- ========================================

-- IDで単一レコードを検索
-- @param id 検索するID
-- @return レコード、エラー
function _M:find(id)
    if not id then
        return nil, "IDが指定されていません"
    end
    
    local query = string.format("SELECT * FROM %s WHERE %s = %s LIMIT 1",
        self.table_name,
        self.primary_key,
        db_config.escape(tostring(id))
    )
    
    local res, err = db_config.query(query)
    if not res then
        return nil, err
    end
    
    if #res == 0 then
        return nil, "レコードが見つかりません"
    end
    
    return res[1], nil
end

-- 条件でレコードを検索
-- @param conditions 検索条件のテーブル {field = value, ...}
-- @param options オプション {limit, offset, order_by}
-- @return レコードの配列、エラー
function _M:find_by(conditions, options)
    options = options or {}
    
    local where_clauses = {}
    if conditions then
        for field, value in pairs(conditions) do
            if value == nil then
                table.insert(where_clauses, string.format("%s IS NULL", field))
            else
                table.insert(where_clauses, string.format("%s = %s", 
                    field, 
                    db_config.escape(tostring(value))
                ))
            end
        end
    end
    
    local query = string.format("SELECT * FROM %s", self.table_name)
    
    if #where_clauses > 0 then
        query = query .. " WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    if options.order_by then
        query = query .. " ORDER BY " .. options.order_by
    end
    
    if options.limit then
        query = query .. " LIMIT " .. tostring(options.limit)
    end
    
    if options.offset then
        query = query .. " OFFSET " .. tostring(options.offset)
    end
    
    return db_config.query(query)
end

-- 新しいレコードを作成
-- @param data 挿入するデータのテーブル
-- @return 挿入されたID、エラー
function _M:create(data)
    if not data or type(data) ~= "table" then
        return nil, "データが無効です"
    end
    
    local fields = {}
    local values = {}
    
    for field, value in pairs(data) do
        table.insert(fields, field)
        if value == nil then
            table.insert(values, "NULL")
        elseif type(value) == "number" then
            table.insert(values, tostring(value))
        else
            table.insert(values, db_config.escape(tostring(value)))
        end
    end
    
    -- PostgreSQL用にRETURNING句を追加
    local query = string.format("INSERT INTO %s (%s) VALUES (%s) RETURNING %s",
        self.table_name,
        table.concat(fields, ", "),
        table.concat(values, ", "),
        self.primary_key
    )
    
    local db, err = db_config.connect()
    if not db then
        return nil, err
    end
    
    local res, err = db:query(query)
    if not res then
        db_config.close(db)
        return nil, err
    end
    
    -- PostgreSQLではRETURNINGで返された値を取得
    local insert_id
    if res[1] and res[1][self.primary_key] then
        insert_id = res[1][self.primary_key]
    else
        insert_id = res.insert_id  -- フォールバック
    end
    
    db_config.close(db)
    
    return insert_id, nil
end

-- レコードを更新
-- @param id 更新するレコードのID
-- @param data 更新するデータのテーブル
-- @return 成功フラグ、エラー
function _M:update(id, data)
    if not id then
        return false, "IDが指定されていません"
    end
    
    if not data or type(data) ~= "table" then
        return false, "データが無効です"
    end
    
    local set_clauses = {}
    for field, value in pairs(data) do
        if value == nil then
            table.insert(set_clauses, string.format("%s = NULL", field))
        elseif type(value) == "number" then
            table.insert(set_clauses, string.format("%s = %s", field, tostring(value)))
        else
            table.insert(set_clauses, string.format("%s = %s", field, db_config.escape(tostring(value))))
        end
    end
    
    if #set_clauses == 0 then
        return false, "更新するデータがありません"
    end
    
    local query = string.format("UPDATE %s SET %s WHERE %s = %s",
        self.table_name,
        table.concat(set_clauses, ", "),
        self.primary_key,
        db_config.escape(tostring(id))
    )
    
    local res, err = db_config.query(query)
    if not res then
        return false, err
    end
    
    return true, nil
end

-- レコードを削除
-- @param id 削除するレコードのID
-- @return 成功フラグ、エラー
function _M:delete(id)
    if not id then
        return false, "IDが指定されていません"
    end
    
    local query = string.format("DELETE FROM %s WHERE %s = %s",
        self.table_name,
        self.primary_key,
        db_config.escape(tostring(id))
    )
    
    local res, err = db_config.query(query)
    if not res then
        return false, err
    end
    
    return true, nil
end

-- 全レコードを取得（ページネーション対応）
-- @param options オプション {limit, offset, order_by, where}
-- @return レコードの配列、エラー
function _M:all(options)
    options = options or {}
    
    local query = string.format("SELECT * FROM %s", self.table_name)
    
    if options.where then
        query = query .. " WHERE " .. options.where
    end
    
    if options.order_by then
        query = query .. " ORDER BY " .. options.order_by
    else
        query = query .. " ORDER BY " .. self.primary_key .. " DESC"
    end
    
    if options.limit then
        query = query .. " LIMIT " .. tostring(options.limit)
    end
    
    if options.offset then
        query = query .. " OFFSET " .. tostring(options.offset)
    end
    
    ngx.log(ngx.ERR, "[DIAGNOSIS] Base:all() テーブル: ", self.table_name)
    ngx.log(ngx.ERR, "[DIAGNOSIS] Base:all() クエリ: ", query)
    
    local result, err = db_config.query(query)
    
    ngx.log(ngx.ERR, "[DIAGNOSIS] Base:all() 結果: ", result and ("配列サイズ=" .. #result) or "nil")
    if err then
        ngx.log(ngx.ERR, "[DIAGNOSIS] Base:all() エラー: ", err)
    end
    
    return result, err
end

-- レコード数をカウント
-- @param conditions 検索条件のテーブル（オプション）
-- @return カウント、エラー
function _M:count(conditions)
    local where_clauses = {}
    if conditions then
        for field, value in pairs(conditions) do
            if value == nil then
                table.insert(where_clauses, string.format("%s IS NULL", field))
            else
                table.insert(where_clauses, string.format("%s = %s", 
                    field, 
                    db_config.escape(tostring(value))
                ))
            end
        end
    end
    
    local query = string.format("SELECT COUNT(*) as count FROM %s", self.table_name)
    
    if #where_clauses > 0 then
        query = query .. " WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    local res, err = db_config.query(query)
    if not res then
        return nil, err
    end
    
    return tonumber(res[1].count), nil
end

-- ========================================
-- トランザクション管理
-- ========================================

-- トランザクションを実行
-- @param callback トランザクション内で実行する関数
-- @return 成功フラグ、結果またはエラー
function _M:transaction(callback)
    local db, err = db_config.begin_transaction()
    if not db then
        return false, err
    end
    
    local success, result = pcall(callback, db)
    
    if success then
        local ok, err = db_config.commit(db)
        if not ok then
            return false, err
        end
        return true, result
    else
        db_config.rollback(db)
        return false, result
    end
end

-- ========================================
-- ヘルパーメソッド
-- ========================================

-- レコードが存在するか確認
-- @param id 確認するID
-- @return 存在フラグ
function _M:exists(id)
    local record, err = self:find(id)
    return record ~= nil
end

-- 生のSQLクエリを実行
-- @param query SQLクエリ文字列
-- @return 結果、エラー
function _M:raw_query(query)
    return db_config.query(query)
end

-- WHERE句を構築
-- @param conditions 条件のテーブル
-- @return WHERE句文字列
function _M:build_where(conditions)
    if not conditions or type(conditions) ~= "table" then
        return ""
    end
    
    local clauses = {}
    for field, value in pairs(conditions) do
        if value == nil then
            table.insert(clauses, string.format("%s IS NULL", field))
        elseif type(value) == "table" and value.op then
            -- 演算子指定: {op = ">=", value = 10}
            table.insert(clauses, string.format("%s %s %s", 
                field, 
                value.op, 
                db_config.escape(tostring(value.value))
            ))
        else
            table.insert(clauses, string.format("%s = %s", 
                field, 
                db_config.escape(tostring(value))
            ))
        end
    end
    
    if #clauses == 0 then
        return ""
    end
    
    return table.concat(clauses, " AND ")
end

return _M
