-- テーマ設定の管理
-- style.css の解析とテーマメタデータの取得

local _M = {}

_M.theme_dir = "wp-content/themes/"

-- テーマ一覧を取得
function _M.get_all_themes()
    local themes = {}
    local handle = io.popen('ls -1 "' .. _M.theme_dir .. '" 2>/dev/null')
    
    if handle then
        for dirname in handle:lines() do
            local theme_info = _M.get_theme_info(dirname)
            if theme_info then
                table.insert(themes, theme_info)
            end
        end
        handle:close()
    end
    
    return themes
end

-- テーマ情報を取得（style.cssから）
function _M.get_theme_info(theme_name)
    local style_css = _M.theme_dir .. theme_name .. "/style.css"
    local file = io.open(style_css, "r")
    
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    -- style.cssのヘッダーコメントを解析
    local info = {
        name = theme_name,
        theme_name = _M.parse_header(content, "Theme Name") or theme_name,
        description = _M.parse_header(content, "Description") or "",
        version = _M.parse_header(content, "Version") or "1.0",
        author = _M.parse_header(content, "Author") or "Unknown",
        author_uri = _M.parse_header(content, "Author URI") or "",
        theme_uri = _M.parse_header(content, "Theme URI") or "",
        tags = _M.parse_header(content, "Tags") or "",
        text_domain = _M.parse_header(content, "Text Domain") or theme_name,
    }
    
    return info
end

-- style.cssのヘッダーから値を取得
function _M.parse_header(content, key)
    local pattern = key .. ":%s*([^\n\r]+)"
    local value = content:match(pattern)
    if value then
        -- 前後の空白を削除
        value = value:gsub("^%s*(.-)%s*$", "%1")
        -- */ を削除（コメント終了タグ）
        value = value:gsub("%*/$", "")
        value = value:gsub("^%s*(.-)%s*$", "%1")
    end
    return value
end

-- テーマオプションを保存
function _M.save_theme_option(theme_name, key, value)
    -- データベースに保存（簡易実装）
    local db = require "app.config.database"
    local conn = db:get_connection()
    
    if not conn then
        return false, "データベース接続エラー"
    end
    
    local stmt = conn:prepare([[
        INSERT INTO theme_options (theme_name, option_key, option_value, updated_at)
        VALUES (?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE option_value = ?, updated_at = NOW()
    ]])
    
    if not stmt then
        return false, "SQL準備エラー"
    end
    
    stmt:execute(theme_name, key, value, value)
    stmt:close()
    
    return true
end

-- テーマオプションを取得
function _M.get_theme_option(theme_name, key, default)
    local db = require "app.config.database"
    local conn = db:get_connection()
    
    if not conn then
        return default
    end
    
    local stmt = conn:prepare([[
        SELECT option_value FROM theme_options
        WHERE theme_name = ? AND option_key = ?
    ]])
    
    if not stmt then
        return default
    end
    
    stmt:execute(theme_name, key)
    local row = stmt:fetch({}, "a")
    stmt:close()
    
    if row then
        return row.option_value
    end
    
    return default
end

-- アクティブテーマを設定
function _M.set_active_theme(theme_name)
    return _M.save_theme_option("system", "active_theme", theme_name)
end

-- アクティブテーマを取得
function _M.get_active_theme()
    return _M.get_theme_option("system", "active_theme", "luaaidiary-default")
end

-- テーマがインストールされているか確認
function _M.theme_exists(theme_name)
    local theme_path = _M.theme_dir .. theme_name .. "/style.css"
    local file = io.open(theme_path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- サムネイルサイズを設定
function _M.add_image_size(name, width, height, crop)
    -- 画像サイズ設定を保存
    local sizes = _M.get_image_sizes()
    sizes[name] = {
        width = width,
        height = height,
        crop = crop or false
    }
    return _M.save_image_sizes(sizes)
end

-- 画像サイズ設定を取得
function _M.get_image_sizes()
    local theme_name = _M.get_active_theme()
    local sizes_json = _M.get_theme_option(theme_name, "image_sizes", "{}")
    
    local cjson = require "cjson"
    local ok, sizes = pcall(cjson.decode, sizes_json)
    
    if ok then
        return sizes
    else
        return {}
    end
end

-- 画像サイズ設定を保存
function _M.save_image_sizes(sizes)
    local theme_name = _M.get_active_theme()
    local cjson = require "cjson"
    local sizes_json = cjson.encode(sizes)
    
    return _M.save_theme_option(theme_name, "image_sizes", sizes_json)
end

-- テーマサポート機能を追加
function _M.add_theme_support(feature, options)
    local theme_name = _M.get_active_theme()
    local supports = _M.get_theme_supports(theme_name)
    
    supports[feature] = options or true
    
    local cjson = require "cjson"
    local supports_json = cjson.encode(supports)
    
    return _M.save_theme_option(theme_name, "theme_supports", supports_json)
end

-- テーマサポート機能を取得
function _M.get_theme_supports(theme_name)
    theme_name = theme_name or _M.get_active_theme()
    local supports_json = _M.get_theme_option(theme_name, "theme_supports", "{}")
    
    local cjson = require "cjson"
    local ok, supports = pcall(cjson.decode, supports_json)
    
    if ok then
        return supports
    else
        return {}
    end
end

-- テーマがサポート機能を持っているか確認
function _M.current_theme_supports(feature)
    local supports = _M.get_theme_supports()
    return supports[feature] ~= nil
end

-- テーマのfunctions.phpを実行
function _M.load_theme_functions(theme_name)
    local functions_path = _M.theme_dir .. theme_name .. "/functions.php"
    local file = io.open(functions_path, "r")
    
    if not file then
        -- functions.phpがない場合はスキップ
        return true
    end
    
    file:close()
    
    -- PHPエグゼキューターで実行
    local php_executor = require "theme_engine.php_executor"
    local output, err = php_executor.execute_php_file(functions_path, {})
    
    if err then
        ngx.log(ngx.ERR, "functions.php実行エラー: ", err)
        return false, err
    end
    
    return true
end

return _M
