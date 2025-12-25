-- コメントモデル
-- コメントの管理、承認ステータス管理、スパムフィルタを提供します

local Base = require("models.base")
local validator = require("utils.validator")
local db_config = require("config.database")

local _M = Base.new("comments")

-- ========================================
-- コメント作成
-- ========================================

-- 新しいコメントを作成
-- @param data コメントデータ {post_id, user_id, author_name, author_email, content, parent_id}
-- @return コメントID、エラー
function _M.create_comment(data)
    -- バリデーション
    local ok, err = _M.validate_comment_data(data)
    if not ok then
        return nil, err
    end
    
    -- コメントデータを準備
    local comment_data = {
        post_id = data.post_id,
        user_id = data.user_id,
        author_name = data.author_name,
        author_email = data.author_email,
        content = data.content,
        status = data.status or "pending",
        parent_id = data.parent_id
    }
    
    -- スパムチェック
    local is_spam = _M.check_spam(comment_data)
    if is_spam then
        comment_data.status = "spam"
    end
    
    return _M:create(comment_data)
end

-- ========================================
-- コメント更新
-- ========================================

-- コメントを更新
-- @param id コメントID
-- @param data 更新データ
-- @return 成功フラグ、エラー
function _M.update_comment(id, data)
    if not id then
        return false, "コメントIDが指定されていません"
    end
    
    -- コメントの存在確認
    local comment, err = _M:find(id)
    if not comment then
        return false, err or "コメントが見つかりません"
    end
    
    -- 内容のバリデーション
    if data.content then
        local ok, err = validator.validate_length(data.content, 1, 65535)
        if not ok then
            return false, err
        end
    end
    
    return _M:update(id, data)
end

-- ========================================
-- コメント検索
-- ========================================

-- 投稿のコメントを取得
-- @param post_id 投稿ID
-- @param options オプション {status, limit, offset, order_by}
-- @return コメントリスト、エラー
function _M.find_by_post(post_id, options)
    if not post_id then
        return nil, "投稿IDが指定されていません"
    end
    
    options = options or {}
    
    local conditions = {post_id = post_id}
    
    -- ステータスフィルタ
    if options.status then
        conditions.status = options.status
    end
    
    local query_options = {
        limit = options.limit,
        offset = options.offset,
        order_by = options.order_by or "created_at ASC"
    }
    
    return _M:find_by(conditions, query_options)
end

-- 承認済みコメントを取得
-- @param post_id 投稿ID
-- @param options オプション {limit, offset}
-- @return コメントリスト、エラー
function _M.find_approved(post_id, options)
    options = options or {}
    options.status = "approved"
    return _M.find_by_post(post_id, options)
end

-- ユーザーのコメントを取得
-- @param user_id ユーザーID
-- @param options オプション {limit, offset, status}
-- @return コメントリスト、エラー
function _M.find_by_user(user_id, options)
    if not user_id then
        return nil, "ユーザーIDが指定されていません"
    end
    
    options = options or {}
    
    local conditions = {user_id = user_id}
    
    if options.status then
        conditions.status = options.status
    end
    
    local query_options = {
        limit = options.limit,
        offset = options.offset,
        order_by = options.order_by or "created_at DESC"
    }
    
    return _M:find_by(conditions, query_options)
end

-- ========================================
-- コメント階層構造（スレッド）
-- ========================================

-- コメントツリーを取得（ネスト構造）
-- @param post_id 投稿ID
-- @param status ステータスフィルタ（オプション）
-- @return コメントツリー、エラー
function _M.get_comment_tree(post_id, status)
    if not post_id then
        return nil, "投稿IDが指定されていません"
    end
    
    -- すべてのコメントを取得
    local options = {
        status = status,
        order_by = "created_at ASC"
    }
    
    local comments, err = _M.find_by_post(post_id, options)
    if not comments then
        return nil, err
    end
    
    -- コメントをIDでインデックス化
    local comment_map = {}
    for _, comment in ipairs(comments) do
        comment.children = {}
        comment_map[comment.id] = comment
    end
    
    -- ツリー構造を構築
    local tree = {}
    for _, comment in ipairs(comments) do
        if comment.parent_id and comment_map[comment.parent_id] then
            -- 親コメントの子として追加
            table.insert(comment_map[comment.parent_id].children, comment)
        else
            -- トップレベルコメント
            table.insert(tree, comment)
        end
    end
    
    return tree, nil
