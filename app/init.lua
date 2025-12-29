-- LuaAIDiary アプリケーション初期化
local lapis = require("lapis")
local app = lapis.Application()

-- モデルの初期化
local User = require("models.user")
local Post = require("models.post")
local Category = require("models.category")
local Tag = require("models.tag")
local Comment = require("models.comment")
local UserSettings = require("models.user_settings")

-- ユーティリティの初期化
local validator = require("utils.validator")
local crypto = require("utils.crypto")
local slug_util = require("utils.slug")

-- テーマコントローラーの初期化
local theme_controller = require("controllers.theme_controller")

-- 認証コントローラーの初期化
local auth_controller = require("controllers.auth_controller")

-- 投稿コントローラーの初期化
local post_controller = require("controllers.post_controller")

-- カテゴリーコントローラーの初期化
local category_controller = require("controllers.category_controller")

-- タグコントローラーの初期化
local tag_controller = require("controllers.tag_controller")

-- 管理画面コントローラーの初期化
local admin_controller = require("controllers.admin_controller")

-- Geminiコントローラーの初期化
local gemini_controller = require("controllers.gemini_controller")

-- CSRFミドルウェアの初期化
local csrf = require("middleware.csrf")

-- ========================================
-- WordPress風URLルーティング
-- ========================================

-- ホームページ
app:get("/", function(self)
    return theme_controller.index()
end)

-- 検索: /search（具体的なルートを先に定義）
app:get("/search", function(self)
    return theme_controller.search()
end)

-- カテゴリーアーカイブ: /category/:slug（具体的なルートを先に定義）
app:get("/category/:slug", function(self)
    return theme_controller.category(self.params.slug)
end)

-- タグアーカイブ: /tag/:slug（具体的なルートを先に定義）
app:get("/tag/:slug", function(self)
    return theme_controller.tag(self.params.slug)
end)

-- 著者アーカイブ: /author/:username（具体的なルートを先に定義）
app:get("/author/:username", function(self)
    return theme_controller.author(self.params.username)
end)

-- 単一投稿: /posts/:slug（具体的なルートを先に定義）
app:get("/posts/:slug", function(self)
    return theme_controller.single(self.params.slug)
end)

-- 日付アーカイブ: /:year/:month/:day
app:get("/:year/:month/:day", function(self)
    local year = self.params.year
    local month = self.params.month
    local day = self.params.day
    
    -- 数値チェック
    if tonumber(year) and tonumber(month) and tonumber(day) then
        return theme_controller.date_archive(year, month, day)
    else
        return theme_controller.error_404()
    end
end)

-- 日付アーカイブ: /:year/:month
app:get("/:year/:month", function(self)
    local year = self.params.year
    local month = self.params.month
    
    -- 数値チェック
    if tonumber(year) and tonumber(month) then
        return theme_controller.date_archive(year, month, nil)
    else
        return theme_controller.error_404()
    end
end)

-- 単一投稿またはアーカイブ: /:slug（キャッチオール）
app:get("/:slug", function(self)
    local slug = self.params.slug
    
    -- 数値の場合は年別アーカイブとして扱う
    if tonumber(slug) then
        return theme_controller.date_archive(slug, nil, nil)
    else
        -- それ以外は投稿スラッグとして扱う
        return theme_controller.single(slug)
    end
end)

-- ========================================
-- APIエンドポイント（既存）
-- ========================================

app:get("/health", function(self)
    self.res.headers["Content-Type"] = "application/json"
    return {
        json = {
            status = "ok",
            service = "LuaAIDiary",
            version = "0.1.0",
            timestamp = os.time()
        }
    }
end)

app:get("/api/db-test", function(self)
    local database = require("config.database")
    
    local db, err = database.connect()
    
    if not db then
        self.res.headers["Content-Type"] = "application/json"
        return {
            json = {
                status = "error",
                message = "データベース接続に失敗しました",
                error = err
            }
        }
    end
    
    local res, err = db:query("SELECT version() as version")
    
    if not res then
        database.close(db)
        self.res.headers["Content-Type"] = "application/json"
        return {
            json = {
                status = "error",
                message = "クエリ実行に失敗しました",
                error = err
            }
        }
    end
    
    database.close(db)
    
    self.res.headers["Content-Type"] = "application/json"
    return {
        json = {
            status = "success",
            message = "データベース接続成功",
            postgres_version = res[1].version,
            database = os.getenv("POSTGRES_DB"),
            host = os.getenv("POSTGRES_HOST")
        }
    }
end)

