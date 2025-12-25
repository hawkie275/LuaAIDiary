-- タグモデル
-- タグの管理、投稿との関連付けを提供します

local Base = require("models.base")
local slug_util = require("utils.slug")
local validator = require("utils.validator")
local db_config = require("config.database")

local _M = Base.new("tags")

-- ========================================
-- タグ作成
-- ========================================

-- 新しいタグを作成
-- @param data タグデータ {name}
-- @return タグID、エラー
function _M.create_tag(data)
    -- バリデーション
    local ok, err = _M.validate_tag_data(data)
    if not ok then
        return nil, err
    end
    
    -- スラッグを生成
    local slug = data.slug
    if not slug or slug == "" then
        slug = slug_util.slugify(data.name)
    end
    
    -- ユニークなスラッグを生成
    slug = slug_util.generate_unique_slug(slug, _M, nil)
    
    -- タグデータを準備
    local tag_data = {
        name = data.name,
        slug = slug
    }
    
    return _M:create(tag_data)
end

-- ========================================
-- タグ更新
-- ========================================

-- タグを更新
-- @param id タグID
-- @param data 更新データ
-- @return 成功フラグ、エラー
function _M.update_tag(id, data)
    if not id then
        return false, "タグIDが指定されていません"
    end
    
    -- タグの存在確認
    local tag, err = _M:find(id)
    if not tag then
        return false, err or "タグが見つかりません"
    end
    
    -- スラッグが変更された場合はユニークチェック
    if data.slug and data.slug ~= tag.slug then
        data.slug = slug_util.generate_unique_slug(data.slug, _M, id)
    end
    
    -- 名前のバリデーション
    if data.name then
        local ok, err = validator.validate_length(data.name, 1, 50)
        if not ok then
            return false, err
        end
    end
    
    return _M:update(id, data)
end

-- ========================================
-- タグ検索
-- ========================================

-- スラッグでタグを検索
-- @param slug スラッグ
-- @return タグ情報、エラー
function _M.find_by_slug(slug)
    if not slug then
        return nil, "スラッグが指定されていません"
    end
    
    local tags, err = _M:find_by({slug = slug})
    if not tags then
        return nil, err
    end
    
    if #tags == 0 then
        return nil, "タグが見つかりません"
    end
    
    return tags[1], nil
end

-- 名前でタグを検索
-- @param name タグ名
-- @return タグ情報、エラー
function _M.find_by_name(name)
    if not name then
        return nil, "タグ名が指定されていません"
    end
    
    local tags, err = _M:find_by({name = name})
    if not tags then
        return nil, err
    end
    
    if #tags == 0 then
        return nil, "タグが見つかりません"
    end
    
    return tags[1], nil
end

-- タグを検索または作成
-- @param name タグ名
-- @return タグ情報、エラー
function _M.find_or_create(name)
    if not name or name == "" then
        return nil, "タグ名が空です"
    end
    
    -- 既存タグを検索
    local tag, err = _M.find_by_name(name)
    if tag then
        return tag, nil
    end
    
    -- 存在しない場合は作成
    local tag_id, err = _M.create_tag({name = name})
    if not tag_id then
        return nil, err
    end
    
    return _M:find(tag_id)
end

-- ========================================
-- 投稿との関連
-- ========================================

-- タグの投稿を取得
-- @param tag_id タグID
-- @param options オプション {limit, offset, published_only}
-- @return 投稿リスト、エラー
function _M.get_posts(tag_id, options)
    if not tag_id then
        return nil, "タグIDが指定されていません"
    end
    
    options = options or {}
    
    local status_clause = ""
    if options.published_only then
        status_clause = " AND posts.status = 'published'"
    end
    
    local query = string.format([[
        SELECT posts.* FROM posts
        INNER JOIN post_tags ON posts.id = post_tags.post_id
        WHERE post_tags.tag_id = %s%s
        ORDER BY %s
    ]], 
        db_config.escape(tostring(tag_id)),
        status_clause,
        options.order_by or "posts.published_at DESC"
    )
    
    if options.limit then
        query = query .. " LIMIT " .. tostring(options.limit)
    end
    
    if options.offset then
        query = query .. " OFFSET " .. tostring(options.offset)
    end
    
    return db_config.query(query)
end

-- タグの投稿数を取得
-- @param tag_id タグID
-- @param published_only 公開済みのみ
-- @return 投稿数、エラー
function _M.count_posts(tag_id, published_only)
    if not tag_id then
        return nil, "タグIDが指定されていません"
    end
    
    local status_clause = ""
    if published_only then
        status_clause = " AND posts.status = 'published'"
    end
    
    local query = string.format([[
        SELECT COUNT(*) as count FROM posts
        INNER JOIN post_tags ON posts.id = post_tags.post_id
        WHERE post_tags.tag_id = %s%s
    ]], 
        db_config.escape(tostring(tag_id)),
        status_clause
    )
    
    local res, err = db_config.query(query)
    if not res then
        return nil, err
    end
    
    return tonumber(res[1].count), nil
end

-- ========================================
-- タグクラウド
-- ========================================

-- タグクラウド用データを取得（投稿数付き）
-- @param options オプション {limit, min_posts, published_only}
-- @return タグリスト、エラー
function _M.get_tag_cloud(options)
    options = options or {}
    
    local status_clause = ""
    if options.published_only then
        status_clause = " AND posts.status = 'published'"
    end
    
    local min_posts_clause = ""
    if options.min_posts then
        min_posts_clause = string.format(" HAVING post_count >= %d", options.min_posts)
    end
    
    local query = string.format([[
        SELECT tags.*, COUNT(post_tags.post_id) as post_count
        FROM tags
        LEFT JOIN post_tags ON tags.id = post_tags.tag_id
        LEFT JOIN posts ON post_tags.post_id = posts.id%s
        GROUP BY tags.id
        %s
        ORDER BY post_count DESC, tags.name
    ]], 
        status_clause,
        min_posts_clause
    )
    
    if options.limit then
        query = query .. " LIMIT " .. tostring(options.limit)
    end
    
    return db_config.query(query)