end

-- 子コメントを取得
-- @param parent_id 親コメントID
-- @return 子コメントリスト、エラー
function _M.get_children(parent_id)
    if not parent_id then
        return nil, "親コメントIDが指定されていません"
    end
    
    return _M:find_by({parent_id = parent_id}, {order_by = "created_at ASC"})
end

-- ========================================
-- ステータス管理
-- ========================================

-- コメントを承認
-- @param id コメントID
-- @return 成功フラグ、エラー
function _M.approve(id)
    return _M:update(id, {status = "approved"})
end

-- コメントを却下
-- @param id コメントID
-- @return 成功フラグ、エラー
function _M.reject(id)
    return _M:update(id, {status = "pending"})
end

-- コメントをスパムとしてマーク
-- @param id コメントID
-- @return 成功フラグ、エラー
function _M.mark_as_spam(id)
    return _M:update(id, {status = "spam"})
end

-- コメントをゴミ箱に移動
-- @param id コメントID
-- @return 成功フラグ、エラー
function _M.trash(id)
    return _M:update(id, {status = "trash"})
end

-- 一括承認
-- @param ids コメントIDの配列
-- @return 成功フラグ、エラー
function _M.bulk_approve(ids)
    if not ids or #ids == 0 then
        return false, "コメントIDが指定されていません"
    end
    
    local id_list = table.concat(ids, ",")
    local query = string.format(
        "UPDATE comments SET status = 'approved' WHERE id IN (%s)",
        id_list
    )
    
    local res, err = db_config.query(query)
    return res ~= nil, err
end

-- 一括削除
-- @param ids コメントIDの配列
-- @return 成功フラグ、エラー
function _M.bulk_delete(ids)
    if not ids or #ids == 0 then
        return false, "コメントIDが指定されていません"
    end
    
    local id_list = table.concat(ids, ",")
    local query = string.format(
        "DELETE FROM comments WHERE id IN (%s)",
        id_list
    )
    
    local res, err = db_config.query(query)
    return res ~= nil, err
end

-- ========================================
-- スパムフィルタ
-- ========================================

-- スパムチェック（簡易版）
-- @param comment_data コメントデータ
-- @return スパム判定結果（true/false）
function _M.check_spam(comment_data)
    if not comment_data or not comment_data.content then
        return false
    end
    
    local content = comment_data.content
    
    -- スパムキーワードリスト（簡易版）
    local spam_keywords = {
        "viagra", "cialis", "casino", "poker", "lottery",
        "pharmacy", "discount", "cheap", "free money"
    }
    
    -- 小文字に変換してチェック
    local lower_content = content:lower()
    
    for _, keyword in ipairs(spam_keywords) do
        if lower_content:find(keyword, 1, true) then
            return true
        end
    end
    
    -- URLの数をチェック（3つ以上でスパム疑い）
    local url_count = 0
    for _ in content:gmatch("https?://") do
        url_count = url_count + 1
    end
    
    if url_count >= 3 then
        return true
    end
    
    -- 連続する同じ文字をチェック
    if content:match("(..)%1%1%1") then
        return true
    end
    
    return false
end

-- ========================================
-- バリデーション
-- ========================================

