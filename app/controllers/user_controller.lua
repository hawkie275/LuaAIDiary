-- app/controllers/user_controller.lua
-- ユーザー管理コントローラー - 管理者用ユーザー管理機能

local Session = require("utils.session")
local User = require("models.user")
local csrf = require("middleware.csrf")
local db_config = require("config.database")
local etlua = require("etlua")

local UserController = {}

-- ========================================
-- ヘルパー関数
-- ========================================

-- セッションから認証されたユーザーを取得
local function get_authenticated_user()
    local session = Session.new()
    local ok = session:start()
    
    if not ok or not session:is_authenticated() then
        return nil, nil, "認証が必要です"
    end
    
    local user_id = session:get_user_id()
    if not user_id then
        return nil, nil, "ユーザー情報の取得に失敗しました"
    end
    
    local user = session:get_user()
    if not user then
        return nil, nil, "ユーザー情報の取得に失敗しました"
    end
    
    return user, session, nil
end

-- 管理者権限チェック（adminのみ）
local function check_user_management_permission(user)
    if not user then
        return false
    end
    
    -- admin ロールのみ許可
    if user.role == "admin" then
        return true
    end
    
    return false
end

-- 管理画面テンプレートのレンダリング
local function render_admin_template(template_name, data)
    local template_path = string.format("/app/views/admin/%s.etlua", template_name)
    local layout_path = "/app/views/admin/layout.etlua"
    
    -- テンプレートとレイアウトを読み込み
    local template_file = io.open(template_path, "r")
    if not template_file then
        ngx.log(ngx.ERR, "テンプレートファイルが見つかりません: ", template_path)
        ngx.status = 500
        return "テンプレートファイルが見つかりません"
    end
    local template_content = template_file:read("*all")
    template_file:close()
    
    local layout_file = io.open(layout_path, "r")
    if not layout_file then
        ngx.log(ngx.ERR, "レイアウトファイルが見つかりません: ", layout_path)
        ngx.status = 500
        return "レイアウトファイルが見つかりません"
    end
    local layout_content = layout_file:read("*all")
    layout_file:close()
    
    -- テンプレートをコンパイル
    local template = etlua.compile(template_content)
    local layout = etlua.compile(layout_content)
    
    -- データに_VERSIONを追加
    data._VERSION = _VERSION
    
    -- テンプレートをレンダリング
    local content = template(data)
    
    -- レイアウトデータを準備
    local layout_data = {
        user = data.user,
        csrf_token = data.csrf_token,
        content_for_layout = content,
        page_title = data.page_title or template_name,
        active_menu = data.active_menu or "users",
        success_message = data.success_message,
        error_message = data.error_message,
        _VERSION = _VERSION
    }
    
    -- レイアウトをレンダリング
    local html = layout(layout_data)
    
    return html
end

