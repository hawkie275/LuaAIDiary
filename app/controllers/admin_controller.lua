-- app/controllers/admin_controller.lua
-- 管理画面コントローラー - 管理画面の各種エンドポイント

local Session = require("utils.session")
local Post = require("models.post")
local Category = require("models.category")
local Tag = require("models.tag")
local Comment = require("models.comment")
local UserSettings = require("models.user_settings")
local csrf = require("middleware.csrf")
local db_config = require("config.database")
local etlua = require("etlua")

local AdminController = {}

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

-- 管理者権限チェック（admin または editor）
local function check_admin_permission(user)
    if not user then
        return false
    end
    
    -- admin または editor ロールを許可
    if user.role == "admin" or user.role == "editor" then
        return true
    end
    
    return false
end

-- 統計情報を取得
local function get_statistics()
    local stats = {
        posts_count = 0,
        categories_count = 0,
        tags_count = 0,
        comments_count = 0
    }
    
    -- 投稿数を取得
    local posts_count, err = Post:count()
    if posts_count then
        stats.posts_count = posts_count
    else
        ngx.log(ngx.WARN, "投稿数の取得に失敗: ", err or "unknown error")
    end
    
    -- カテゴリー数を取得
    local categories_count, err = Category.count_categories()
    if categories_count then
        stats.categories_count = categories_count
    else
        ngx.log(ngx.WARN, "カテゴリー数の取得に失敗: ", err or "unknown error")
    end
    
    -- タグ数を取得
    local tags_count, err = Tag.count_tags()
    if tags_count then
        stats.tags_count = tags_count
    else
        ngx.log(ngx.WARN, "タグ数の取得に失敗: ", err or "unknown error")
    end
    
    -- コメント数を取得
    local comments_count, err = Comment:count()
    if comments_count then
        stats.comments_count = comments_count
    else
        ngx.log(ngx.WARN, "コメント数の取得に失敗: ", err or "unknown error")
    end
    
    return stats
end

-- 最近の投稿を取得（カテゴリー名付き）
local function get_recent_posts(limit)
    limit = limit or 5
    
    -- まず最近の投稿を取得（重複なし）
    local query = string.format([[
        SELECT
            id,
            title,
            slug,
            excerpt,
            status,
            created_at,
            published_at
        FROM posts
        ORDER BY created_at DESC
        LIMIT %d
    ]], limit)
    
    local posts, err = db_config.query(query)
    if not posts then
        ngx.log(ngx.WARN, "最近の投稿の取得に失敗: ", err or "unknown error")
        return {}
    end
    
    -- 各投稿のすべてのカテゴリ名を取得してカンマ区切りで結合
    for _, post in ipairs(posts) do
        local cat_query = string.format([[
            SELECT c.name
            FROM categories c
            INNER JOIN post_categories pc ON c.id = pc.category_id
            WHERE pc.post_id = %s
            ORDER BY c.name
        ]], db_config.escape(tostring(post.id)))
        
        local categories, cat_err = db_config.query(cat_query)
        if categories and #categories > 0 then
            local cat_names = {}
            for _, cat in ipairs(categories) do
                table.insert(cat_names, cat.name)
            end
            post.category_name = table.concat(cat_names, ", ")
        else
            post.category_name = nil
        end
    end
    
    return posts
end

-- システム情報を取得
local function get_system_info()
    local system_info = {
        lua_version = _VERSION or "Unknown",
        server_time = os.date("%Y-%m-%d %H:%M:%S"),
        database_status = "disconnected"
    }
    
    -- データベース接続状態を確認
    local db, err = db_config.connect()
    if db then
        system_info.database_status = "connected"
        db_config.close(db)
    else
        ngx.log(ngx.WARN, "データベース接続確認失敗: ", err or "unknown error")
    end
    
    return system_info
end

-- ========================================
-- ヘルパー関数
-- ========================================