-- コメントデータをバリデーション
-- @param data コメントデータ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_comment_data(data)
    if not data then
        return false, "データが空です"
    end
    
    -- 投稿IDチェック
    if not data.post_id then
        return false, "投稿IDが必要です"
    end
    
    local is_valid, post_id = validator.validate_positive_integer(data.post_id)
    if not is_valid then
        return false, "無効な投稿IDです"
    end
    
    -- 著者名チェック
    if not data.author_name or data.author_name == "" then
        return false, "著者名が必要です"
    end
    
    local ok, err = validator.validate_length(data.author_name, 1, 100)
    if not ok then
        return false, err
    end
    
    -- メールアドレスチェック
    if not data.author_email or data.author_email == "" then
        return false, "メールアドレスが必要です"
    end
    
    ok, err = validator.validate_email(data.author_email)
    if not ok then
        return false, err
    end
    
    -- コメント内容チェック
    if not data.content or data.content == "" then
        return false, "コメント内容が必要です"
    end
    
    ok, err = validator.validate_length(data.content, 1, 65535)
    if not ok then
        return false, err
    end
    
    -- ステータスチェック
    if data.status then
        local valid_statuses = {"pending", "approved", "spam", "trash"}
        ok, err = validator.validate_enum(data.status, valid_statuses)
        if not ok then
            return false, "無効なステータスです"
        end
    end
    
    -- 親コメントIDチェック
    if data.parent_id then
        is_valid, _ = validator.validate_positive_integer(data.parent_id)
        if not is_valid then
            return false, "無効な親コメントIDです"
        end
        
        -- 親コメントの存在確認
        local parent_exists = _M:exists(data.parent_id)
        if not parent_exists then
            return false, "指定された親コメントが存在しません"
        end
    end
    
    return true, nil
end

-- ========================================
-- 統計情報
-- ========================================

-- 投稿のコメント数を取得
-- @param post_id 投稿ID
-- @param status ステータスフィルタ（オプション）
-- @return コメント数、エラー
function _M.count_by_post(post_id, status)
    if not post_id then
        return nil, "投稿IDが指定されていません"
    end
    
    local conditions = {post_id = post_id}
    
    if status then
        conditions.status = status
    end
    
    return _M:count(conditions)
end

-- ステータス別コメント数を取得
-- @param status ステータス
-- @return コメント数、エラー
function _M.count_by_status(status)
    if not status then
        return nil, "ステータスが指定されていません"
    end
    
    return _M:count({status = status})
end

-- 承認待ちコメント数を取得
-- @return コメント数、エラー
function _M.count_pending()
    return _M.count_by_status("pending")
end

-- スパムコメント数を取得
-- @return コメント数、エラー
function _M.count_spam()
    return _M.count_by_status("spam")
end

-- ========================================
-- コメント削除
-- ========================================

-- コメントを削除（子コメントも削除）
-- @param id コメントID
-- @return 成功フラグ、エラー
function _M.delete_comment(id)
    if not id then
        return false, "コメントIDが指定されていません"
    end
    
    -- 子コメントも削除（CASCADE削除がDBで設定されている場合は不要）
    -- ここでは明示的に削除
    local children, err = _M.get_children(id)
    if children then
        for _, child in ipairs(children) do
            _M.delete_comment(child.id)
        end
    end
    
    return _M:delete(id)
end

-- 投稿のすべてのコメントを削除
-- @param post_id 投稿ID
-- @return 成功フラグ、エラー
function _M.delete_by_post(post_id)
    if not post_id then
        return false, "投稿IDが指定されていません"
    end
    
    local query = string.format(
        "DELETE FROM comments WHERE post_id = %s",
        db_config.escape(tostring(post_id))
    )
    
    local res, err = db_config.query(query)
    return res ~= nil, err
end

-- スパムコメントを一括削除
-- @return 削除件数、エラー
function _M.delete_spam()
    local query = "DELETE FROM comments WHERE status = 'spam'"
    
    local res, err = db_config.query(query)
    if not res then
        return nil, err
    end
    
    return res.affected_rows or 0, nil
end

-- ========================================
-- ヘルパーメソッド
-- ========================================

-- 最近のコメントを取得
-- @param limit 取得件数
-- @param approved_only 承認済みのみ
-- @return コメントリスト、エラー
function _M.get_recent_comments(limit, approved_only)
    limit = limit or 10
    
    local options = {
        limit = limit,
        order_by = "created_at DESC"
    }
    
    if approved_only then
        options.where = "status = 'approved'"
    end
    
    return _M:all(options)
end

-- コメントの深さを取得
-- @param id コメントID
-- @return 深さ（0がトップレベル）
function _M.get_depth(id)
    if not id then
        return 0
    end
    
    local depth = 0
    local current_id = id
    local max_depth = 10  -- 無限ループ防止
    
    while current_id and depth < max_depth do
        local comment, err = _M:find(current_id)
        if not comment or not comment.parent_id then
            break
        end
        
        current_id = comment.parent_id
        depth = depth + 1
    end
    
    return depth
end

return _M
