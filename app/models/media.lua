-- メディアモデル
-- アップロード済み画像の保存情報、重複検知、利用状況を管理します。

local Base = require("models.base")
local db_config = require("config.database")

local _M = Base.new("media")

local function escape(value)
    if value == nil then
        return "NULL"
    end
    if type(value) == "number" then
        return tostring(value)
    end
    return db_config.escape(tostring(value))
end

local function media_select_columns()
    return [[
        media.*,
        COALESCE(usage_counts.usage_count, 0) AS usage_count
    ]]
end

local function media_from_row(row)
    if not row then
        return nil
    end

    row.url = "/" .. row.storage_key
    if row.thumbnail_storage_key and row.thumbnail_storage_key ~= "" then
        row.thumbnail_url = "/" .. row.thumbnail_storage_key
    else
        row.thumbnail_url = nil
    end
    row.usage_count = tonumber(row.usage_count or 0) or 0
    row.in_use = row.usage_count > 0
    return row
end

-- アクティブなメディアをIDで取得します。
function _M.find_active(id)
    if not id then
        return nil, "メディアIDが指定されていません"
    end

    local query = string.format([[
        SELECT %s
        FROM media
        LEFT JOIN (
            SELECT media_id, COUNT(*) AS usage_count
            FROM media_post_usages
            GROUP BY media_id
        ) usage_counts ON usage_counts.media_id = media.id
        WHERE media.id = %s
          AND media.deleted_at IS NULL
        LIMIT 1
    ]], media_select_columns(), escape(tonumber(id)))

    local rows, err = db_config.query(query)
    if not rows then
        return nil, err
    end
    if #rows == 0 then
        return nil, "メディアが見つかりません"
    end

    return media_from_row(rows[1]), nil
end

-- SHA-256ハッシュで論理削除されていない既存メディアを取得します。
function _M.find_active_by_hash(sha256_hash)
    if not sha256_hash or sha256_hash == "" then
        return nil, "SHA-256ハッシュが指定されていません"
    end

    local query = string.format([[
        SELECT %s
        FROM media
        LEFT JOIN (
            SELECT media_id, COUNT(*) AS usage_count
            FROM media_post_usages
            GROUP BY media_id
        ) usage_counts ON usage_counts.media_id = media.id
        WHERE media.sha256_hash = %s
          AND media.deleted_at IS NULL
        LIMIT 1
    ]], media_select_columns(), escape(sha256_hash))

    local rows, err = db_config.query(query)
    if not rows then
        return nil, err
    end
    if #rows == 0 then
        return nil, nil
    end

    return media_from_row(rows[1]), nil
end

-- 保存キーでメディアを取得します。
function _M.find_active_by_storage_key(storage_key)
    if not storage_key or storage_key == "" then
        return nil, "保存キーが指定されていません"
    end

    local key = storage_key:gsub("^/", "")
    local query = string.format([[
        SELECT %s
        FROM media
        LEFT JOIN (
            SELECT media_id, COUNT(*) AS usage_count
            FROM media_post_usages
            GROUP BY media_id
        ) usage_counts ON usage_counts.media_id = media.id
        WHERE media.storage_key = %s
          AND media.deleted_at IS NULL
        LIMIT 1
    ]], media_select_columns(), escape(key))

    local rows, err = db_config.query(query)
    if not rows then
        return nil, err
    end
    if #rows == 0 then
        return nil, nil
    end

    return media_from_row(rows[1]), nil
end

-- メディア一覧をページネーション付きで取得します。
function _M.list_active(options)
    options = options or {}
    local page = math.max(tonumber(options.page) or 1, 1)
    local per_page = math.min(math.max(tonumber(options.per_page) or 20, 1), 100)
    local offset = (page - 1) * per_page
    local where = "media.deleted_at IS NULL"

    if options.q and options.q ~= "" then
        where = where .. " AND media.file_name ILIKE " .. escape(options.q .. "%")
    end

    local count_query = string.format("SELECT COUNT(*) AS count FROM media WHERE %s", where)
    local count_rows, count_err = db_config.query(count_query)
    if not count_rows then
        return nil, count_err
    end
    local total = tonumber(count_rows[1].count or 0) or 0

    local query = string.format([[
        SELECT %s
        FROM media
        LEFT JOIN (
            SELECT media_id, COUNT(*) AS usage_count
            FROM media_post_usages
            GROUP BY media_id
        ) usage_counts ON usage_counts.media_id = media.id
        WHERE %s
        ORDER BY media.created_at DESC, media.id DESC
        LIMIT %d OFFSET %d
    ]], media_select_columns(), where, per_page, offset)

    local rows, err = db_config.query(query)
    if not rows then
        return nil, err
    end

    for _, row in ipairs(rows) do
        media_from_row(row)
    end

    return {
        items = rows,
        pagination = {
            page = page,
            per_page = per_page,
            total = total,
            total_pages = math.ceil(total / per_page)
        }
    }, nil
end

-- 新しいメディアレコードを作成します。
function _M.create_media(data)
    data.storage_disk = data.storage_disk or "local"
    data.backup_status = data.backup_status or "disabled"
    local id, err = _M:create(data)
    if not id then
        return nil, err
    end
    return _M.find_active(id)
end

-- 表示ファイル名とaltテキストを更新します。
function _M.update_metadata(id, data)
    local update_data = {}
    if data.file_name ~= nil then
        update_data.file_name = data.file_name
    end
    if data.alt_text ~= nil then
        update_data.alt_text = data.alt_text
    end

    if next(update_data) == nil then
        return nil, "更新するデータがありません"
    end

    local ok, err = _M:update(id, update_data)
    if not ok then
        return nil, err
    end

    return _M.find_active(id)
end

-- 利用中メディアの削除を防ぎつつ論理削除します。
function _M.soft_delete(id)
    local media, err = _M.find_active(id)
    if not media then
        return false, err or "メディアが見つかりません", 404
    end
    if media.usage_count > 0 then
        return false, "参照中のメディアは削除できません", 409
    end

    local ok, update_err = _M:update(id, { deleted_at = os.date("%Y-%m-%d %H:%M:%S") })
    if not ok then
        return false, update_err, 500
    end

    return true, nil, 200
end

-- 記事本文の /uploads/... URL から利用状況を同期します。
function _M.sync_post_usages(post_id, content, db)
    if not post_id then
        return false, "投稿IDが指定されていません"
    end

    local urls = {}
    local seen = {}
    local body = content or ""
    for raw_url in body:gmatch("!?%[[^%]]*%]%(([^%)]+)%)") do
        local path = raw_url:gsub("#.*$", ""):gsub("%?.*$", "")
        path = path:gsub("^https?://[^/]+", "")
        path = path:gsub("^/", "")
        if path:match("^uploads/") and not seen[path] then
            seen[path] = true
            table.insert(urls, path)
        end
    end

    local delete_query = string.format(
        "DELETE FROM media_post_usages WHERE post_id = %s",
        escape(tonumber(post_id))
    )
    local res, err = db:query(delete_query)
    if not res then
        return false, err
    end

    for _, storage_key in ipairs(urls) do
        local insert_query = string.format([[
            INSERT INTO media_post_usages(media_id, post_id)
            SELECT id, %s
            FROM media
            WHERE storage_key = %s
              AND deleted_at IS NULL
            ON CONFLICT DO NOTHING
        ]], escape(tonumber(post_id)), escape(storage_key))
        local ok, insert_err = db:query(insert_query)
        if not ok then
            return false, insert_err
        end
    end

    return true, nil
end

return _M
