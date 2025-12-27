-- 投稿モデル
-- ブログ記事の作成、更新、検索、カテゴリ・タグ管理を提供します

local Base = require("models.base")
local slug_util = require("utils.slug")
local validator = require("utils.validator")
local db_config = require("config.database")

local _M = Base.new("posts")

-- ========================================
-- 投稿作成
-- ========================================

-- 新しい投稿を作成
-- @param data 投稿データ {title, content, excerpt, author_id, status, categories, tags}
-- @return 投稿ID、エラー
function _M.create_post(data)
    -- バリデーション
    local ok, err = _M.validate_post_data(data)
    if not ok then
        return nil, err
    end
    
    -- スラッグを生成
    local slug = data.slug
    if not slug or slug == "" then
        slug = slug_util.slugify(data.title)
    end
    
    -- 予約語を回避
    slug = slug_util.avoid_reserved(slug)
    
    -- ユニークなスラッグを生成
    slug = slug_util.generate_unique_slug(slug, _M, nil)
    
    -- 投稿データを準備
    local post_data = {
        title = data.title,
        slug = slug,
        content = data.content or "",
        excerpt = data.excerpt or "",
        author_id = data.author_id,
        status = data.status or "draft"
    }
    
    -- 公開済みの場合は公開日時を設定
    if post_data.status == "published" and not data.published_at then
        post_data.published_at = os.date("%Y-%m-%d %H:%M:%S")
    end
    
    -- トランザクション内で投稿とカテゴリ・タグを保存
    local success, result = _M:transaction(function(db)
        -- 投稿を作成
        local post_id, err = _M:create(post_data)
        if not post_id then
            error(err or "投稿の作成に失敗しました")
        end
        
        -- カテゴリを関連付け
        if data.categories and #data.categories > 0 then
            for _, category_id in ipairs(data.categories) do
                _M.add_category(post_id, category_id, db)
            end
        end
        
        -- タグを関連付け
        if data.tags and #data.tags > 0 then
            for _, tag_id in ipairs(data.tags) do
                _M.add_tag(post_id, tag_id, db)
            end
        end
        
        return post_id
    end)
    
    if not success then
        return nil, result
    end
    
    return result, nil
end

-- ========================================
-- 投稿更新
-- ========================================

-- 投稿を更新
-- @param id 投稿ID
-- @param data 更新データ
-- @return 成功フラグ、エラー
function _M.update_post(id, data)
    if not id then
        return false, "投稿IDが指定されていません"
    end
    
    -- 投稿の存在確認
    local post, err = _M:find(id)
    if not post then
        return false, err or "投稿が見つかりません"
    end
    
    -- スラッグが変更された場合はユニークチェック
    if data.slug and data.slug ~= post.slug then
        data.slug = slug_util.generate_unique_slug(data.slug, _M, id)
    end
    
    -- ステータスが公開に変更された場合、公開日時を設定
    if data.status == "published" and post.status ~= "published" then
        data.published_at = os.date("%Y-%m-%d %H:%M:%S")
    end
    
    -- トランザクション内で更新
    local success, result = _M:transaction(function(db)
        -- カテゴリとタグを別途保存
        local categories = data.categories
        local tags = data.tags
        
        -- 基本情報のみを抽出（postsテーブルのカラムのみ）
        local post_data = {
            title = data.title,
            content = data.content,
            excerpt = data.excerpt,
            status = data.status,
            slug = data.slug,
            published_at = data.published_at
        }
        
        -- 基本情報を更新
        local ok, err = _M:update(id, post_data)
        if not ok then
            error(err or "投稿の更新に失敗しました")
        end
        
        -- カテゴリを更新
        if categories then
            _M.sync_categories(id, categories, db)
        end
        
        -- タグを更新
        if tags then
            _M.sync_tags(id, tags, db)
        end
        
        return true
    end)
    
    return success, result
end

-- ========================================
-- 投稿検索
-- ========================================

-- スラッグで投稿を検索
-- @param slug スラッグ
-- @return 投稿情報、エラー
function _M.find_by_slug(slug)
    if not slug then
        return nil, "スラッグが指定されていません"
    end
    
    local posts, err = _M:find_by({slug = slug})
    if not posts then
        return nil, err
    end
    
    if #posts == 0 then
        return nil, "投稿が見つかりません"
    end
    
    local post = posts[1]
    
    -- カテゴリとタグを取得
    post.categories = _M.get_categories(post.id)
    post.tags = _M.get_tags(post.id)
    
    return post, nil