-- エラーページのレンダリング
local function render_error(title, message)
    ngx.header.content_type = "text/html; charset=utf-8"
    return string.format([[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s - LuaAIDiary</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d9534f; }
        p { color: #666; }
        a { color: #337ab7; text-decoration: none; }
    </style>
</head>
<body>
    <h1>%s</h1>
    <p>%s</p>
    <p><a href="/admin/users">ユーザー管理に戻る</a></p>
</body>
</html>
]], title, title, message)
end

-- ========================================
-- コントローラーアクション
-- ========================================

-- ユーザー一覧表示
-- GET /admin/users
function UserController:index(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login?redirect=/admin/users", status = 302 }
    end
    
    -- 管理者権限チェック
    if not check_user_management_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "ユーザー管理機能は管理者のみ利用できます")
    end
    
    -- クエリパラメータ取得
    local args = self.req.params_get or {}
    local role_filter = args.role or "all"
    local page = tonumber(args.page) or 1
    local per_page = 20
    local offset = (page - 1) * per_page
    
    -- ユーザー一覧を取得（投稿数も含む）
    local query = string.format([[
        SELECT u.id, u.username, u.email, u.display_name, u.role, u.created_at,
               COUNT(p.id) as post_count
        FROM users u
        LEFT JOIN posts p ON u.id = p.author_id
        %s
        GROUP BY u.id, u.username, u.email, u.display_name, u.role, u.created_at
        ORDER BY u.created_at DESC
        LIMIT %d OFFSET %d
    ]],
        role_filter ~= "all" and string.format("WHERE u.role = '%s'", db_config.escape(role_filter)) or "",
        per_page,
        offset
    )
    
    local users, err = db_config.query(query)
    if not users then
        users = {}
        ngx.log(ngx.ERR, "ユーザー一覧取得エラー: ", err or "unknown")
    end
    
    -- 総ユーザー数を取得
    local count_query = string.format([[
        SELECT COUNT(*) as total FROM users
        %s
    ]],
        role_filter ~= "all" and string.format("WHERE role = '%s'", db_config.escape(role_filter)) or ""
    )
    
    local count_result = db_config.query(count_query)
    local total_count = count_result and count_result[1] and count_result[1].total or 0
    local total_pages = math.ceil(total_count / per_page)
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- 成功メッセージの確認
    local success_message = nil
    if args.created == "1" then
        success_message = "ユーザーを作成しました"
    elseif args.updated == "1" then
        success_message = "ユーザー情報を更新しました"
    elseif args.deleted == "1" then
        success_message = "ユーザーを削除しました"
    end
    
    -- テンプレートをレンダリング
    return render_admin_template("users/index", {
        user = user,
        csrf_token = csrf_token,
        users = users,
        role_filter = role_filter,
        pagination = {
            current_page = page,
            total_pages = total_pages,
            total_count = total_count,
            per_page = per_page
        },
        success_message = success_message,
        page_title = "ユーザー管理",
        active_menu = "users"
    })
end

-- 新規ユーザー作成フォーム表示
-- GET /admin/users/new
function UserController:new(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login?redirect=/admin/users/new", status = 302 }
    end
    
    -- 管理者権限チェック
    if not check_user_management_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "ユーザー管理機能は管理者のみ利用できます")
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- テンプレートをレンダリング
    return render_admin_template("users/new", {
        user = user,
        csrf_token = csrf_token,
        roles = {"admin", "editor", "author", "subscriber"},
        error_message = nil,
        page_title = "新規ユーザー作成",
        active_menu = "users"
    })
end

-- 新規ユーザー作成処理
-- POST /admin/users/create
function UserController:create(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- 管理者権限チェック
    if not check_user_management_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "ユーザー管理機能は管理者のみ利用できます")
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        ngx.log(ngx.ERR, "CSRF検証失敗: ", csrf_err or "unknown")
        return render_error("403 Forbidden", "CSRF検証に失敗しました")
    end
    
    -- フォームデータ取得
    local user_data = {
        username = self.params.username,
        email = self.params.email,
        password = self.params.password,
        display_name = self.params.display_name,
        role = self.params.role or "subscriber"
    }
    
    -- バリデーション
    local ok, validation_err = User.validate_user_data(user_data)
    if not ok then
        local csrf_token = csrf.generate_token(session)
        return render_admin_template("users/new", {
            user = user,
            csrf_token = csrf_token,
            roles = {"admin", "editor", "author", "subscriber"},
            error_message = validation_err,
            form_data = user_data,
            page_title = "新規ユーザー作成",
            active_menu = "users"
        })
    end
    
    -- ユーザー作成
    local user_id, create_err = User.create_user(user_data)
    if not user_id then
        local csrf_token = csrf.generate_token(session)
        return render_admin_template("users/new", {
            user = user,
            csrf_token = csrf_token,
            roles = {"admin", "editor", "author", "subscriber"},
            error_message = create_err or "ユーザーの作成に失敗しました",
            form_data = user_data,
            page_title = "新規ユーザー作成",
            active_menu = "users"
        })
    end
    
    -- 成功時はユーザー一覧にリダイレクト
    return { redirect_to = "/admin/users?created=1", status = 302 }
end

-- ユーザー編集フォーム表示
-- GET /admin/users/:id/edit
function UserController:edit(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- 管理者権限チェック
    if not check_user_management_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "ユーザー管理機能は管理者のみ利用できます")
    end
    
    -- ユーザーIDを取得
    local user_id = tonumber(self.params.id)
    if not user_id then
        return { redirect_to = "/admin/users", status = 302 }
    end
    
    -- ユーザーを取得
    local edit_user, err = User:find(user_id)
    if not edit_user then
        return { redirect_to = "/admin/users", status = 302 }
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- 成功メッセージの確認
    local args = self.req.params_get or {}
    local success_message = nil
    if args.updated == "1" then
        success_message = "ユーザー情報を更新しました"
    end
    
    -- テンプレートをレンダリング
    return render_admin_template("users/edit", {
        user = user,
        csrf_token = csrf_token,
        edit_user = edit_user,
        roles = {"admin", "editor", "author", "subscriber"},
        error_message = nil,
        success_message = success_message,
        page_title = "ユーザー編集",
        active_menu = "users"
    })
end

-- ユーザー更新処理
-- POST /admin/users/:id/update
function UserController:update(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- 管理者権限チェック
    if not check_user_management_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "ユーザー管理機能は管理者のみ利用できます")
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        ngx.log(ngx.ERR, "CSRF検証失敗: ", csrf_err or "unknown")
        return render_error("403 Forbidden", "CSRF検証に失敗しました")
    end
    
    -- ユーザーIDを取得
    local user_id = tonumber(self.params.id)
    if not user_id then
        return { redirect_to = "/admin/users", status = 302 }
    end
    
    -- 更新データを準備
    local update_data = {
        username = self.params.username,
        email = self.params.email,
        display_name = self.params.display_name,
        role = self.params.role
    }
    
    -- パスワードが入力されている場合のみ含める
    if self.params.password and self.params.password ~= "" then
        update_data.password = self.params.password
    end
    
    -- 最後の管理者のロール変更を防止
    if update_data.role ~= "admin" then
        local target_user = User:find(user_id)
        if target_user and target_user.role == "admin" then
            local admin_count = User:count({role = "admin"})
            if admin_count and admin_count <= 1 then
                local csrf_token = csrf.generate_token(session)
                local edit_user = User:find(user_id)
                return render_admin_template("users/edit", {
                    user = user,
                    csrf_token = csrf_token,
                    edit_user = edit_user,
                    roles = {"admin", "editor", "author", "subscriber"},
                    error_message = "最後の管理者ユーザーのロールは変更できません",
                    page_title = "ユーザー編集",
                    active_menu = "users"
                })
            end
        end
    end
    
    -- ユーザー更新
    local ok, update_err = User.update_user(user_id, update_data)
    if not ok then
        local csrf_token = csrf.generate_token(session)
        local edit_user = User:find(user_id)
        return render_admin_template("users/edit", {
            user = user,
            csrf_token = csrf_token,
            edit_user = edit_user,
            roles = {"admin", "editor", "author", "subscriber"},
            error_message = update_err or "ユーザーの更新に失敗しました",
            page_title = "ユーザー編集",
            active_menu = "users"
        })
    end
    
    -- 成功時は編集ページに戻る（成功メッセージ付き）
    return { redirect_to = string.format("/admin/users/%d/edit?updated=1", user_id), status = 302 }
end

-- ユーザー削除処理
-- POST /admin/users/:id/delete
function UserController:delete(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- 管理者権限チェック
    if not check_user_management_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "ユーザー管理機能は管理者のみ利用できます")
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        ngx.log(ngx.ERR, "CSRF検証失敗: ", csrf_err or "unknown")
        return render_error("403 Forbidden", "CSRF検証に失敗しました")
    end
    
    -- ユーザーIDを取得
    local user_id = tonumber(self.params.id)
    if not user_id then
        return { redirect_to = "/admin/users", status = 302 }
    end
    
    -- ユーザー削除（最後の管理者削除防止はUser.delete_userで実装済み）
    local ok, delete_err = User.delete_user(user_id)
    if not ok then
        return { redirect_to = "/admin/users?error=" .. ngx.escape_uri(delete_err or "削除に失敗しました"), status = 302 }
    end
    
    -- 成功時はユーザー一覧にリダイレクト
    return { redirect_to = "/admin/users?deleted=1", status = 302 }
end

-- ========================================
-- プロフィール管理（全ユーザー）
-- ========================================

-- プロフィール表示
-- GET /admin/profile
function UserController:profile(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login?redirect=/admin/profile", status = 302 }
    end
    
    -- ユーザー統計情報を取得
    local stats = {
        post_count = 0,
        comment_count = 0
    }
    
    -- 投稿数を取得
    local post_count_query = string.format("SELECT COUNT(*) as count FROM posts WHERE author_id = %d", user.id)
    local post_result = db_config.query(post_count_query)
    if post_result and post_result[1] then
        stats.post_count = post_result[1].count or 0
    end
    
    -- コメント数を取得
    local comment_count_query = string.format("SELECT COUNT(*) as count FROM comments WHERE author_id = %d", user.id)
    local comment_result = db_config.query(comment_count_query)
    if comment_result and comment_result[1] then
        stats.comment_count = comment_result[1].count or 0
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- テンプレートをレンダリング
    return render_admin_template("profile/show", {
        user = user,
        csrf_token = csrf_token,
        stats = stats,
        page_title = "プロフィール",
        active_menu = "profile"
    })
end

-- プロフィール編集フォーム表示
-- GET /admin/profile/edit
function UserController:edit_profile(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login?redirect=/admin/profile/edit", status = 302 }
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- テンプレートをレンダリング
    return render_admin_template("profile/edit", {
        user = user,
        csrf_token = csrf_token,
        error_message = nil,
        page_title = "プロフィール編集",
        active_menu = "profile"
    })
end

-- プロフィール更新処理
-- POST /admin/profile/update
function UserController:update_profile(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        ngx.log(ngx.ERR, "CSRF検証失敗: ", csrf_err or "unknown")
        return render_error("403 Forbidden", "CSRF検証に失敗しました")
    end
    
    -- 更新データを準備（roleは含めない）
    local update_data = {
        username = self.params.username,
        email = self.params.email,
        display_name = self.params.display_name
    }
    
    -- バリデーション（簡易版）
    if not update_data.username or update_data.username == "" then
        local csrf_token = csrf.generate_token(session)
        return render_admin_template("profile/edit", {
            user = user,
            csrf_token = csrf_token,
            error_message = "ユーザー名は必須です",
            page_title = "プロフィール編集",
            active_menu = "profile"
        })
    end
    
    if not update_data.email or update_data.email == "" then
        local csrf_token = csrf.generate_token(session)
        return render_admin_template("profile/edit", {
            user = user,
            csrf_token = csrf_token,
            error_message = "メールアドレスは必須です",
            page_title = "プロフィール編集",
            active_menu = "profile"
        })
    end
    
    -- ユーザー更新（自分自身のみ）
    local ok, update_err = User.update_user(user.id, update_data)
    if not ok then
        local csrf_token = csrf.generate_token(session)
        return render_admin_template("profile/edit", {
            user = user,
            csrf_token = csrf_token,
            error_message = update_err or "プロフィールの更新に失敗しました",
            page_title = "プロフィール編集",
            active_menu = "profile"
        })
    end
    
    -- セッション情報を更新
    local updated_user, _ = User:find(user.id)
    if updated_user then
        updated_user.password_hash = nil
        session:set_user(updated_user)
    end
    
    -- 成功時はプロフィールページにリダイレクト
    return { redirect_to = "/admin/profile?updated=1", status = 302 }
end

return UserController
