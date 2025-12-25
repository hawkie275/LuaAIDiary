-- テーマレンダリングを担当するコントローラー
-- リクエストに応じた適切なテンプレートの選択とデータの準備

local template_loader = require "theme_engine.template_loader"
local wp_query = require "theme_engine.wp_query"
local Post = require "models.post"
local Category = require "models.category"
local Tag = require "models.tag"

local _M = {}

-- ホームページを表示
function _M.index()
    -- 公開済み投稿を取得
    local query = wp_query:new({
        post_type = "post",
        post_status = "published",
        posts_per_page = 10,
        paged = tonumber(ngx.var.arg_paged) or 1
    })
    
    -- グローバルクエリとして設定
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        posts = query.posts,
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("home", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

-- 単一投稿を表示
function _M.single(slug)
    -- スラッグから投稿を取得
    local post, err = Post.find_by_slug(slug)
    
    if not post then
        return _M.error_404()
    end
    
    -- find_by_slug で既にカテゴリとタグは取得済み
    -- 著者情報を取得
    if post.author_id then
        local User = require "models.user"
        post.author = User:find(post.author_id)
    end
    
    -- クエリを作成
    local query = wp_query:new({
        name = slug,
        post_type = "post"
    })
    
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        post = post,
        posts = {post},
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("single", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

-- カテゴリーアーカイブを表示
function _M.category(slug)
    -- カテゴリーを取得
    local category = Category:find_by_slug(slug)
    
    if not category then
        return _M.error_404()
    end
    
    -- カテゴリーの投稿を取得
    local posts = category:get_posts()
    
    -- クエリを作成
    local query = wp_query:new({
        category_name = slug,
        posts_per_page = 10,
        paged = tonumber(ngx.var.arg_paged) or 1
    })
    
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        category = category,
        posts = posts,
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("category", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

-- タグアーカイブを表示
function _M.tag(slug)
    -- タグを取得
    local tag = Tag:find_by_slug(slug)
    
    if not tag then
        return _M.error_404()
    end
    
    -- タグの投稿を取得
    local posts = tag:get_posts()
    
    -- クエリを作成
    local query = wp_query:new({
        tag = slug,
        posts_per_page = 10,
        paged = tonumber(ngx.var.arg_paged) or 1
    })
    
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        tag = tag,
        posts = posts,
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("tag", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

-- 検索結果を表示
function _M.search()
    local search_query = ngx.var.arg_s or ""
    
    if search_query == "" then
        return _M.error_404()
    end
    
    -- 検索クエリを作成
    local query = wp_query:new({
        s = search_query,
        posts_per_page = 10,
        paged = tonumber(ngx.var.arg_paged) or 1
    })
    
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        search_query = search_query,
        posts = query.posts,
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("search", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

-- 404エラーページ
function _M.error_404()
    ngx.status = 404
    
    -- クエリを作成
    local query = wp_query:new({})
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        posts = {},
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("404", context)
    
    ngx.header.content_type = "text/html; charset=utf-8"
    if err then
        ngx.log(ngx.ERR, "404テンプレート読み込みエラー: ", err)
        ngx.say([[
            <!DOCTYPE html>
            <html>
            <head>
                <title>404 Not Found</title>
            </head>
            <body>
                <h1>404 Not Found</h1>
                <p>お探しのページは見つかりませんでした。</p>
            </body>
            </html>
        ]])
        return
    end
    
    ngx.say(output)
end

-- 日付アーカイブを表示
function _M.date_archive(year, month, day)
    -- 日付条件を作成
    local date_query = {
        year = tonumber(year),
        month = month and tonumber(month) or nil,
        day = day and tonumber(day) or nil
    }
    
    -- クエリを作成
    local query = wp_query:new({
        date_query = date_query,
        posts_per_page = 10,
        paged = tonumber(ngx.var.arg_paged) or 1
    })
    
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        date_query = date_query,
        posts = query.posts,
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("archive", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

-- 著者アーカイブを表示
function _M.author(username)
    local User = require "models.user"
    
    -- ユーザーを取得
    local author = User:find_by_username(username)
    
    if not author then
        return _M.error_404()
    end
    
    -- 著者の投稿を取得
    local query = wp_query:new({
        author = author.id,
        posts_per_page = 10,
        paged = tonumber(ngx.var.arg_paged) or 1
    })
    
    wp_query.set_global_query(query)
    
    -- コンテキストを準備
    local context = {
        author = author,
        posts = query.posts,
        query = query
    }
    
    -- テンプレートをロードして実行
    local output, err = template_loader.load_template("archive", context)
    
    if err then
        ngx.log(ngx.ERR, "テンプレート読み込みエラー: ", err)
        return _M.error_404()
    end
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(output)
end

return _M