end

-- 公開済み投稿を取得
-- @param options オプション {limit, offset, order_by}
-- @return 投稿リスト、エラー
function _M.find_published(options)
    options = options or {}
    options.where = "status = 'published'"
    options.order_by = options.order_by or "published_at DESC"
    
    local posts, err = _M:all(options)
    
    if not posts then
        return nil, err
    end
    
    -- 各投稿にカテゴリとタグを付与
    for _, post in ipairs(posts) do
        post.categories = _M.get_categories(post.id)
        post.tags = _M.get_tags(post.id)
    end
    
    return posts, nil
end

-- カテゴリで投稿を検索
-- @param category_id カテゴリID
-- @param options オプション {limit, offset, published_only}
-- @return 投稿リスト、エラー
function _M.find_by_category(category_id, options)
    if not category_id then
        return nil, "カテゴリIDが指定されていません"
    end
    
    options = options or {}
    
    local status_clause = ""
    if options.published_only then
        status_clause = " AND posts.status = 'published'"
    end
    
    local query = string.format([[
        SELECT posts.* FROM posts
        INNER JOIN post_categories ON posts.id = post_categories.post_id
        WHERE post_categories.category_id = %s%s
        ORDER BY %s
    ]], 
        db_config.escape(tostring(category_id)),
        status_clause,
        options.order_by or "posts.published_at DESC"
    )
    
    if options.limit then
        query = query .. " LIMIT " .. tostring(options.limit)
    end
    
    if options.offset then
        query = query .. " OFFSET " .. tostring(options.offset)
    end
    
    local posts, err = _M:raw_query(query)
    if not posts then
        return nil, err
    end
    
    -- 各投稿にカテゴリとタグを付与
    for _, post in ipairs(posts) do
        post.categories = _M.get_categories(post.id)
        post.tags = _M.get_tags(post.id)
    end
    
    return posts, nil
end

-- タグで投稿を検索
-- @param tag_id タグID
-- @param options オプション {limit, offset, published_only}
-- @return 投稿リスト、エラー
function _M.find_by_tag(tag_id, options)
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
    
    local posts, err = _M:raw_query(query)
    if not posts then
        return nil, err
    end
    
    -- 各投稿にカテゴリとタグを付与
    for _, post in ipairs(posts) do
        post.categories = _M.get_categories(post.id)
        post.tags = _M.get_tags(post.id)
    end
    
    return posts, nil
end

-- 全文検索
-- @param keyword 検索キーワード
-- @param options オプション {limit, offset, published_only}
-- @return 投稿リスト、エラー
function _M.search(keyword, options)
    if not keyword or keyword == "" then
        return nil, "検索キーワードが空です"
    end
    
    options = options or {}
    
    local status_clause = ""
    if options.published_only then
        status_clause = " AND status = 'published'"
    end
    
    local query = string.format([[
        SELECT * FROM posts
        WHERE to_tsvector('english', title || ' ' || content) @@ to_tsquery('english', %s)%s
        ORDER BY %s
    ]],
        db_config.escape(keyword),
        status_clause,
        options.order_by or "published_at DESC"
    )
    
    if options.limit then
        query = query .. " LIMIT " .. tostring(options.limit)
    end
    
    if options.offset then
        query = query .. " OFFSET " .. tostring(options.offset)
    end
    
    local posts, err = _M:raw_query(query)
    if not posts then
        return nil, err
    end
    
    -- 各投稿にカテゴリとタグを付与
    for _, post in ipairs(posts) do
        post.categories = _M.get_categories(post.id)
        post.tags = _M.get_tags(post.id)
    end
    
    return posts, nil
end

-- ========================================
-- カテゴリ管理
-- ========================================

-- 投稿にカテゴリを追加
-- @param post_id 投稿ID
-- @param category_id カテゴリID
-- @param db データベース接続（オプション）
-- @return 成功フラグ、エラー
function _M.add_category(post_id, category_id, db)
    local query = string.format([[
        INSERT INTO post_categories (post_id, category_id)
        VALUES (%s, %s)
        ON CONFLICT DO NOTHING
    ]],
        db_config.escape(tostring(post_id)),
        db_config.escape(tostring(category_id))
    )
    
    if db then
        return db:query(query)
    else
        return db_config.query(query)
    end
end

