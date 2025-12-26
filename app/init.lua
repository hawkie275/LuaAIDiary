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

-- ========================================
-- WordPress風URLルーティング
-- ========================================

-- ホームページ
app:get("/", function(self)
    return theme_controller.index()
end)

-- 単一投稿: /:slug
app:get("/:slug", function(self)
    return theme_controller.single(self.params.slug)
end)

-- カテゴリーアーカイブ: /category/:slug
app:get("/category/:slug", function(self)
    return theme_controller.category(self.params.slug)
end)

-- タグアーカイブ: /tag/:slug
app:get("/tag/:slug", function(self)
    return theme_controller.tag(self.params.slug)
end)

-- 著者アーカイブ: /author/:username
app:get("/author/:username", function(self)
    return theme_controller.author(self.params.username)
end)

-- 検索: /search
app:get("/search", function(self)
    return theme_controller.search()
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

-- 日付アーカイブ: /:year
app:get("/:year", function(self)
    local year = self.params.year
    
    -- 数値チェック
    if tonumber(year) then
        return theme_controller.date_archive(year, nil, nil)
    else
        return theme_controller.error_404()
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

-- ログアウト
app:match("auth_logout", "/api/auth/logout", auth_controller.logout)

-- 現在のユーザー情報取得
app:match("auth_me", "/api/auth/me", auth_controller.me)

-- パスワード変更
app:match("auth_change_password", "/api/auth/change-password", auth_controller.change_password)

-- 認証状態チェック
app:match("auth_check", "/api/auth/check", auth_controller.check)

-- 404エラーハンドリング
app:match("*", function(self)
    return theme_controller.error_404()
end)

return app