-- 配列パラメータのパース（チェックボックスやマルチセレクト用）
-- Lapisでは複数の値を持つフィールドの全ての値を取得するため、
-- self.req.params_post:get_all() を使用する必要がある
local function parse_array_param(param)
    if not param then
        return {}
    end
    
    if type(param) == "table" then
        -- 既に配列の場合
        local result = {}
        for _, v in ipairs(param) do
            table.insert(result, tonumber(v))
        end
        return result
    end
    
    -- 単一の値の場合（文字列または数値）
    if type(param) == "string" or type(param) == "number" then
        return {tonumber(param)}
    end
    
    return {}
end

-- リクエストから配列パラメータを取得
-- ngx.req.get_post_args() を使用して直接POSTパラメータを取得
local function get_array_param(req, field_name)
    -- リクエストボディを読み込む
    ngx.req.read_body()
    
    -- POSTパラメータを取得（100はmax_argsの制限）
    local post_args, err = ngx.req.get_post_args(100)
    if not post_args then
        ngx.log(ngx.ERR, "POSTパラメータの取得に失敗: ", err)
        return {}
    end
    
    -- フィールドの値を取得
    local values = post_args[field_name]
    if not values then
        return {}
    end
    
    -- 単一の値の場合は配列に変換
    if type(values) == "string" then
        return {tonumber(values)}
    end
    
    -- 既に配列の場合は数値に変換
    if type(values) == "table" then
        local result = {}
        for _, v in ipairs(values) do
            local num = tonumber(v)
            if num then
                table.insert(result, num)
            end
        end
        return result
    end
    
    return {}
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
        active_menu = data.active_menu or "dashboard",
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
    <p><a href="/admin/dashboard">ダッシュボードに戻る</a></p>
</body>
</html>
]], title, title, message)
end

-- ========================================
-- コントローラーメソッド
-- ========================================

