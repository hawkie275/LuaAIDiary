-- WordPress関数のLua実装
-- 主要なWordPress関数をエミュレーション

local _M = {}

-- グローバルコンテキスト
_M.current_post = nil
_M.posts = {}
_M.post_index = 0
_M.query = {}

-- ========================================
-- コンテキスト設定関数
-- ========================================

function _M.set_current_post(post)
    _M.current_post = post
end

function _M.set_posts(posts)
    _M.posts = posts
    _M.post_index = 0
end

function _M.set_query(query)
    _M.query = query
end

-- ========================================
-- The Loop 関数
-- ========================================

function _M.have_posts()
    local has_posts = _M.post_index < #_M.posts
    -- 診断ログ
    ngx.log(ngx.ERR, "[DIAGNOSIS] wp_functions.have_posts: post_index=", _M.post_index, ", #posts=", #_M.posts, ", 結果=", has_posts)
    return has_posts
end

function _M.the_post()
    _M.post_index = _M.post_index + 1
    _M.current_post = _M.posts[_M.post_index]
    -- 診断ログ
    ngx.log(ngx.ERR, "[DIAGNOSIS] wp_functions.the_post: post_index=", _M.post_index)
    if _M.current_post then
        ngx.log(ngx.ERR, "[DIAGNOSIS] current_post.title=", _M.current_post.title or "nil")
    else
        ngx.log(ngx.ERR, "[DIAGNOSIS] current_post は nil")
    end
end

-- ========================================
-- 記事データ取得関数
-- ========================================

function _M.the_title(before, after)
    if _M.current_post then
        before = before or ""
        after = after or ""
        ngx.print(before .. _M.escape_html(_M.current_post.title) .. after)
    end
end

function _M.get_the_title(post_id)
    local post = post_id and _M.get_post(post_id) or _M.current_post
    return post and post.title or ""
end

function _M.the_content(more_link_text)
    if _M.current_post then
        local content = _M.current_post.content or ""
        
        -- Markdownをレンダリング
        local ok, markdown = pcall(require, "utils.markdown")
        if ok then
            content = markdown.render_markdown(content)
            ngx.log(ngx.INFO, "[the_content] Markdownレンダリング成功")
        else
            -- Markdownモジュールが読み込めない場合は、wpautopで処理
            ngx.log(ngx.WARN, "[the_content] Markdownモジュール読み込み失敗: ", tostring(markdown))
            content = _M.wpautop(content)
        end
        
        ngx.print(content)
    end
end

function _M.get_the_content()
    return _M.current_post and _M.current_post.content or ""
end

function _M.the_excerpt()
    if _M.current_post then
        local excerpt = _M.current_post.excerpt
        if not excerpt or excerpt == "" then
            excerpt = _M.auto_excerpt(_M.current_post.content, 150)
        end
        ngx.print(_M.escape_html(excerpt))
    end
end

function _M.get_the_excerpt()
    if _M.current_post then
        local excerpt = _M.current_post.excerpt
        if not excerpt or excerpt == "" then
            return _M.auto_excerpt(_M.current_post.content, 150)
        end
        return excerpt
    end
    return ""
end

-- ========================================
-- URL・リンク関数
-- ========================================

function _M.the_permalink()
    ngx.print(_M.get_permalink())
end

function _M.get_permalink(post_id)
    local post = post_id and _M.get_post(post_id) or _M.current_post
    if post then
        return string.format("%s/%s", _M.home_url(), post.slug)
    end
    return ""
end

function _M.home_url(path)
    local scheme = ngx.var.scheme or "http"
    local host = ngx.var.host or "localhost"
    local base_url = scheme .. "://" .. host
    return path and (base_url .. "/" .. path) or base_url
end

function _M.site_url(path)
    return _M.home_url(path)
end

-- ========================================
-- 著者関数
-- ========================================

function _M.the_author()
    if _M.current_post and _M.current_post.author then
        ngx.print(_M.escape_html(_M.current_post.author.display_name or _M.current_post.author.username))
    end
end

function _M.get_the_author()
    if _M.current_post and _M.current_post.author then
        return _M.current_post.author.display_name or _M.current_post.author.username or ""
    end
    return ""
end

function _M.the_author_posts_link()
    if _M.current_post and _M.current_post.author then
        local author = _M.current_post.author
        ngx.print(string.format(
            '<a href="%s/author/%s">%s</a>',
            _M.home_url(),
            author.username,
            _M.escape_html(author.display_name or author.username)
        ))
    end
end

-- ========================================
-- 日時関数
-- ========================================

function _M.the_time(format)
    ngx.print(_M.get_the_time(format))
end

function _M.get_the_time(format)
    if _M.current_post and _M.current_post.published_at then
        format = format or "%Y-%m-%d %H:%M:%S"
        return os.date(format, _M.current_post.published_at)
    end
    return ""
end

function _M.the_date(format)
    ngx.print(_M.get_the_date(format))
end

function _M.get_the_date(format)
    format = format or "%Y年%m月%d日"
    return _M.get_the_time(format)
end

-- ========================================
-- カテゴリー・タグ関数
-- ========================================

function _M.the_category(separator, parents)
    ngx.print(_M.get_the_category_list(separator, parents))
end

function _M.get_the_category_list(separator, parents)
    if not _M.current_post or not _M.current_post.categories then
        return ""
    end
    
    separator = separator or ", "
    local cats = {}
    
    for _, cat in ipairs(_M.current_post.categories) do
        table.insert(cats, string.format(
            '<a href="%s/category/%s">%s</a>',
            _M.home_url(),
            cat.slug,
            _M.escape_html(cat.name)
        ))
    end
    
    return table.concat(cats, separator)
end

function _M.get_categories(args)
    -- カテゴリモデルから取得
    local Category = require "models.category"
    return Category:all()
end

function _M.get_the_category(post_id)
    local post = post_id and _M.get_post(post_id) or _M.current_post
    return post and post.categories or {}
end

function _M.the_tags(before, separator, after)
    ngx.print(_M.get_the_tag_list(before, separator, after))
end

function _M.get_the_tag_list(before, separator, after)
    if not _M.current_post or not _M.current_post.tags then
        return ""
    end
    
    before = before or "タグ: "
    separator = separator or ", "
    after = after or ""
    
    local tags = {}
    for _, tag in ipairs(_M.current_post.tags) do
        table.insert(tags, string.format(
            '<a href="%s/tag/%s">%s</a>',
            _M.home_url(),
            tag.slug,
            _M.escape_html(tag.name)
        ))
    end
    
    if #tags == 0 then
        return ""
    end
    
    return before .. table.concat(tags, separator) .. after
end

function _M.get_tags(args)
    -- タグモデルから取得
    local Tag = require "models.tag"
    return Tag:all()
end

function _M.get_the_tags(post_id)
    local post = post_id and _M.get_post(post_id) or _M.current_post
    return post and post.tags or {}
end

-- クエリされたオブジェクトを取得（アーカイブページ用）
-- @return クエリされたオブジェクト（カテゴリー、タグ、著者など）
function _M.get_queried_object()
    local wp_query = require "theme_engine.wp_query"
    local query = wp_query.get_global_query()
    
    if query and query.queried_object then
        return query.queried_object
    end
    
    return nil
end

-- カテゴリータイトルを表示
-- @param prefix タイトルの前に付ける文字列（デフォルト: 空文字列）
-- @param display true=出力、false=文字列を返す（デフォルト: true）
-- @return displayがfalseの場合は文字列、trueの場合はnil
function _M.single_cat_title(prefix, display)
    prefix = prefix or ''
    display = display == nil and true or display
    
    local current_category = _M.get_queried_object()
    if not current_category or not current_category.name then
        if not display then
            return ''
        end
        return nil
    end
    
    local title = prefix .. current_category.name
    
    if display then
        ngx.print(_M.escape_html(title))
        return nil
    else
        return title
    end
end

-- タグタイトルを表示
-- @param prefix タイトルの前に付ける文字列（デフォルト: 空文字列）
-- @param display true=出力、false=文字列を返す（デフォルト: true）
-- @return displayがfalseの場合は文字列、trueの場合はnil
function _M.single_tag_title(prefix, display)
    prefix = prefix or ''
    display = display == nil and true or display
    
    local current_tag = _M.get_queried_object()
    if not current_tag or not current_tag.name then
        if not display then
            return ''
        end
        return nil
    end
    
    local title = prefix .. current_tag.name
    
    if display then
        ngx.print(_M.escape_html(title))
        return nil
    else
        return title
    end
end

-- ========================================
-- アイキャッチ画像
-- ========================================

function _M.get_the_post_thumbnail(post_id, size)
    local post = post_id and _M.get_post(post_id) or _M.current_post
    if post and post.thumbnail then
        size = size or "full"
        return string.format('<img src="%s" alt="%s">', 
            _M.escape_html(post.thumbnail),
            _M.escape_html(post.title))
    end
    return ""
end

function _M.the_post_thumbnail(size)
    ngx.print(_M.get_the_post_thumbnail(nil, size))
end

-- ========================================
-- 条件分岐タグ
-- ========================================

function _M.is_home()
    return ngx.var.uri == "/" or ngx.var.uri == "/home"
end

function _M.is_front_page()
    return ngx.var.uri == "/"
end

function _M.is_single()
    return _M.current_post ~= nil and not _M.is_page()
end

function _M.is_page()
    return _M.current_post ~= nil and _M.current_post.post_type == "page"
end

function _M.is_category(category)
    if not ngx.var.uri:match("^/category/") then
        return false
    end
    if category then
        return ngx.var.uri:match("/category/" .. category) ~= nil
    end
    return true
end

function _M.is_tag(tag)
    if not ngx.var.uri:match("^/tag/") then
        return false
    end
    if tag then
        return ngx.var.uri:match("/tag/" .. tag) ~= nil
    end
    return true
end

function _M.is_archive()
    return _M.is_category() or _M.is_tag() or _M.is_date()
end

function _M.is_date()
    return ngx.var.uri:match("^/%d%d%d%d/") ~= nil
end

function _M.is_search()
    return ngx.var.uri == "/search" or (ngx.var.args and ngx.var.args:match("s="))
end

function _M.is_404()
    return ngx.status == 404
end

-- ========================================
-- サイト情報関数
-- ========================================

function _M.bloginfo(show)
    local info = _M.get_bloginfo(show)
    ngx.print(info)
end

function _M.get_bloginfo(show)
    show = show or "name"
    
    -- デフォルト値
    local defaults = {
        name = "LuaAIDiary",
        description = "Lua製高性能ブログシステム",
        url = _M.home_url(),
        charset = "UTF-8",
        version = "1.0.0",
        language = "ja",
    }
    
    -- user_settingsから設定を取得（管理者ユーザーID=1）
    local ok, UserSettings = pcall(require, "models.user_settings")
    ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: pcall result=", ok)
    
    if ok then
        -- 管理者の設定を取得
        local settings, err = UserSettings.get_settings(1)
        ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: settings=", settings and "exists" or "nil", ", err=", err or "nil")
        
        if settings then
            -- preferencesを取得
            local preferences, pref_err = UserSettings.get_preferences(1)
            ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: preferences=", preferences and "exists" or "nil")
            
            if preferences then
                ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: blog_title=", preferences.blog_title or "nil")
                ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: blog_description=", preferences.blog_description or "nil")
                
                -- preferencesからサイト設定を取得（キー名はblog_title, blog_description）
                if preferences.blog_title and preferences.blog_title ~= "" then
                    defaults.name = preferences.blog_title
                    ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: Updated name to: ", defaults.name)
                end
                if preferences.blog_description and preferences.blog_description ~= "" then
                    defaults.description = preferences.blog_description
                    ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: Updated description to: ", defaults.description)
                end
            end
        end
    end
    
    ngx.log(ngx.ERR, "[DEBUG] get_bloginfo: Returning ", show, "=", defaults[show] or "")
    return defaults[show] or ""
end

function _M.wp_title(separator, display, seplocation)
    separator = separator or "|"
    local title = ""
    
    if _M.current_post then
        title = _M.current_post.title
    elseif _M.is_category() then
        title = "カテゴリー"
    elseif _M.is_tag() then
        title = "タグ"
    else
        title = _M.get_bloginfo("name")
    end
    
    if display then
        ngx.print(title)
    end
    
    return title
end

-- ========================================
-- テンプレートパーツ読み込み
-- ========================================

function _M.get_header(name)
    local template_loader = require "theme_engine.template_loader"
    local output = template_loader.get_header(name)
    ngx.print(output)
end

function _M.get_footer(name)
    local template_loader = require "theme_engine.template_loader"
    local output = template_loader.get_footer(name)
    ngx.print(output)
end

function _M.get_sidebar(name)
    local template_loader = require "theme_engine.template_loader"
    local output = template_loader.get_sidebar(name)
    ngx.print(output)
end

function _M.get_template_part(slug, name)
    local template_loader = require "theme_engine.template_loader"
    local output = template_loader.get_template_part(slug, name)
    ngx.print(output)
end

-- ========================================
-- ヘッダー・フッター
-- ========================================

function _M.wp_head()
    -- メタタグ、CSS、JSの出力
    ngx.print([[
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    ]])
    
    -- テーマのstyle.css読み込み
    local template_loader = require "theme_engine.template_loader"
    ngx.print(string.format(
        '<link rel="stylesheet" href="%s/style.css">',
        template_loader.get_theme_uri()
    ))
end

function _M.wp_footer()
    -- フッタースクリプトの出力
end

-- ========================================
-- HTML属性関数
-- ========================================

function _M.language_attributes()
    ngx.print('lang="ja"')
end

-- ========================================
-- PHP互換関数
-- ========================================

function _M.date(format, timestamp)
    format = format or "Y-m-d H:i:s"
    timestamp = timestamp or os.time()
    
    -- PHPのdate形式をLuaのos.date形式に変換
    local lua_format = format
    lua_format = lua_format:gsub("Y", "%%Y")
    lua_format = lua_format:gsub("m", "%%m")
    lua_format = lua_format:gsub("d", "%%d")
    lua_format = lua_format:gsub("H", "%%H")
    lua_format = lua_format:gsub("i", "%%M")
    lua_format = lua_format:gsub("s", "%%S")
    
    return os.date(lua_format, timestamp)
end

-- ========================================
-- クラス出力
-- ========================================

function _M.body_class(class)
    local classes = {}
    
    if _M.is_home() then
        table.insert(classes, "home")
    end
    if _M.is_single() then
        table.insert(classes, "single")
    end
    if _M.is_page() then
        table.insert(classes, "page")
    end
    if _M.is_archive() then
        table.insert(classes, "archive")
    end
    
    if class then
        table.insert(classes, class)
    end
    
    ngx.print('class="' .. table.concat(classes, " ") .. '"')
end

function _M.post_class(class)
    local classes = {"post"}
    
    if _M.current_post then
        table.insert(classes, "post-" .. _M.current_post.id)
        if _M.current_post.post_type then
            table.insert(classes, "type-" .. _M.current_post.post_type)
        end
        if _M.current_post.status then
            table.insert(classes, "status-" .. _M.current_post.status)
        end
    end
    
    if class then
        table.insert(classes, class)
    end
    
    ngx.print('class="' .. table.concat(classes, " ") .. '"')
end

-- ========================================
-- メニュー
-- ========================================

function _M.wp_nav_menu(args)
    args = args or {}
    local menu_class = args.menu_class or "menu"
    local container = args.container or "div"
    local container_class = args.container_class or "menu-container"
    
    ngx.print(string.format('<%s class="%s">', container, container_class))
    ngx.print(string.format('<ul class="%s">', menu_class))
    ngx.print('<li><a href="' .. _M.home_url() .. '">ホーム</a></li>')
    ngx.print('</ul>')
    ngx.print('</' .. container .. '>')
end

-- ========================================
-- ヘルパー関数
-- ========================================

function _M.escape_html(str)
    if not str then return "" end
    str = tostring(str)
    str = string.gsub(str, "&", "&amp;")
    str = string.gsub(str, "<", "&lt;")
    str = string.gsub(str, ">", "&gt;")
    str = string.gsub(str, '"', "&quot;")
    str = string.gsub(str, "'", "&#39;")
    return str
end

-- 改行を段落とbrタグに変換（WordPress wpautop相当の簡易版）
function _M.wpautop(text)
    if not text or text == "" then return "" end
    
    -- 既存のHTMLタグがある場合はそのまま返す
    if text:match("<p>") or text:match("<div>") or text:match("<br") then
        return text
    end
    
    -- エスケープされた改行を実際の改行に戻す（ngx.quote_sql_strの影響を修正）
    text = text:gsub("\\r\\n", "\n")  -- エスケープされたWindows改行
    text = text:gsub("\\n", "\n")     -- エスケープされたUnix改行
    text = text:gsub("\\r", "\n")     -- エスケープされたMac改行
    
    -- テキストを正規化
    text = text:gsub("\r\n", "\n")  -- Windows改行をUnix改行に統一
    text = text:gsub("\r", "\n")    -- Mac改行をUnix改行に統一
    text = text:gsub("[ \t]+\n", "\n")  -- 行末の空白を削除
    text = text:gsub("\n\n+", "\n\n")  -- 3つ以上の連続改行を2つに
    
    -- 段落に分割
    local paragraphs = {}
    local current_para = ""
    
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^%s*$") then
            -- 空行の場合、現在の段落を保存
            if current_para ~= "" then
                -- 段落内の改行を<br>に変換
                current_para = current_para:gsub("\n", "<br>\n")
                table.insert(paragraphs, "<p>" .. current_para .. "</p>")
                current_para = ""
            end
        else
            -- 空行でない場合、現在の段落に追加
            if current_para ~= "" then
                current_para = current_para .. "\n" .. line
            else
                current_para = line
            end
        end
    end
    
    -- 最後の段落を処理
    if current_para ~= "" then
        current_para = current_para:gsub("\n", "<br>\n")
        table.insert(paragraphs, "<p>" .. current_para .. "</p>")
    end
    
    -- 段落がない場合
    if #paragraphs == 0 then
        return "<p>" .. text .. "</p>"
    end
    
    return table.concat(paragraphs, "\n\n")
end

function _M.auto_excerpt(content, length)
    if not content then return "" end
    -- HTMLタグを除去
    content = content:gsub("<[^>]+>", "")
    -- 指定文字数で切り詰め
    if #content > length then
        return content:sub(1, length) .. "..."
    end
    return content
end

function _M.get_post(post_id)
    -- モデルから投稿を取得
    local Post = require "models.post"
    return Post:find(post_id)
end

return _M
