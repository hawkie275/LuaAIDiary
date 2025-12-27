-- app/controllers/admin_controller.lua
-- 管理画面コントローラー - 管理画面の各種エンドポイント

local Session = require("utils.session")
local Post = require("models.post")
local Category = require("models.category")
local Tag = require("models.tag")
local Comment = require("models.comment")
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
    
    -- カテゴリー名を含む最近の投稿を取得
    local query = string.format([[
        SELECT 
            p.id,
            p.title,
            p.status,
            p.created_at,
            p.published_at,
            c.name as category_name
        FROM posts p
        LEFT JOIN post_categories pc ON p.id = pc.post_id
        LEFT JOIN categories c ON pc.category_id = c.id
        ORDER BY p.created_at DESC
        LIMIT %d
    ]], limit)
    
    local posts, err = db_config.query(query)
    if not posts then
        ngx.log(ngx.WARN, "最近の投稿の取得に失敗: ", err or "unknown error")
        return {}
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
    local csrf_token = csrf.generate_token(session)
    
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

return AdminController
