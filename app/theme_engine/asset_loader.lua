-- アセット管理（CSS/JSファイルの読み込み）
-- wp_enqueue_style(), wp_enqueue_script() のエミュレーション

local _M = {}

-- 登録されたスタイル
_M.styles = {}
_M.enqueued_styles = {}

-- 登録されたスクリプト
_M.scripts = {}
_M.enqueued_scripts = {}

-- スタイルを登録
function _M.wp_register_style(handle, src, deps, ver, media)
    _M.styles[handle] = {
        src = src,
        deps = deps or {},
        ver = ver or "1.0",
        media = media or "all",
        enqueued = false
    }
end

-- スタイルをエンキュー
function _M.wp_enqueue_style(handle, src, deps, ver, media)
    -- 未登録の場合は登録してからエンキュー
    if not _M.styles[handle] and src then
        _M.wp_register_style(handle, src, deps, ver, media)
    end
    
    if _M.styles[handle] then
        _M.styles[handle].enqueued = true
        table.insert(_M.enqueued_styles, handle)
    end
end

-- スクリプトを登録
function _M.wp_register_script(handle, src, deps, ver, in_footer)
    _M.scripts[handle] = {
        src = src,
        deps = deps or {},
        ver = ver or "1.0",
        in_footer = in_footer or false,
        enqueued = false
    }
end

-- スクリプトをエンキュー
function _M.wp_enqueue_script(handle, src, deps, ver, in_footer)
    -- 未登録の場合は登録してからエンキュー
    if not _M.scripts[handle] and src then
        _M.wp_register_script(handle, src, deps, ver, in_footer)
    end
    
    if _M.scripts[handle] then
        _M.scripts[handle].enqueued = true
        table.insert(_M.enqueued_scripts, handle)
    end
end

-- 依存関係を解決してスタイルを並び替え
function _M.resolve_style_dependencies()
    local resolved = {}
    local visited = {}
    
    local function resolve(handle)
        if visited[handle] then
            return
        end
        
        visited[handle] = true
        local style = _M.styles[handle]
        
        if not style or not style.enqueued then
            return
        end
        
        -- 依存関係を先に解決
        for _, dep in ipairs(style.deps) do
            resolve(dep)
        end
        
        table.insert(resolved, handle)
    end
    
    for _, handle in ipairs(_M.enqueued_styles) do
        resolve(handle)
    end
    
    return resolved
end

-- 依存関係を解決してスクリプトを並び替え
function _M.resolve_script_dependencies()
    local resolved = {}
    local visited = {}
    
    local function resolve(handle)
        if visited[handle] then
            return
        end
        
        visited[handle] = true
        local script = _M.scripts[handle]
        
        if not script or not script.enqueued then
            return
        end
        
        -- 依存関係を先に解決
        for _, dep in ipairs(script.deps) do
            resolve(dep)
        end
        
        table.insert(resolved, handle)
    end
    
    for _, handle in ipairs(_M.enqueued_scripts) do
        resolve(handle)
    end
    
    return resolved
end

-- ヘッダーでスタイルを出力
function _M.print_styles()
    local resolved = _M.resolve_style_dependencies()
    local output = {}
    
    for _, handle in ipairs(resolved) do
        local style = _M.styles[handle]
        if style then
            local ver_param = style.ver and ("?ver=" .. style.ver) or ""
            table.insert(output, string.format(
                '<link rel="stylesheet" id="%s-css" href="%s%s" media="%s">',
                handle,
                style.src,
                ver_param,
                style.media
            ))
        end
    end
    
    return table.concat(output, "\n")
end

-- ヘッダーでスクリプトを出力
function _M.print_header_scripts()
    local resolved = _M.resolve_script_dependencies()
    local output = {}
    
    for _, handle in ipairs(resolved) do
        local script = _M.scripts[handle]
        if script and not script.in_footer then
            local ver_param = script.ver and ("?ver=" .. script.ver) or ""
            table.insert(output, string.format(
                '<script id="%s-js" src="%s%s"></script>',
                handle,
                script.src,
                ver_param
            ))
        end
    end
    
    return table.concat(output, "\n")
end

-- フッターでスクリプトを出力
function _M.print_footer_scripts()
    local resolved = _M.resolve_script_dependencies()
    local output = {}
    
    for _, handle in ipairs(resolved) do
        local script = _M.scripts[handle]
        if script and script.in_footer then
            local ver_param = script.ver and ("?ver=" .. script.ver) or ""
            table.insert(output, string.format(
                '<script id="%s-js" src="%s%s"></script>',
                handle,
                script.src,
                ver_param
            ))
        end
    end
    
    return table.concat(output, "\n")
end

-- スタイルをデキュー（削除）
function _M.wp_dequeue_style(handle)
    if _M.styles[handle] then
        _M.styles[handle].enqueued = false
    end
    
    -- enqueued_stylesから削除
    for i, h in ipairs(_M.enqueued_styles) do
        if h == handle then
            table.remove(_M.enqueued_styles, i)
            break
        end
    end
end

-- スクリプトをデキュー（削除）
function _M.wp_dequeue_script(handle)
    if _M.scripts[handle] then
        _M.scripts[handle].enqueued = false
    end
    
    -- enqueued_scriptsから削除
    for i, h in ipairs(_M.enqueued_scripts) do
        if h == handle then
            table.remove(_M.enqueued_scripts, i)
            break
        end
    end
end

-- インラインスタイルを追加
function _M.wp_add_inline_style(handle, css)
    if not _M.styles[handle] then
        return false
    end
    
    if not _M.styles[handle].inline_css then
        _M.styles[handle].inline_css = {}
    end
    
    table.insert(_M.styles[handle].inline_css, css)
    return true
end

-- インラインスクリプトを追加
function _M.wp_add_inline_script(handle, script, position)
    if not _M.scripts[handle] then
        return false
    end
    
    position = position or "after"
    
    if not _M.scripts[handle].inline_script then
        _M.scripts[handle].inline_script = {
            before = {},
            after = {}
        }
    end
    
    if position == "before" then
        table.insert(_M.scripts[handle].inline_script.before, script)
    else
        table.insert(_M.scripts[handle].inline_script.after, script)
    end
    
    return true
end

-- テーマのアセットを自動登録
function _M.register_theme_assets(theme_name)
    local template_loader = require "theme_engine.template_loader"
    local theme_uri = template_loader.get_theme_uri()
    
    -- テーマのメインスタイル
    _M.wp_register_style(
        theme_name .. "-style",
        theme_uri .. "/style.css",
        {},
        "1.0",
        "all"
    )
    
    -- 自動エンキュー
    _M.wp_enqueue_style(theme_name .. "-style")
end

-- すべてのアセットをリセット
function _M.reset()
    _M.styles = {}
    _M.enqueued_styles = {}
    _M.scripts = {}
    _M.enqueued_scripts = {}
end

return _M
