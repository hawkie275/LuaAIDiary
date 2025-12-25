-- カテゴリモデル
-- カテゴリの管理、階層構造サポート、投稿との関連付けを提供します

local Base = require("models.base")
local slug_util = require("utils.slug")
local validator = require("utils.validator")
local db_config = require("config.database")

local _M = Base.new("categories")

-- ========================================
-- カテゴリ作成
-- ========================================

-- 新しいカテゴリを作成
-- @param data カテゴリデータ {name, description, parent_id}
-- @return カテゴリID、エラー
function _M.create_category(data)
    -- バリデーション
    local ok, err = _M.validate_category_data(data)
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
    
    -- カテゴリデータを準備
    local category_data = {
        name = data.name,
        slug = slug,
        description = data.description or "",
        parent_id = data.parent_id
    }
    
    return _M:create(category_data)
end

-- ========================================
-- カテゴリ更新
-- ========================================

-- カテゴリを更新
-- @param id カテゴリID
-- @param data 更新データ
-- @return 成功フラグ、エラー
function _M.update_category(id, data)
    if not id then
        return false, "カテゴリIDが指定されていません"
    end
    
    -- カテゴリの存在確認
    local category, err = _M:find(id)
    if not category then
        return false, err or "カテゴリが見つかりません"
    end
    
    -- スラッグが変更された場合はユニークチェック
    if data.slug and data.slug ~= category.slug then
        data.slug = slug_util.generate_unique_slug(data.slug, _M, id)
    end
    
    -- 親カテゴリの循環参照チェック
    if data.parent_id then
        if data.parent_id == id then
            return false, "自分自身を親カテゴリにすることはできません"
        end
        
        local ok, err = _M.check_circular_reference(id, data.parent_id)
        if not ok then
            return false, err or "循環参照が発生します"
        end
    end
    
    return _M:update(id, data)
end

-- ========================================
-- カテゴリ検索
-- ========================================

-- スラッグでカテゴリを検索
-- @param slug スラッグ
-- @return カテゴリ情報、エラー
function _M.find_by_slug(slug)
    if not slug then
        return nil, "スラッグが指定されていません"
    end
    
    local categories, err = _M:find_by({slug = slug})
    if not categories then
        return nil, err
    end
    
    if #categories == 0 then
        return nil, "カテゴリが見つかりません"
    end
    
    return categories[1], nil
end

-- 親カテゴリで検索
-- @param parent_id 親カテゴリID（nilの場合はトップレベル）
-- @return カテゴリリスト、エラー
function _M.find_by_parent(parent_id)
    local conditions = {}
    
    if parent_id then
        conditions.parent_id = parent_id
    else
        -- トップレベルのカテゴリを取得
        return _M:find_by(conditions, {where = "parent_id IS NULL", order_by = "name"})
    end
    
    return _M:find_by(conditions, {order_by = "name"})
end

-- ========================================
-- 階層構造
-- ========================================

-- 子カテゴリを取得
-- @param parent_id 親カテゴリID
-- @return 子カテゴリリスト、エラー
function _M.get_children(parent_id)
    if not parent_id then
        return nil, "親カテゴリIDが指定されていません"
    end
    
    return _M:find_by({parent_id = parent_id}, {order_by = "name"})
end

-- カテゴリツリーを取得（再帰的）
-- @param parent_id 親カテゴリID（nilの場合はルートから）
-- @return カテゴリツリー、エラー
function _M.get_tree(parent_id)
    local categories, err
    
    if parent_id then
        categories, err = _M.get_children(parent_id)
    else
        categories, err = _M.find_by_parent(nil)
    end
    
    if not categories then
        return nil, err
    end
    
    -- 各カテゴリに子カテゴリを再帰的に追加
    for _, category in ipairs(categories) do
        category.children = _M.get_tree(category.id) or {}
    end
    
    return categories, nil
end

-- 親カテゴリのパスを取得（パンくずリスト用）
-- @param id カテゴリID
-- @return 親カテゴリの配列、エラー
function _M.get_ancestors(id)
    if not id then
        return nil, "カテゴリIDが指定されていません"
    end
    
    local ancestors = {}
    local current_id = id
    local max_depth = 10  -- 無限ループ防止
    local depth = 0
    
    while current_id and depth < max_depth do
        local category, err = _M:find(current_id)
        if not category then
            break
        end
        
        table.insert(ancestors, 1, category)
        current_id = category.parent_id
        depth = depth + 1
    end
    
    return ancestors, nil