app:get("/api/redis-test", function(self)
    local redis = require("resty.redis")
    local red = redis:new()
    
    red:set_timeout(1000)
    
    local ok, err = red:connect(os.getenv("REDIS_HOST"), tonumber(os.getenv("REDIS_PORT")))
    
    if not ok then
        self.res.headers["Content-Type"] = "application/json"
        return {
            json = {
                status = "error",
                message = "Redis接続に失敗しました",
                error = err
            }
        }
    end
    
    local res, err = red:ping()
    
    if not res then
        self.res.headers["Content-Type"] = "application/json"
        return {
            json = {
                status = "error",
                message = "Ping失敗",
                error = err
            }
        }
    end
    
    self.res.headers["Content-Type"] = "application/json"
    return {
        json = {
            status = "success",
            message = "Redis接続成功",
            response = res
        }
    }
end)

-- モデルテストエンドポイント
app:get("/api/models-test", function(self)
    self.res.headers["Content-Type"] = "application/json"
    
    local results = {
        status = "ok",
        models_loaded = true,
        models = {
            user = User ~= nil,
            post = Post ~= nil,
            category = Category ~= nil,
            tag = Tag ~= nil,
            comment = Comment ~= nil,
            user_settings = UserSettings ~= nil
        },
        utils = {
            validator = validator ~= nil,
            crypto = crypto ~= nil,
            slug_util = slug_util ~= nil
        }
    }
    
    return {json = results}
end)

-- ========================================
-- 認証APIエンドポイント
-- ========================================

-- ユーザー登録
app:match("auth_register", "/api/auth/register", auth_controller.register)

-- ログイン
app:match("auth_login", "/api/auth/login", auth_controller.login)
app:post("/api/login", auth_controller.login)  -- エイリアス

-- ログアウト
app:match("auth_logout", "/api/auth/logout", auth_controller.logout)

-- 現在のユーザー情報取得
app:match("auth_me", "/api/auth/me", auth_controller.me)
app:get("/api/me", auth_controller.me)  -- エイリアス

-- パスワード変更
app:match("auth_change_password", "/api/auth/change-password", auth_controller.change_password)

-- 認証状態チェック
app:match("auth_check", "/api/auth/check", auth_controller.check)

-- ========================================
-- CSRFトークンAPIエンドポイント
-- ========================================

-- CSRFトークン取得
app:get("/api/csrf-token", function(self)
    return csrf.get_token_endpoint(self)
end)

-- ========================================
-- 投稿APIエンドポイント
-- ========================================

-- 投稿一覧取得
app:get("/api/posts", post_controller.index)

-- 投稿作成
app:post("/api/posts", post_controller.create)

-- 投稿詳細取得
app:get("/api/posts/:id", function(self)
    return post_controller.show(self.params.id)
end)

-- 投稿更新
app:put("/api/posts/:id", function(self)
    return post_controller.update(self.params.id)
end)

-- 投稿削除
app:delete("/api/posts/:id", function(self)
    return post_controller.delete(self.params.id)
end)

-- ========================================
-- カテゴリーAPIエンドポイント
-- ========================================

-- カテゴリー一覧取得
app:get("/api/categories", category_controller.index)

-- カテゴリー作成
app:post("/api/categories", category_controller.create)

-- カテゴリー詳細取得
app:get("/api/categories/:id", function(self)
    return category_controller.show(self.params.id)
end)

-- カテゴリー更新
app:put("/api/categories/:id", function(self)
    return category_controller.update(self.params.id)
end)

-- カテゴリー削除
app:delete("/api/categories/:id", function(self)
    return category_controller.delete(self.params.id)
end)

-- ========================================
-- タグAPIエンドポイント
-- ========================================

-- タグ一覧取得
app:get("/api/tags", tag_controller.index)

-- タグ作成
app:post("/api/tags", tag_controller.create)

-- タグ詳細取得
app:get("/api/tags/:id", function(self)
    return tag_controller.show(self.params.id)
end)

-- タグ更新
app:put("/api/tags/:id", function(self)
    return tag_controller.update(self.params.id)
end)

-- タグ削除
app:delete("/api/tags/:id", function(self)
    return tag_controller.delete(self.params.id)
end)

-- ========================================
-- 管理画面エンドポイント
-- ========================================

-- 管理画面ログインフォーム
app:get("/admin/login", function(self)
    return auth_controller.login_form(self)
end)