-- 投稿からカテゴリを削除
-- @param post_id 投稿ID
-- @param category_id カテゴリID
-- @param db データベース接続（オプション）
-- @return 成功フラグ、エラー
function _M.remove_category(post_id, category_id, db)
    local query = string.format([[
        DELETE FROM post_categories
        WHERE post_id = %s AND category_id = %s
    ]], 
        db_config.escape(tostring(post_id)),
        db_config.escape(tostring(category_id))
    )
    
    if db then
        return db:query(query)
    else
        return db_config.query(query)
    end
end

-- 投稿のカテゴリを同期
-- @param post_id 投稿ID
-- @param category_ids カテゴリIDの配列
-- @param db データベース接続（オプション）
function _M.sync_categories(post_id, category_ids, db)
    -- 既存のカテゴリをすべて削除
    local delete_query = string.format(
        "DELETE FROM post_categories WHERE post_id = %s",
        db_config.escape(tostring(post_id))
    )
    
    if db then
        db:query(delete_query)
    else
        db_config.query(delete_query)
    end
    
    -- 新しいカテゴリを追加
    if category_ids and #category_ids > 0 then
        for _, category_id in ipairs(category_ids) do
            _M.add_category(post_id, category_id, db)
        end
    end
end

-- 投稿のカテゴリを取得
-- @param post_id 投稿ID
-- @return カテゴリリスト
function _M.get_categories(post_id)
    local query = string.format([[
        SELECT categories.* FROM categories
        INNER JOIN post_categories ON categories.id = post_categories.category_id
        WHERE post_categories.post_id = %s
        ORDER BY categories.name
    ]], db_config.escape(tostring(post_id)))
    
    local categories, err = db_config.query(query)
    if not categories then
        ngx.log(ngx.ERR, "カテゴリ取得エラー: ", err)
        return {}
    end
    
    return categories
end

-- ========================================
-- タグ管理
-- ========================================

-- 投稿にタグを追加
-- @param post_id 投稿ID
-- @param tag_id タグID
-- @param db データベース接続（オプション）
-- @return 成功フラグ、エラー
function _M.add_tag(post_id, tag_id, db)
    local query = string.format([[
        INSERT INTO post_tags (post_id, tag_id)
        VALUES (%s, %s)
        ON CONFLICT DO NOTHING
    ]],
        db_config.escape(tostring(post_id)),
        db_config.escape(tostring(tag_id))
    )
    
    if db then
        return db:query(query)
    else
        return db_config.query(query)
    end
end

-- 投稿からタグを削除
-- @param post_id 投稿ID
-- @param tag_id タグID
-- @param db データベース接続（オプション）
-- @return 成功フラグ、エラー
function _M.remove_tag(post_id, tag_id, db)
    local query = string.format([[
        DELETE FROM post_tags
        WHERE post_id = %s AND tag_id = %s
    ]], 
        db_config.escape(tostring(post_id)),
        db_config.escape(tostring(tag_id))
    )
    
    if db then
        return db:query(query)
    else
        return db_config.query(query)
    end
end

-- 投稿のタグを同期
-- @param post_id 投稿ID
-- @param tag_ids タグIDの配列
-- @param db データベース接続（オプション）
function _M.sync_tags(post_id, tag_ids, db)
    -- 既存のタグをすべて削除
    local delete_query = string.format(
        "DELETE FROM post_tags WHERE post_id = %s",
        db_config.escape(tostring(post_id))
    )
    
    if db then
        db:query(delete_query)
    else
        db_config.query(delete_query)
    end
    
    -- 新しいタグを追加
    if tag_ids and #tag_ids > 0 then
        for _, tag_id in ipairs(tag_ids) do
            _M.add_tag(post_id, tag_id, db)
        end
    end
end

-- 投稿のタグを取得
-- @param post_id 投稿ID
-- @return タグリスト
function _M.get_tags(post_id)
    local query = string.format([[
        SELECT tags.* FROM tags
        INNER JOIN post_tags ON tags.id = post_tags.tag_id
        WHERE post_tags.post_id = %s
        ORDER BY tags.name
    ]], db_config.escape(tostring(post_id)))
    
    local tags, err = db_config.query(query)
    if not tags then
        ngx.log(ngx.ERR, "タグ取得エラー: ", err)
        return {}
    end
    
    return tags
end