end

-- 循環参照チェック
-- @param category_id カテゴリID
-- @param new_parent_id 新しい親カテゴリID
-- @return 検証結果（true/false）、エラーメッセージ
function _M.check_circular_reference(category_id, new_parent_id)
    if not new_parent_id then
        return true, nil
    end
    
    local current_id = new_parent_id
    local max_depth = 10
    local depth = 0
    
    while current_id and depth < max_depth do
        if current_id == category_id then
            return false, "循環参照が発生します"
        end
        
        local parent, err = _M:find(current_id)
        if not parent then
            break
        end
        
        current_id = parent.parent_id
        depth = depth + 1
    end
    
    return true, nil
end

-- ========================================
-- 投稿との関連
-- ========================================

-- カテゴリの投稿を取得
-- @param category_id カテゴリID
-- @param options オプション {limit, offset, published_only}
-- @return 投稿リスト、エラー
function _M.get_posts(category_id, options)
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
    
    return db_config.query(query)
end

-- カテゴリの投稿数を取得
-- @param category_id カテゴリID
-- @param published_only 公開済みのみ
-- @return 投稿数、エラー
function _M.count_posts(category_id, published_only)
    if not category_id then
        return nil, "カテゴリIDが指定されていません"
    end
    
    local status_clause = ""
    if published_only then
        status_clause = " AND posts.status = 'published'"
    end
    
    local query = string.format([[
        SELECT COUNT(*) as count FROM posts
        INNER JOIN post_categories ON posts.id = post_categories.post_id
        WHERE post_categories.category_id = %s%s
    ]], 
        db_config.escape(tostring(category_id)),
        status_clause
    )
    
    local res, err = db_config.query(query)
    if not res then
        return nil, err
    end
    
    return tonumber(res[1].count), nil
end

-- ========================================
-- バリデーション
-- ========================================

-- カテゴリデータをバリデーション
-- @param data カテゴリデータ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_category_data(data)
    if not data then
        return false, "データが空です"
    end
    
    -- 名前チェック
    if not data.name or data.name == "" then
        return false, "カテゴリ名が必要です"
    end
    
    local ok, err = validator.validate_length(data.name, 1, 100)
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
    
    -- 親カテゴリIDチェック
    if data.parent_id then
        local is_valid, parent_id = validator.validate_positive_integer(data.parent_id)
        if not is_valid then
            return false, "無効な親カテゴリIDです"
        end
        
        -- 親カテゴリの存在確認
        local parent_exists = _M:exists(parent_id)
        if not parent_exists then
            return false, "指定された親カテゴリが存在しません"
        end
    end
    
    return true, nil
end

-- ========================================
-- カテゴリ削除
-- ========================================

-- カテゴリを削除
-- @param id カテゴリID
-- @param delete_posts 投稿も削除するか（デフォルト: false）
-- @return 成功フラグ、エラー
function _M.delete_category(id, delete_posts)
    if not id then
        return false, "カテゴリIDが指定されていません"
    end
    
    -- 子カテゴリの確認
    local children, err = _M.get_children(id)
    if children and #children > 0 then
        return false, "子カテゴリが存在するため削除できません"
    end
    
    -- 投稿との関連を確認
    local post_count, err = _M.count_posts(id)
    if post_count and post_count > 0 and not delete_posts then
        return false, string.format("%d件の投稿が関連付けられています", post_count)
    end
    
    return _M:delete(id)
end

-- ========================================
-- ヘルパーメソッド
-- ========================================

-- カテゴリ一覧を取得
-- @param options オプション {limit, offset, order_by}
-- @return カテゴリリスト、エラー
function _M.get_all_categories(options)
    options = options or {}
    options.order_by = options.order_by or "name"
    return _M:all(options)
end

-- カテゴリ数を取得
-- @return カテゴリ数、エラー
function _M.count_categories()
    return _M:count()
end

-- トップレベルカテゴリを取得
-- @return カテゴリリスト、エラー
function _M.get_top_level_categories()
    return _M.find_by_parent(nil)
end

-- カテゴリの深さを取得
-- @param id カテゴリID
-- @return 深さ（0がトップレベル）
function _M.get_depth(id)
    local ancestors, err = _M.get_ancestors(id)
    if not ancestors then
        return 0
    end
    return #ancestors - 1
end

return _M