-- 管理画面ログイン処理
app:post("/admin/login", function(self)
    return auth_controller.login(self)
end)

-- パスワード変更フォーム
app:get("/admin/change-password", function(self)
    return auth_controller.change_password_form(self)
end)

-- パスワード変更処理
app:post("/admin/change-password", function(self)
    return auth_controller.change_password_submit(self)
end)

-- ログアウト処理（フォームからPOST）
app:post("/auth/logout", function(self)
    return auth_controller.logout(self)
end)

-- 管理画面トップ（ダッシュボードにリダイレクト）
app:match("/admin", function(self)
    return { redirect_to = "/admin/dashboard" }
end)

-- 管理画面ダッシュボード
app:get("/admin/dashboard", function(self)
    return admin_controller.dashboard(self)
end)

-- ========================================
-- 管理画面 - 投稿管理エンドポイント
-- ========================================

-- 投稿一覧
app:get("/admin/posts", function(self)
    return admin_controller.posts_index(self)
end)

-- 新規投稿フォーム
app:get("/admin/posts/new", function(self)
    return admin_controller.posts_new(self)
end)

-- 投稿作成
app:post("/admin/posts", function(self)
    return admin_controller.posts_create(self)
end)

-- 投稿編集フォーム
app:get("/admin/posts/:id/edit", function(self)
    return admin_controller.posts_edit(self)
end)

-- 投稿更新
app:post("/admin/posts/:id", function(self)
    return admin_controller.posts_update(self)
end)

-- 投稿削除
app:post("/admin/posts/:id/delete", function(self)
    return admin_controller.posts_delete(self)
end)

-- ========================================
-- 管理画面 - カテゴリー管理エンドポイント
-- ========================================

-- カテゴリー管理ページ
app:get("/admin/categories", function(self)
    return admin_controller.categories_index(self)
end)

-- カテゴリー作成
app:post("/admin/categories", function(self)
    return admin_controller.categories_create(self)
end)

-- カテゴリー更新
app:post("/admin/categories/:id", function(self)
    return admin_controller.categories_update(self)
end)

-- カテゴリー削除
app:post("/admin/categories/:id/delete", function(self)
    return admin_controller.categories_delete(self)
end)

-- ========================================
-- 管理画面 - タグ管理エンドポイント
-- ========================================

-- タグ管理ページ
app:get("/admin/tags", function(self)
    return admin_controller.tags_index(self)
end)

-- タグ作成
app:post("/admin/tags", function(self)
    return admin_controller.tags_create(self)
end)

-- タグ更新
app:post("/admin/tags/:id", function(self)
    return admin_controller.tags_update(self)
end)

-- タグ削除
app:post("/admin/tags/:id/delete", function(self)
    return admin_controller.tags_delete(self)
end)

-- ========================================
-- 管理画面 - サイト設定エンドポイント
-- ========================================

-- サイト設定ページ
app:get("/admin/settings", function(self)
    return admin_controller.settings_index(self)
end)

-- サイト設定更新
app:post("/admin/settings", function(self)
    return admin_controller.settings_update(self)
end)

-- ========================================
-- 管理画面 - Markdownプレビュー
-- ========================================

-- Markdownプレビュー
app:post("/api/preview/markdown", function(self)
    return admin_controller.preview_markdown(self)
end)

-- ========================================
-- Gemini API エンドポイント
-- ========================================

-- 記事生成
app:post("/api/gemini/generate-article", function(self)
    return gemini_controller.generate_article(self)
end)

-- AI校正
app:post("/api/gemini/proofread", function(self)
    return gemini_controller.proofread(self)
end)

-- API接続テスト
app:post("/api/gemini/test-connection", function(self)
    return gemini_controller.test_connection(self)
end)

-- ========================================
-- AI設定API エンドポイント
-- ========================================

-- AI設定取得
app:get("/api/settings/ai-preferences", function(self)
    return admin_controller.get_ai_preferences(self)
end)

-- AI設定更新
app:put("/api/settings/ai-preferences", function(self)
    return admin_controller.update_ai_preferences(self)
end)

-- Gemini APIキー保存
app:post("/api/settings/gemini-api-key", function(self)
    return admin_controller.save_gemini_api_key(self)
end)

-- Gemini APIキー削除
app:delete("/api/settings/gemini-api-key", function(self)
    return admin_controller.delete_gemini_api_key(self)
end)

-- 404エラーハンドリング
app:match("*", function(self)
    return theme_controller.error_404()
end)

return app
