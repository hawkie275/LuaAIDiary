-- WordPressテンプレート階層の実装
-- テンプレートファイル探索とロード
local php_executor = require "theme_engine.php_executor"


local _M = {}

-- アクティブテーマのディレクトリ
_M.active_theme = "luwordpress-default"  -- 設定から取得
_M.theme_dir = "/app/wp-content/themes/"

-- テンプレート階層定義（WordPressと同じ優先順位）
_M.template_hierarchy = {
    single = {
        'single-{post_type}-{slug}.php',
        'single-{post_type}.php',
        'single.php',
        'singular.php',
        'index.php'
    },
    page = {
        'page-{slug}.php',
        'page-{id}.php',
        'page.php',
        'singular.php',
        'index.php'
    },
    category = {
        'category-{slug}.php',
        'category-{id}.php',
        'category.php',
        'archive.php',
        'index.php'
    },
    tag = {
        'tag-{slug}.php',
        'tag-{id}.php',
        'tag.php',
        'archive.php',
        'index.php'
    },
    home = {
        'front-page.php',
        'home.php',
        'index.php'
    },
    archive = {
        'archive.php',
        'index.php'
    },
    search = {
        'search.php',
        'index.php'
    },
    ['404'] = {
        '404.php',
        'index.php'
    }
}

-- Luaテンプレートを実行
function _M.execute_lua_template(file_path, context)
    local chunk, err = loadfile(file_path)
    if not chunk then
        ngx.log(ngx.ERR, "Luaテンプレート読み込みエラー: ", err)
        return nil, err
    end
    
    local ok, template = pcall(chunk)
    if not ok then
        ngx.log(ngx.ERR, "Luaテンプレート実行エラー: ", template)
        return nil, template
    end
    
    if template and template.render then
        local output_ok, output = pcall(template.render, context)
        if output_ok then
            return output, nil
        else
            ngx.log(ngx.ERR, "テンプレートrender()エラー: ", output)
            return nil, output
        end
    end
    
    return nil, "テンプレートにrender()関数がありません"
end

-- テンプレートを読み込んで実行
function _M.load_template(template_type, context)
    local templates = _M.template_hierarchy[template_type]
    if not templates then
        ngx.log(ngx.ERR, "不明なテンプレートタイプ: " .. tostring(template_type))
        return nil, "不明なテンプレートタイプ: " .. tostring(template_type)
    end
    
    -- まず、Luaテンプレートを探す（index-simple.luaなど）
    for _, template_pattern in ipairs(templates) do
        local lua_template = template_pattern:gsub("%.php$", "-simple.lua")
        local file_path = _M.theme_dir .. _M.active_theme .. "/" .. lua_template
        
        if _M.file_exists(file_path) then
            ngx.log(ngx.INFO, "Luaテンプレート読み込み: ", file_path)
            return _M.execute_lua_template(file_path, context)
        end
    end
    
    -- Luaテンプレートがなければ、PHPテンプレートを探す
    for _, template_pattern in ipairs(templates) do
        local template_file = _M.resolve_template_path(template_pattern, context)
        local file_path = _M.theme_dir .. _M.active_theme .. "/" .. template_file
        
        if _M.file_exists(file_path) then
            ngx.log(ngx.INFO, "PHPテンプレート読み込み: ", file_path)
            return php_executor.execute_php_file(file_path, context)
        end
    end
    
    return nil, "テンプレートが見つかりません"
end

-- テンプレートパスの解決（プレースホルダーを置換）
function _M.resolve_template_path(pattern, context)
    local path = pattern
    
    -- プレースホルダーを置換
    if context.post then
        path = path:gsub("{post_type}", context.post.post_type or "post")
        path = path:gsub("{slug}", context.post.slug or "")
        path = path:gsub("{id}", tostring(context.post.id or ""))
    end
    
    if context.category then
        path = path:gsub("{slug}", context.category.slug or "")
        path = path:gsub("{id}", tostring(context.category.id or ""))
    end
    
    if context.tag then
        path = path:gsub("{slug}", context.tag.slug or "")
        path = path:gsub("{id}", tostring(context.tag.id or ""))
    end
    
    return path
end

-- ファイルの存在確認
function _M.file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- get_header() の実装
function _M.get_header(name)
    local file_name = name and ("header-" .. name .. ".php") or "header.php"
    local file_path = _M.theme_dir .. _M.active_theme .. "/" .. file_name
    
    if _M.file_exists(file_path) then
        local output, err = php_executor.execute_php_file(file_path, {})
        if output then
            return output
        else
            ngx.log(ngx.ERR, "ヘッダー読み込みエラー: ", err)
        end
    end
    return ""
end

-- get_footer() の実装
function _M.get_footer(name)
    local file_name = name and ("footer-" .. name .. ".php") or "footer.php"
    local file_path = _M.theme_dir .. _M.active_theme .. "/" .. file_name
    
    if _M.file_exists(file_path) then
        local output, err = php_executor.execute_php_file(file_path, {})
        if output then
            return output
        else
            ngx.log(ngx.ERR, "フッター読み込みエラー: ", err)
        end
    end
    return ""
end

-- get_sidebar() の実装
function _M.get_sidebar(name)
    local file_name = name and ("sidebar-" .. name .. ".php") or "sidebar.php"
    local file_path = _M.theme_dir .. _M.active_theme .. "/" .. file_name
    
    if _M.file_exists(file_path) then
        local output, err = php_executor.execute_php_file(file_path, {})
        if output then
            return output
        else
            ngx.log(ngx.ERR, "サイドバー読み込みエラー: ", err)
        end
    end
    return ""
end

-- get_template_part() の実装
function _M.get_template_part(slug, name)
    local file_name
    if name then
        file_name = slug .. "-" .. name .. ".php"
    else
        file_name = slug .. ".php"
    end
    
    local file_path = _M.theme_dir .. _M.active_theme .. "/" .. file_name
    
    if _M.file_exists(file_path) then
        local output, err = php_executor.execute_php_file(file_path, {})
        if output then
            return output
        else
            ngx.log(ngx.ERR, "テンプレートパーツ読み込みエラー: ", err)
        end
    end
    return ""
end

-- アクティブテーマを設定
function _M.set_active_theme(theme_name)
    _M.active_theme = theme_name
end

-- アクティブテーマを取得
function _M.get_active_theme()
    return _M.active_theme
end

-- テーマディレクトリのパスを取得
function _M.get_theme_directory()
    return _M.theme_dir .. _M.active_theme
end

-- テーマURLを取得
function _M.get_theme_uri()
    local scheme = ngx.var.scheme or "http"
    local host = ngx.var.host or "localhost"
    return scheme .. "://" .. host .. "/" .. _M.theme_dir .. _M.active_theme
end

return _M