-- ダッシュボードページ
-- GET /admin/dashboard
function AdminController.dashboard(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        -- ログインページにリダイレクト
        return {
            redirect_to = "/admin/login?redirect=/admin/dashboard",
            status = 302
        }
    end
    
    -- 管理者権限チェック
    if not check_admin_permission(user) then
        -- 権限不足
        ngx.status = 403
        self.res.headers["Content-Type"] = "text/html; charset=utf-8"
        return [[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>403 Forbidden - LuaAIDiary</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d9534f; }
        p { color: #666; }
        a { color: #337ab7; text-decoration: none; }
    </style>
</head>
<body>
    <h1>403 Forbidden</h1>
    <p>このページへのアクセス権限がありません。</p>
    <p>管理者権限が必要です。</p>
    <p><a href="/">トップページに戻る</a></p>
</body>
</html>
]]
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- 統計情報を取得
    local stats = get_statistics()
    
    -- 最近の投稿を取得
    local recent_posts = get_recent_posts(5)
    
    -- システム情報を取得
    local system_info = get_system_info()
    
    -- etluaテンプレートを読み込んでレンダリング
    local template_path = "/app/views/admin/dashboard.etlua"
    local layout_path = "/app/views/admin/layout.etlua"
    
    -- テンプレートファイルを読み込む
    local template_file = io.open(template_path, "r")
    if not template_file then
        ngx.log(ngx.ERR, "テンプレートファイルが見つかりません: ", template_path)
        ngx.status = 500
        return "テンプレートファイルが見つかりません"
    end
    local template_content = template_file:read("*all")
    template_file:close()
    
    -- レイアウトファイルを読み込む
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
    
    -- テンプレートデータ
    local data = {
        user = user,
        csrf_token = csrf_token,
        stats = stats,
        recent_posts = recent_posts,
        system_info = system_info,
        _VERSION = _VERSION
    }
    
    -- テンプレートをレンダリング
    local content = template(data)
    
    -- レイアウトデータ
    local layout_data = {
        user = user,
        csrf_token = csrf_token,
        content_for_layout = content,
        page_title = "ダッシュボード",
        active_menu = "dashboard",
        _VERSION = _VERSION
    }
    
    -- レイアウトをレンダリング
    local html = layout(layout_data)
    
    -- HTMLレスポンスを返す
    self.res.headers["Content-Type"] = "text/html; charset=utf-8"
    return html
end

-- ========================================
-- 投稿管理メソッド
-- ========================================

-- 投稿一覧ページ
-- GET /admin/posts
function AdminController.posts_index(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login?redirect=/admin/posts", status = 302 }
    end
    
    if not check_admin_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "このページへのアクセス権限がありません")
    end
    
    -- クエリパラメータ取得
    local args = self.req.params_get or {}
    local status = args.status or "all"
    local page = tonumber(args.page) or 1
    local per_page = 20
    local offset = (page - 1) * per_page
    
    -- 投稿を取得
    local options = {
        limit = per_page,
        offset = offset,
        order_by = "created_at DESC"
    }
    
    if status ~= "all" then
        options.where = string.format("status = '%s'", status)
    end
    
    local posts, err = Post:all(options)
    if not posts then
        posts = {}
    end
    
    -- 投稿数を取得（ページネーション用）
    local total_count = Post:count() or 0
    local total_pages = math.ceil(total_count / per_page)
    
    -- カテゴリーとタグを付与
    for _, post in ipairs(posts) do
        post.categories = Post.get_categories(post.id) or {}
        post.tags = Post.get_tags(post.id) or {}
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    -- テンプレートをレンダリング
    return render_admin_template("posts/index", {
        user = user,
        csrf_token = csrf_token,
        posts = posts,
        status_filter = status,
        page = page,
        total_pages = total_pages,
        total_count = total_count,
        page_title = "投稿管理",
        active_menu = "posts"
    })
end

-- 新規投稿作成ページ
-- GET /admin/posts/new
function AdminController.posts_new(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login?redirect=/admin/posts/new", status = 302 }
    end
    
    if not check_admin_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "このページへのアクセス権限がありません")
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""  -- フォールバック
    end
    
    -- カテゴリーとタグを取得
    local categories = Category:all() or {}
    local tags = Tag:all() or {}
    
    -- テンプレートをレンダリング
    return render_admin_template("posts/edit", {
        user = user,
        csrf_token = csrf_token,
        post = nil,  -- 新規作成なのでnil
        categories = categories,
        tags = tags,
        is_new = true,
        error_message = nil,  -- エラーメッセージなし
        page_title = "新規投稿",
        active_menu = "posts"
    })
end

-- 投稿編集ページ
-- GET /admin/posts/:id/edit
function AdminController.posts_edit(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    if not check_admin_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "このページへのアクセス権限がありません")
    end
    
    -- 投稿IDを取得
    local post_id = tonumber(self.params.id)
    if not post_id then
        return { redirect_to = "/admin/posts", status = 302 }
    end
    
    -- 投稿を取得
    local post, err = Post:find(post_id)
    if not post then
        return { redirect_to = "/admin/posts", status = 302 }
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""  -- フォールバック
    end
    
    -- カテゴリーとタグを取得
    post.categories = Post.get_categories(post_id) or {}
    post.tags = Post.get_tags(post_id) or {}
    local all_categories = Category:all() or {}
    local all_tags = Tag:all() or {}
    
    -- テンプレートをレンダリング
    return render_admin_template("posts/edit", {
        user = user,
        csrf_token = csrf_token,
        post = post,
        categories = all_categories,
        tags = all_tags,
        is_new = false,
        error_message = nil,  -- エラーメッセージなし
        page_title = "投稿を編集",
        active_menu = "posts"
    })
end

-- 投稿作成処理（フォームPOST）
-- POST /admin/posts
function AdminController.posts_create(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    -- フォームデータから投稿を作成
    -- Lapisでは name="field[]" のパラメータは self.params["field[]"] でアクセス
    local post_data = {
        title = self.params.title,
        content = self.params.content,
        excerpt = self.params.excerpt or "",
        author_id = user.id,
        status = self.params.status or "draft",
        categories = parse_array_param(self.params["category_ids[]"]),
        tags = parse_array_param(self.params["tag_ids[]"])
    }
    
    local post_id, err = Post.create_post(post_data)
    if not post_id then
        -- CSRFトークンを生成
        local csrf_token, csrf_err = csrf.generate_token(session)
        if not csrf_token then
            ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
            csrf_token = ""
        end
        
        -- エラー時はフォームに戻る
        return render_admin_template("posts/edit", {
            user = user,
            csrf_token = csrf_token,
            post = post_data,
            categories = Category:all() or {},
            tags = Tag:all() or {},
            is_new = true,
            error_message = err or "投稿の作成に失敗しました",
            page_title = "新規投稿",
            active_menu = "posts"
        })
    end
    
    -- 成功時は投稿一覧にリダイレクト
    return { redirect_to = "/admin/posts?created=1", status = 302 }
end

-- 投稿更新処理（フォームPOST）
-- POST /admin/posts/:id
function AdminController.posts_update(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    local post_id = tonumber(self.params.id)
    if not post_id then
        return { redirect_to = "/admin/posts", status = 302 }
    end
    
    -- フォームデータから更新データを作成
    local update_data = {
        title = self.params.title,
        content = self.params.content,
        excerpt = self.params.excerpt,
        status = self.params.status,
        categories = get_array_param(self.req, "category_ids[]"),
        tags = get_array_param(self.req, "tag_ids[]")
    }
    
    local ok, err = Post.update_post(post_id, update_data)
    if not ok then
        -- CSRFトークンを生成
        local csrf_token, csrf_err = csrf.generate_token(session)
        if not csrf_token then
            ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
            csrf_token = ""
        end
        
        -- エラー時はフォームに戻る
        local post = Post:find(post_id)
        return render_admin_template("posts/edit", {
            user = user,
            csrf_token = csrf_token,
            post = post,
            categories = Category:all() or {},
            tags = Tag:all() or {},
            is_new = false,
            error_message = err or "投稿の更新に失敗しました",
            page_title = "投稿を編集",
            active_menu = "posts"
        })
    end
    
    -- 成功時は編集ページに戻る
    return { redirect_to = string.format("/admin/posts/%d/edit?updated=1", post_id), status = 302 }
end

-- 投稿削除処理
-- POST /admin/posts/:id/delete
function AdminController.posts_delete(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    local post_id = tonumber(self.params.id)
    if not post_id then
        return { redirect_to = "/admin/posts", status = 302 }
    end
    
    local ok, err = Post:delete(post_id)
    if not ok then
        return { redirect_to = "/admin/posts?error=delete_failed", status = 302 }
    end
    
    return { redirect_to = "/admin/posts?deleted=1", status = 302 }
end

-- ========================================
-- カテゴリー管理メソッド
-- ========================================

-- カテゴリー管理ページ
-- GET /admin/categories
function AdminController.categories_index(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    if not check_admin_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "このページへのアクセス権限がありません")
    end
    
    -- カテゴリー一覧を取得
    local categories = Category:all() or {}
    
    -- 各カテゴリーの投稿数を取得
    for _, category in ipairs(categories) do
        category.post_count = Category.count_posts(category.id) or 0
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    return render_admin_template("categories/index", {
        user = user,
        csrf_token = csrf_token,
        categories = categories,
        error_message = nil,
        page_title = "カテゴリー管理",
        active_menu = "categories"
    })
end

-- カテゴリー作成処理
-- POST /admin/categories
function AdminController.categories_create(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    -- スラッグが空の場合は名前から自動生成
    local slug = self.params.slug
    if not slug or slug == "" then
        local slug_util = require("utils.slug")
        slug = slug_util.slugify(self.params.name)
    end
    
    -- カテゴリーを作成
    local category_data = {
        name = self.params.name,
        slug = slug,
        description = self.params.description or ""
    }
    
    local category_id, err = Category.create_category(category_data)
    if not category_id then
        -- CSRFトークンを生成
        local csrf_token, csrf_err = csrf.generate_token(session)
        if not csrf_token then
            ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
            csrf_token = ""
        end
        
        -- エラー時はカテゴリー管理ページに戻る
        local categories = Category:all() or {}
        for _, category in ipairs(categories) do
            category.post_count = Category.count_posts(category.id) or 0
        end
        
        return render_admin_template("categories/index", {
            user = user,
            csrf_token = csrf_token,
            categories = categories,
            error_message = err or "カテゴリーの作成に失敗しました",
            page_title = "カテゴリー管理",
            active_menu = "categories"
        })
    end
    
    -- 成功時はカテゴリー管理ページにリダイレクト
    return { redirect_to = "/admin/categories?created=1", status = 302 }
end

-- カテゴリー更新処理
-- POST /admin/categories/:id
function AdminController.categories_update(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    local category_id = tonumber(self.params.id)
    if not category_id then
        return { redirect_to = "/admin/categories", status = 302 }
    end
    
    -- 更新データを作成
    local update_data = {
        name = self.params.name,
        slug = self.params.slug,
        description = self.params.description
    }
    
    local ok, err = Category.update_category(category_id, update_data)
    if not ok then
        return { redirect_to = "/admin/categories?error=update_failed", status = 302 }
    end
    
    return { redirect_to = "/admin/categories?updated=1", status = 302 }
end

-- カテゴリー削除処理
-- POST /admin/categories/:id/delete
function AdminController.categories_delete(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    local category_id = tonumber(self.params.id)
    if not category_id then
        return { redirect_to = "/admin/categories", status = 302 }
    end
    
    local ok, err = Category:delete(category_id)
    if not ok then
        return { redirect_to = "/admin/categories?error=delete_failed", status = 302 }
    end
    
    return { redirect_to = "/admin/categories?deleted=1", status = 302 }
end

-- ========================================
-- タグ管理メソッド
-- ========================================

-- タグ管理ページ
-- GET /admin/tags
function AdminController.tags_index(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    if not check_admin_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "このページへのアクセス権限がありません")
    end
    
    -- タグ一覧を取得
    local tags = Tag:all() or {}
    
    -- 各タグの投稿数を取得
    for _, tag in ipairs(tags) do
        tag.post_count = Tag.count_posts(tag.id) or 0
    end
    
    -- CSRFトークンを生成
    local csrf_token, csrf_err = csrf.generate_token(session)
    if not csrf_token then
        ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
        csrf_token = ""
    end
    
    return render_admin_template("tags/index", {
        user = user,
        csrf_token = csrf_token,
        tags = tags,
        error_message = nil,
        page_title = "タグ管理",
        active_menu = "tags"
    })
end

-- タグ作成処理
-- POST /admin/tags
function AdminController.tags_create(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    -- スラッグが空の場合は名前から自動生成
    local slug = self.params.slug
    if not slug or slug == "" then
        local slug_util = require("utils.slug")
        slug = slug_util.slugify(self.params.name)
    end
    
    -- タグを作成
    local tag_data = {
        name = self.params.name,
        slug = slug,
        description = self.params.description or ""
    }
    
    local tag_id, err = Tag.create_tag(tag_data)
    if not tag_id then
        -- CSRFトークンを生成
        local csrf_token, csrf_err = csrf.generate_token(session)
        if not csrf_token then
            ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
            csrf_token = ""
        end
        
        -- エラー時はタグ管理ページに戻る
        local tags = Tag:all() or {}
        for _, tag in ipairs(tags) do
            tag.post_count = Tag.count_posts(tag.id) or 0
        end
        
        return render_admin_template("tags/index", {
            user = user,
            csrf_token = csrf_token,
            tags = tags,
            error_message = err or "タグの作成に失敗しました",
            page_title = "タグ管理",
            active_menu = "tags"
        })
    end
    
    -- 成功時はタグ管理ページにリダイレクト
    return { redirect_to = "/admin/tags?created=1", status = 302 }
end

-- タグ更新処理
-- POST /admin/tags/:id
function AdminController.tags_update(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    local tag_id = tonumber(self.params.id)
    if not tag_id then
        return { redirect_to = "/admin/tags", status = 302 }
    end
    
    -- 更新データを作成
    local update_data = {
        name = self.params.name,
        slug = self.params.slug,
        description = self.params.description
    }
    
    local ok, err = Tag.update_tag(tag_id, update_data)
    if not ok then
        return { redirect_to = "/admin/tags?error=update_failed", status = 302 }
    end
    
    return { redirect_to = "/admin/tags?updated=1", status = 302 }
end

-- タグ削除処理
-- POST /admin/tags/:id/delete
function AdminController.tags_delete(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    local tag_id = tonumber(self.params.id)
    if not tag_id then
        return { redirect_to = "/admin/tags", status = 302 }
    end
    
    local ok, err = Tag:delete(tag_id)
    if not ok then
        return { redirect_to = "/admin/tags?error=delete_failed", status = 302 }
    end
    
    return { redirect_to = "/admin/tags?deleted=1", status = 302 }
end

-- ========================================
-- サイト設定メソッド
-- ========================================

-- サイト設定ページ
-- GET /admin/settings
function AdminController.settings_index(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    if not check_admin_permission(user) then
        ngx.status = 403
        return render_error("403 Forbidden", "このページへのアクセス権限がありません")
    end
    
    -- ユーザー設定を取得
    local user_settings, err = UserSettings.get_settings(user.id)
    if not user_settings then
        -- 設定が存在しない場合はデフォルト値を使用
        user_settings = UserSettings.get_default_settings()
    end
    
    -- プリファレンスを取得してブログ設定を追加
    local preferences, pref_err = UserSettings.get_preferences(user.id)
    if preferences then
        user_settings.blog_title = preferences.blog_title or "LuaAIDiary"
        user_settings.blog_description = preferences.blog_description or ""
    else
        user_settings.blog_title = "LuaAIDiary"
        user_settings.blog_description = ""
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
        success_message = "設定を保存しました"
    end
    
    return render_admin_template("settings/index", {
        user = user,
        csrf_token = csrf_token,
        settings = user_settings,
        success_message = success_message,
        error_message = nil,
        page_title = "サイト設定",
        active_menu = "settings"
    })
end

-- サイト設定更新処理
-- POST /admin/settings
function AdminController.settings_update(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { redirect_to = "/admin/login", status = 302 }
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = csrf.verify_token(self, session)
    if not csrf_valid then
        return render_error("403 Forbidden", csrf_err or "CSRF検証に失敗しました")
    end
    
    -- 設定データを準備
    local settings_data = {}
    
    -- Gemini APIキーの処理（空でない場合のみ更新）
    if self.params.gemini_api_key and self.params.gemini_api_key ~= "" then
        settings_data.gemini_api_key = self.params.gemini_api_key
    end
    
    -- プリファレンス（ブログタイトル、説明）を準備
    local preferences = {
        blog_title = self.params.blog_title or "LuaAIDiary",
        blog_description = self.params.blog_description or ""
    }
    settings_data.preferences = preferences
    
    -- 設定を更新
    local ok, err = UserSettings.update_settings(user.id, settings_data)
    if not ok then
        -- CSRFトークンを生成
        local csrf_token, csrf_err = csrf.generate_token(session)
        if not csrf_token then
            ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", csrf_err or "unknown")
            csrf_token = ""
        end
        
        -- エラー時は設定ページに戻る
        local user_settings = UserSettings.get_settings(user.id) or UserSettings.get_default_settings()
        user_settings.blog_title = self.params.blog_title
        user_settings.blog_description = self.params.blog_description
        
        return render_admin_template("settings/index", {
            user = user,
            csrf_token = csrf_token,
            settings = user_settings,
            success_message = nil,
            error_message = err or "設定の更新に失敗しました",
            page_title = "サイト設定",
            active_menu = "settings"
        })
    end
    
    -- 成功時は設定ページにリダイレクト
    return { redirect_to = "/admin/settings?updated=1", status = 302 }
end

-- ========================================
-- Markdownプレビュー機能
-- ========================================

-- Markdownプレビュー
-- POST /api/preview/markdown
function AdminController.preview_markdown(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        ngx.status = 401
        return { json = { error = "Unauthorized" } }
    end
    
    -- Markdownテキストを取得
    local content = self.params.content or ""
    
    -- Markdownライブラリを読み込んでレンダリング
    local markdown = require("utils.markdown")
    local html = markdown.render_markdown(content)
    
    -- JSON形式でHTMLを返す
    return { json = { html = html } }
end

return AdminController