-- 複数投稿のカテゴリを一括取得（N+1問題対策）
-- @param post_ids 投稿IDの配列
-- @return 投稿IDをキーとするカテゴリマップ {post_id: [categories]}
function _M.get_categories_batch(post_ids)
    if not post_ids or #post_ids == 0 then
        return {}
    end
    
    -- IDリストを作成
    local id_list = {}
    for _, id in ipairs(post_ids) do
        table.insert(id_list, db_config.escape(tostring(id)))
    end
    
    local query = string.format([[
        SELECT
            post_categories.post_id,
            categories.id,
            categories.name,
            categories.slug,
            categories.description,
            categories.created_at
        FROM categories
        INNER JOIN post_categories ON categories.id = post_categories.category_id
        WHERE post_categories.post_id IN (%s)
        ORDER BY post_categories.post_id, categories.name
    ]], table.concat(id_list, ", "))
    
    local results, err = db_config.query(query)
    if not results then
        ngx.log(ngx.ERR, "カテゴリ一括取得エラー: ", err)
        return {}
    end
    
    -- 投稿IDごとにグループ化
    local category_map = {}
    for _, post_id in ipairs(post_ids) do
        category_map[tostring(post_id)] = {}
    end
    
    for _, row in ipairs(results) do
        local post_id = tostring(row.post_id)
        if not category_map[post_id] then
            category_map[post_id] = {}
        end
        table.insert(category_map[post_id], {
            id = row.id,
            name = row.name,
            slug = row.slug,
            description = row.description,
            created_at = row.created_at
        })
    end
    
    return category_map
end

-- 複数投稿のタグを一括取得（N+1問題対策）
-- @param post_ids 投稿IDの配列
-- @return 投稿IDをキーとするタグマップ {post_id: [tags]}
function _M.get_tags_batch(post_ids)
    if not post_ids or #post_ids == 0 then
        return {}
    end
    
    -- IDリストを作成
    local id_list = {}
    for _, id in ipairs(post_ids) do
        table.insert(id_list, db_config.escape(tostring(id)))
    end
    
    local query = string.format([[
        SELECT
            post_tags.post_id,
            tags.id,
            tags.name,
            tags.slug,
            tags.created_at
        FROM tags
        INNER JOIN post_tags ON tags.id = post_tags.tag_id
        WHERE post_tags.post_id IN (%s)
        ORDER BY post_tags.post_id, tags.name
    ]], table.concat(id_list, ", "))
    
    local results, err = db_config.query(query)
    if not results then
        ngx.log(ngx.ERR, "タグ一括取得エラー: ", err)
        return {}
    end
    
    -- 投稿IDごとにグループ化
    local tag_map = {}
    for _, post_id in ipairs(post_ids) do
        tag_map[tostring(post_id)] = {}
    end
    
    for _, row in ipairs(results) do
        local post_id = tostring(row.post_id)
        if not tag_map[post_id] then
            tag_map[post_id] = {}
        end
        table.insert(tag_map[post_id], {
            id = row.id,
            name = row.name,
            slug = row.slug,
            created_at = row.created_at
        })
    end
    
    return tag_map
end

-- ========================================
-- バリデーション
-- ========================================

-- 投稿データをバリデーション
-- @param data 投稿データ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_post_data(data)
    if not data then
        return false, "データが空です"
    end
    
    -- タイトルチェック
    if not data.title or data.title == "" then
        return false, "タイトルが必要です"
    end
    
    local ok, err = validator.validate_length(data.title, 1, 255)
    if not ok then
        return false, err
    end
    
    -- 著者IDチェック
    if not data.author_id then
        return false, "著者IDが必要です"
    end
    
    local is_valid, author_id = validator.validate_positive_integer(data.author_id)
    if not is_valid then
        return false, "無効な著者IDです"
    end
    
    -- ステータスチェック
    if data.status then
        local valid_statuses = {"draft", "published", "trash"}
        ok, err = validator.validate_enum(data.status, valid_statuses)
        if not ok then
            return false, "無効なステータスです"
        end
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
-- ヘルパーメソッド
-- ========================================

-- 投稿数を取得
-- @param status ステータス（オプション）
-- @return 投稿数、エラー
function _M.count_posts(status)
    if status then
        return _M:count({status = status})
    end
    return _M:count()
end

-- 最新の投稿を取得
-- @param limit 取得件数
-- @param published_only 公開済みのみ
-- @return 投稿リスト、エラー
function _M.get_recent_posts(limit, published_only)
    limit = limit or 10
    
    local options = {
        limit = limit,
        order_by = "published_at DESC"
    }
    
    if published_only then
        return _M.find_published(options)
    else
        return _M:all(options)
    end
end

return _M