end

-- 人気タグを取得
-- @param limit 取得件数
-- @param published_only 公開済みのみ
-- @return タグリスト、エラー
function _M.get_popular_tags(limit, published_only)
    limit = limit or 10
    
    return _M.get_tag_cloud({
        limit = limit,
        published_only = published_only,
        min_posts = 1
    })
end

-- ========================================
-- バリデーション
-- ========================================

-- タグデータをバリデーション
-- @param data タグデータ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_tag_data(data)
    if not data then
        return false, "データが空です"
    end
    
    -- 名前チェック
    if not data.name or data.name == "" then
        return false, "タグ名が必要です"
    end
    
    local ok, err = validator.validate_length(data.name, 1, 50)
    if not ok then
        return false, err
    end
    
    -- スラッグチェック（指定されている場合）
    if data.slug and data.slug ~= "" then
        ok, err = slug_util.is_valid_slug(data.slug)
        if not ok then
            return false, err
        end
    end
    
    return true, nil
end

-- ========================================
-- タグ削除
-- ========================================

-- タグを削除
-- @param id タグID
-- @param delete_relations 投稿との関連も削除するか（デフォルト: true）
-- @return 成功フラグ、エラー
function _M.delete_tag(id, delete_relations)
    if not id then
        return false, "タグIDが指定されていません"
    end
    
    if delete_relations == nil then
        delete_relations = true
    end
    
    if not delete_relations then
        -- 投稿との関連を確認
        local post_count, err = _M.count_posts(id)
        if post_count and post_count > 0 then
            return false, string.format("%d件の投稿が関連付けられています", post_count)
        end
    end
    
    return _M:delete(id)
end

-- 未使用タグを削除
-- @return 削除件数、エラー
function _M.delete_unused_tags()
    local query = [[
        DELETE FROM tags
        WHERE id NOT IN (
            SELECT DISTINCT tag_id FROM post_tags
        )
    ]]
    
    local res, err = db_config.query(query)
    if not res then
        return nil, err
    end
    
    return res.affected_rows or 0, nil
end

-- ========================================
-- タグのマージ
-- ========================================

-- タグをマージ（複数のタグを1つに統合）
-- @param source_ids マージ元タグIDの配列
-- @param target_id マージ先タグID
-- @return 成功フラグ、エラー
function _M.merge_tags(source_ids, target_id)
    if not source_ids or #source_ids == 0 then
        return false, "マージ元タグが指定されていません"
    end
    
    if not target_id then
        return false, "マージ先タグが指定されていません"
    end
    
    -- ターゲットタグの存在確認
    local target_exists = _M:exists(target_id)
    if not target_exists then
        return false, "マージ先タグが存在しません"
    end
    
    -- トランザクション内で処理
    local success, result = _M:transaction(function(db)
        for _, source_id in ipairs(source_ids) do
            if source_id ~= target_id then
                -- 投稿タグの関連をマージ先に変更
                local update_query = string.format([[
                    UPDATE IGNORE post_tags
                    SET tag_id = %s
                    WHERE tag_id = %s
                ]], 
                    db_config.escape(tostring(target_id)),
                    db_config.escape(tostring(source_id))
                )
                
                db:query(update_query)
                
                -- 重複を削除
                local delete_duplicate_query = string.format([[
                    DELETE FROM post_tags
                    WHERE tag_id = %s
                ]], db_config.escape(tostring(source_id)))
                
                db:query(delete_duplicate_query)
                
                -- 元のタグを削除
                _M:delete(source_id)
            end
        end
        
        return true
    end)
    
    return success, result
end

-- ========================================
-- ヘルパーメソッド
-- ========================================

-- タグ一覧を取得
-- @param options オプション {limit, offset, order_by}
-- @return タグリスト、エラー
function _M.get_all_tags(options)
    options = options or {}
    options.order_by = options.order_by or "name"
    return _M:all(options)
end

-- タグ数を取得
-- @return タグ数、エラー
function _M.count_tags()
    return _M:count()
end

-- タグ名の配列からタグIDの配列を取得（存在しないタグは作成）
-- @param tag_names タグ名の配列
-- @return タグIDの配列、エラー
function _M.get_or_create_by_names(tag_names)
    if not tag_names or #tag_names == 0 then
        return {}, nil
    end
    
    local tag_ids = {}
    
    for _, name in ipairs(tag_names) do
        local tag, err = _M.find_or_create(name)
        if tag then
            table.insert(tag_ids, tag.id)
        else
            ngx.log(ngx.WARN, "タグの作成に失敗しました: ", name, " - ", err or "")
        end
    end
    
    return tag_ids, nil
end

-- タグをカンマ区切り文字列から配列に変換
-- @param tag_string カンマ区切りのタグ文字列
-- @return タグ名の配列
function _M.parse_tag_string(tag_string)
    if not tag_string or tag_string == "" then
        return {}
    end
    
    local tags = {}
    for tag in tag_string:gmatch("[^,]+") do
        -- 前後の空白を削除
        tag = tag:match("^%s*(.-)%s*$")
        if tag and tag ~= "" then
            table.insert(tags, tag)
        end
    end
    
    return tags
end

return _M
