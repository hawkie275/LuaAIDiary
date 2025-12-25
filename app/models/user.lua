-- ユーザーモデル
-- ユーザーの認証、管理、ロール制御を提供します

local Base = require("models.base")
local crypto = require("utils.crypto")
local validator = require("utils.validator")

local _M = Base.new("users")

-- ========================================
-- ユーザー作成
-- ========================================

-- 新しいユーザーを作成
-- @param data ユーザーデータ {username, email, password, display_name, role}
-- @return ユーザーID、エラー
function _M.create_user(data)
    -- バリデーション
    local ok, err = _M.validate_user_data(data)
    if not ok then
        return nil, err
    end
    
    -- パスワードをハッシュ化
    local password_hash, err = crypto.hash_password(data.password)
    if not password_hash then
        return nil, err or "パスワードのハッシュ化に失敗しました"
    end
    
    -- ユーザーデータを準備
    local user_data = {
        username = data.username,
        email = data.email,
        password_hash = password_hash,
        display_name = data.display_name or data.username,
        role = data.role or "subscriber"
    }
    
    -- データベースに挿入
    return _M:create(user_data)
end

-- ========================================
-- 認証
-- ========================================

-- ユーザー名とパスワードで認証
-- @param username ユーザー名
-- @param password パスワード
-- @return ユーザー情報、エラー
function _M.authenticate(username, password)
    if not username or not password then
        return nil, "ユーザー名またはパスワードが空です"
    end
    
    -- ユーザーを検索
    local user, err = _M.find_by_username(username)
    if not user then
        return nil, err or "ユーザーが見つかりません"
    end
    
    -- パスワードを検証
    if not crypto.verify_password(password, user.password_hash) then
        return nil, "パスワードが正しくありません"
    end
    
    -- パスワードハッシュを除外して返す
    user.password_hash = nil
    return user, nil
end

-- メールアドレスとパスワードで認証
-- @param email メールアドレス
-- @param password パスワード
-- @return ユーザー情報、エラー
function _M.authenticate_by_email(email, password)
    if not email or not password then
        return nil, "メールアドレスまたはパスワードが空です"
    end
    
    -- ユーザーを検索
    local user, err = _M.find_by_email(email)
    if not user then
        return nil, err or "ユーザーが見つかりません"
    end
    
    -- パスワードを検証
    if not crypto.verify_password(password, user.password_hash) then
        return nil, "パスワードが正しくありません"
    end
    
    -- パスワードハッシュを除外して返す
    user.password_hash = nil
    return user, nil
end

-- ========================================
-- ユーザー検索
-- ========================================

-- ユーザー名でユーザーを検索
-- @param username ユーザー名
-- @return ユーザー情報、エラー
function _M.find_by_username(username)
    if not username then
        return nil, "ユーザー名が指定されていません"
    end
    
    local users, err = _M:find_by({username = username})
    if not users then
        return nil, err
    end
    
    if #users == 0 then
        return nil, "ユーザーが見つかりません"
    end
    
    return users[1], nil
end

-- メールアドレスでユーザーを検索
-- @param email メールアドレス
-- @return ユーザー情報、エラー
function _M.find_by_email(email)
    if not email then
        return nil, "メールアドレスが指定されていません"
    end
    
    local users, err = _M:find_by({email = email})
    if not users then
        return nil, err
    end
    
    if #users == 0 then
        return nil, "ユーザーが見つかりません"
    end
    
    return users[1], nil
end

-- ロールでユーザーを検索
-- @param role ロール
-- @param options オプション {limit, offset, order_by}
-- @return ユーザーリスト、エラー
function _M.find_by_role(role, options)
    return _M:find_by({role = role}, options)
end

-- ========================================
-- ユーザー更新
-- ========================================

-- ユーザー情報を更新
-- @param id ユーザーID
-- @param data 更新データ
-- @return 成功フラグ、エラー
function _M.update_user(id, data)
    if not id then
        return false, "ユーザーIDが指定されていません"
    end
    
    -- パスワードが含まれている場合はハッシュ化
    if data.password then
        local password_hash, err = crypto.hash_password(data.password)
        if not password_hash then
            return false, err or "パスワードのハッシュ化に失敗しました"
        end
        data.password_hash = password_hash
        data.password = nil  -- 平文パスワードを削除
    end
    
    -- バリデーション（更新用）
    if data.email then
        local ok, err = validator.validate_email(data.email)
        if not ok then
            return false, err
        end
    end
    
    if data.username then
        local ok, err = validator.validate_username(data.username)
        if not ok then
            return false, err
        end
    end
    
    return _M:update(id, data)
end

-- パスワードを変更
-- @param id ユーザーID
-- @param old_password 現在のパスワード
-- @param new_password 新しいパスワード
-- @return 成功フラグ、エラー
function _M.change_password(id, old_password, new_password)
    if not id or not old_password or not new_password then
        return false, "必要なパラメータが不足しています"
    end
    
    -- ユーザーを取得
    local user, err = _M:find(id)
    if not user then
        return false, err or "ユーザーが見つかりません"
    end
    
    -- 現在のパスワードを検証
    if not crypto.verify_password(old_password, user.password_hash) then
        return false, "現在のパスワードが正しくありません"
    end
    
    -- 新しいパスワードをバリデーション
    local ok, err = validator.validate_password(new_password)
    if not ok then
        return false, err
    end
    
    -- 新しいパスワードをハッシュ化
    local password_hash, err = crypto.hash_password(new_password)
    if not password_hash then
        return false, err or "パスワードのハッシュ化に失敗しました"
    end
    
    -- パスワードを更新
    return _M:update(id, {password_hash = password_hash})
end

-- ========================================
-- ロール管理
-- ========================================

-- 有効なロール一覧
local VALID_ROLES = {"admin", "editor", "author", "subscriber"}

-- ロールを変更
-- @param id ユーザーID
-- @param role 新しいロール
-- @return 成功フラグ、エラー
function _M.change_role(id, role)
    if not id or not role then
        return false, "必要なパラメータが不足しています"
    end
    
    -- ロールのバリデーション
    local ok, err = validator.validate_enum(role, VALID_ROLES)
    if not ok then
        return false, "無効なロールです: " .. role
    end
    
    return _M:update(id, {role = role})
end

-- ユーザーが特定のロールを持っているか確認
-- @param id ユーザーID
-- @param role ロール
-- @return 確認結果（true/false）
function _M.has_role(id, role)
    local user, err = _M:find(id)
    if not user then
        return false
    end
    
    return user.role == role
end

-- ユーザーが管理者権限を持っているか確認
-- @param id ユーザーID
-- @return 確認結果（true/false）
function _M.is_admin(id)
    return _M.has_role(id, "admin")
end

-- ユーザーが編集者権限以上を持っているか確認
-- @param id ユーザーID
-- @return 確認結果（true/false）
function _M.can_edit(id)
    local user, err = _M:find(id)
    if not user then
        return false
    end
    
    return user.role == "admin" or user.role == "editor" or user.role == "author"
end

-- ========================================
-- バリデーション
-- ========================================

-- ユーザーデータをバリデーション
-- @param data ユーザーデータ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_user_data(data)
    if not data then
        return false, "データが空です"
    end
    
    -- ユーザー名チェック
    if not data.username then
        return false, "ユーザー名が必要です"
    end
    
    local ok, err = validator.validate_username(data.username)
    if not ok then
        return false, err
    end
    
    -- メールアドレスチェック
    if not data.email then
        return false, "メールアドレスが必要です"
    end
    
    ok, err = validator.validate_email(data.email)
    if not ok then
        return false, err
    end
    
    -- パスワードチェック（新規作成時のみ）
    if data.password then
        ok, err = validator.validate_password(data.password)
        if not ok then
            return false, err
        end
    end
    
    -- ロールチェック
    if data.role then
        ok, err = validator.validate_enum(data.role, VALID_ROLES)
        if not ok then
            return false, "無効なロールです"
        end
    end
    
    -- ユーザー名の重複チェック
    local existing_user, _ = _M.find_by_username(data.username)
    if existing_user and existing_user.id ~= data.id then
        return false, "このユーザー名は既に使用されています"
    end
    
    -- メールアドレスの重複チェック
    existing_user, _ = _M.find_by_email(data.email)
    if existing_user and existing_user.id ~= data.id then
        return false, "このメールアドレスは既に使用されています"
    end
    
    return true, nil
end

-- ========================================
-- ユーザー削除
-- ========================================

-- ユーザーを削除（ソフトデリート対応可能）
-- @param id ユーザーID
-- @return 成功フラグ、エラー
function _M.delete_user(id)
    if not id then
        return false, "ユーザーIDが指定されていません"
    end
    
    -- 管理者が1人だけの場合は削除不可
    local user, err = _M:find(id)
    if not user then
        return false, err or "ユーザーが見つかりません"
    end
    
    if user.role == "admin" then
        local admin_count, err = _M:count({role = "admin"})
        if admin_count and admin_count <= 1 then
            return false, "最後の管理者ユーザーは削除できません"
        end
    end
    
    return _M:delete(id)
end

-- ========================================
-- ユーザー一覧取得
-- ========================================

-- ユーザー一覧を取得（ページネーション対応）
-- @param options オプション {limit, offset, order_by, role}
-- @return ユーザーリスト、エラー
function _M.get_users(options)
    options = options or {}
    
    if options.role then
        return _M.find_by_role(options.role, options)
    end
    
    return _M:all(options)
end

-- ユーザー数を取得
-- @param role ロール（オプション）
-- @return ユーザー数、エラー
function _M.count_users(role)
    if role then
        return _M:count({role = role})
    end
    return _M:count()
end

-- ========================================
-- セーフなユーザー情報取得
-- ========================================

-- パスワードハッシュを除外したユーザー情報を取得
-- @param id ユーザーID
-- @return ユーザー情報、エラー
function _M.get_safe_user(id)
    local user, err = _M:find(id)
    if not user then
        return nil, err
    end
    
    -- パスワードハッシュを除外
    user.password_hash = nil
    return user, nil
end

return _M
