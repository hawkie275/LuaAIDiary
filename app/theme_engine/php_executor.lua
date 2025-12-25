-- PHPコードを実行するためのインタープリタ
-- セキュリティを考慮し、危険な関数は制限

local _M = {}

-- 危険な関数のブラックリスト
local DANGEROUS_FUNCTIONS = {
    eval = true,
    system = true,
    exec = true,
    shell_exec = true,
    passthru = true,
    popen = true,
    proc_open = true,
    pcntl_exec = true,
}

-- PHPファイルを実行
function _M.execute_php_file(file_path, context)
    -- PHPファイルを読み込み
    local file, err = io.open(file_path, "r")
    if not file then
        return nil, "ファイルが見つかりません: " .. file_path
    end
    
    local php_code = file:read("*all")
    file:close()
    
    -- PHPコードを解析・実行
    return _M.execute_php_code(php_code, context)
end

-- PHPコードを実行
function _M.execute_php_code(php_code, context)
    -- コンテキストをグローバルスコープに設定
    _M.setup_wp_globals(context)
    
    -- PHPコードを処理
    local output, err = _M.process_php_template(php_code, context)
    if not output then
        return nil, err
    end
    
    return output, nil
end

-- PHPテンプレートを処理（混在HTMLとPHPコード）
function _M.process_php_template(php_code, context)
    -- ステップ1: テンプレート全体を前処理して代替制御構文を展開
    local preprocessed = _M.preprocess_alternative_syntax(php_code)
    
    local output = {}
    local pos = 1
    
    while pos <= #preprocessed do
        -- <?php タグを探す
        local php_start, php_end = preprocessed:find("<%?php%s+", pos)
        if not php_start then
            -- <?= ショートタグを探す
            php_start, php_end = preprocessed:find("<%?=", pos)
        end
        
        if php_start then
            -- PHPタグの前のHTMLを出力
            if php_start > pos then
                table.insert(output, preprocessed:sub(pos, php_start - 1))
            end
            
            -- PHPコードの終了タグを探す
            local close_start, close_end = preprocessed:find("%?>", php_end + 1)
            if close_start then
                local code_block = preprocessed:sub(php_end + 1, close_start - 1)
                
                -- ショートタグの場合はechoとして処理
                if preprocessed:sub(php_start, php_end):match("<%?=") then
                    code_block = "echo " .. code_block
                end
                
                -- PHPコードを実行
                local result, err = _M.execute_php_block(code_block, context)
                if result then
                    table.insert(output, result)
                elseif err then
                    -- ngxが利用できない環境でもエラーを無視
                    if ngx then
                        ngx.log(ngx.ERR, "PHP実行エラー: ", err)
                    end
                end
                
                pos = close_end + 1
            else
                -- 閉じタグが見つからない場合は残り全体をPHPとして処理
                local code_block = preprocessed:sub(php_end + 1)
                local result, err = _M.execute_php_block(code_block, context)
                if result then
                    table.insert(output, result)
                end
                break
            end
        else
            -- 残りのHTMLを出力
            table.insert(output, preprocessed:sub(pos))
            break
        end
    end
    
    return table.concat(output, ""), nil
end

-- テンプレートの前処理：PHPタグを削除してHTMLをecho文に変換
function _M.preprocess_alternative_syntax(template)
    local result = template
    local parts = {}
    local pos = 1
    local in_php = false
    
    -- すべてのPHPブロックとHTMLを統合
    while pos <= #result do
        local php_start, php_end = result:find("<%?php%s+", pos)
        local short_start, short_end = result:find("<%?=", pos)
        
        -- 最も近いタグを選択
        if short_start and (not php_start or short_start < php_start) then
            php_start, php_end = short_start, short_end
        end
        
        if php_start then
            -- PHPタグの前のHTMLをecho文として追加
            if php_start > pos then
                local html = result:sub(pos, php_start - 1)
                if html:match("%S") or html:match("\n") then
                    -- HTMLをecho文に変換（Luaの長文字列リテラルを使用）
                    -- ]] をエスケープ
                    html = html:gsub("%]%]", "]]..\"]]\"..[[")
                    table.insert(parts, " echo [[" .. html .. "]]; ")
                end
            end
            
            -- PHPコードの終了を探す
            local close_start, close_end = result:find("%?>", php_end + 1)
            if close_start then
                local php_code = result:sub(php_end + 1, close_start - 1)
                
                -- ショートタグの場合
                if result:sub(php_start, php_end):match("<%?=") then
                    table.insert(parts, " echo " .. php_code .. "; ")
                else
                    -- 代替構文を通常の構文に変換
                    php_code = php_code:gsub("if%s*(%b())%s*:", "if%1 {")
                    php_code = php_code:gsub("elseif%s*(%b())%s*:", "} elseif%1 {")
                    php_code = php_code:gsub("else%s*:", "} else {")
                    php_code = php_code:gsub("endif%s*;?", "}")
                    php_code = php_code:gsub("while%s*(%b())%s*:", "while%1 {")
                    php_code = php_code:gsub("endwhile%s*;?", "}")
                    php_code = php_code:gsub("for%s*(%b())%s*:", "for%1 {")
                    php_code = php_code:gsub("endfor%s*;?", "}")
                    
                    table.insert(parts, " " .. php_code .. " ")
                end
                
                pos = close_end + 1
            else
                break
            end
        else
            -- 残りのHTMLを追加
            local html = result:sub(pos)
            if html:match("%S") then
                -- ]] をエスケープ
                html = html:gsub("%]%]", "]]..\"]]\"..[[")
                table.insert(parts, " echo [[" .. html .. "]]; ")
            end
            break
        end
    end
    
    -- 1つの大きなPHPブロックとして返す
    return "<?php " .. table.concat(parts, "") .. " ?>"
end

-- PHPコードブロックを実行
function _M.execute_php_block(php_code, context)
    -- 簡易的なPHP構文の変換とエミュレーション
    local output_buffer = {}
    
    -- 出力をキャプチャするための関数
    local function php_echo(...)
        local args = {...}
        for i, v in ipairs(args) do
            table.insert(output_buffer, tostring(v))
        end
    end
    
    -- WordPress関数をLua環境に設定
    local wp = require "theme_engine.wp_functions"
    local env = {
        -- PHP互換関数
        echo = php_echo,
        print = php_echo,
        date = wp.date,
        
        -- WordPress関数
        bloginfo = wp.bloginfo,
        wp_title = wp.wp_title,
        language_attributes = wp.language_attributes,
        get_header = wp.get_header,
        get_footer = wp.get_footer,
        get_sidebar = wp.get_sidebar,
        get_template_part = wp.get_template_part,
        have_posts = wp.have_posts,
        the_post = wp.the_post,
        the_title = wp.the_title,
        the_content = wp.the_content,
        the_excerpt = wp.the_excerpt,
        the_permalink = wp.the_permalink,
        the_date = wp.the_date,
        the_time = wp.the_time,
        the_author = wp.the_author,
        the_category = wp.the_category,
        the_tags = wp.the_tags,
        get_the_title = wp.get_the_title,
        get_the_content = wp.get_the_content,
        get_the_permalink = wp.get_the_permalink,
        get_the_post_thumbnail = wp.get_the_post_thumbnail,
        wp_head = wp.wp_head,
        wp_footer = wp.wp_footer,
        body_class = wp.body_class,
        post_class = wp.post_class,
        wp_nav_menu = wp.wp_nav_menu,
        home_url = wp.home_url,
        site_url = wp.site_url,
        is_home = wp.is_home,
        is_single = wp.is_single,
        is_page = wp.is_page,
        is_category = wp.is_category,
        is_tag = wp.is_tag,
        is_archive = wp.is_archive,
        is_search = wp.is_search,
        is_404 = wp.is_404,
        
        -- コンテキストデータ
        post = context.post,
        posts = context.posts,
        
        -- ngxライブラリ（HTMLの直接出力用）
        ngx = ngx,
        
        -- 標準Lua関数へのアクセス
        pairs = pairs,
        ipairs = ipairs,
        tostring = tostring,
        tonumber = tonumber,
        type = type,
        string = string,
        table = table,
        math = math,
    }
    
    -- PHPコードの簡易変換
    local lua_code = _M.php_to_lua(php_code)
    
    -- Luaコードとしてコンパイル
    local func, err = loadstring("return function() " .. lua_code .. " end")
    if not func then
        return nil, "Luaコンパイルエラー: " .. tostring(err)
    end
    
    -- 実行環境を設定して実行
    local executable = func()
    setfenv(executable, env)
    
    local success, result = pcall(executable)
    if not success then
        return nil, "実行エラー: " .. tostring(result)
    end
    
    return table.concat(output_buffer, ""), nil
end

-- PHPコードをLuaに変換（簡易版）
function _M.php_to_lua(php_code)
    local code = php_code
    
    -- 診断ログ: 変換前のコード
    if ngx and code:match("have_posts") then
        ngx.log(ngx.ERR, "[DIAGNOSIS] php_to_lua 変換前: ", code:sub(1, 100))
    end
    
    -- コメントを除去
    code = code:gsub("/%*.-%*/", "")
    code = code:gsub("//[^\n]*", "")
    code = code:gsub("#[^\n]*", "")
    
    -- 変数の $ を削除
    code = code:gsub("%$([%w_]+)", "%1")
    
    -- 通常のPHP構文を変換
    -- if (...) { を if (...) then に変換
    code = code:gsub("(if%s*%b())%s*{%s*", "%1 then ")
    
    -- elseif (...) { を elseif (...) then に変換
    code = code:gsub("(elseif%s*%b())%s*{%s*", "%1 then ")
    
    -- else { を else に変換
    code = code:gsub("else%s*{%s*", "else ")
    
    -- while (...) { を while (...) do に変換
    code = code:gsub("(while%s*%b())%s*{%s*", "%1 do ")
    
    -- for (...) { を for (...) do に変換
    code = code:gsub("(for%s*%b())%s*{%s*", "%1 do ")
    
    -- 閉じ波括弧 } を end に変換
    code = code:gsub("}%s*", " end ")
    
    -- PHP代替構文も念のため変換（前処理で変換されているはずだが）
    code = code:gsub("endif%s*", "end ")
    code = code:gsub("endwhile%s*", "end ")
    code = code:gsub("endfor%s*", "end ")
    code = code:gsub("(if%s*%b())%s*:%s*", "%1 then ")
    code = code:gsub("(elseif%s*%b())%s*:%s*", "%1 then ")
    code = code:gsub("else%s*:%s*", "else ")
    code = code:gsub("(while%s*%b())%s*:%s*", "%1 do ")
    code = code:gsub("(for%s*%b())%s*:%s*", "%1 do ")
    
    -- echo を関数呼び出しに変換
    code = code:gsub("echo%s+([^;]+);", "echo(%1)")
    
    -- print を関数呼び出しに変換
    code = code:gsub("print%s+([^;]+);", "print(%1)")
    
    -- セミコロンを改行に変換
    code = code:gsub(";", "\n")
    
    -- PHP の -> は Lua では使わない（オブジェクト指向のメソッド呼び出しは別途処理）
    -- code = code:gsub("%-?>", ".")  -- この変換は問題を起こすので削除
    
    -- PHPの文字列連結演算子 . を .. に変換
    -- ただし、この変換は ngx.print のような関数呼び出しを壊すので削除
    -- code = code:gsub("%.%s*", ".. ")  -- この変換も削除
    
    -- 診断ログ: 変換後のコード
    if ngx and php_code:match("have_posts") then
        ngx.log(ngx.ERR, "[DIAGNOSIS] php_to_lua 変換後: ", code:sub(1, 100))
    end
    
    return code
end

-- WordPressグローバル変数の設定
function _M.setup_wp_globals(context)
    local wp = require "theme_engine.wp_functions"
    
    -- 診断ログ: コンテキストの内容を確認
    ngx.log(ngx.ERR, "[DIAGNOSIS] php_executor.setup_wp_globals 開始")
    if context.posts then
        ngx.log(ngx.ERR, "[DIAGNOSIS] context.posts サイズ: ", #context.posts)
        if #context.posts > 0 then
            ngx.log(ngx.ERR, "[DIAGNOSIS] context.posts[1].title: ", context.posts[1].title or "nil")
        end
    else
        ngx.log(ngx.ERR, "[DIAGNOSIS] context.posts は nil")
    end
    
    -- コンテキストをWordPress関数に設定
    if context.post then
        wp.set_current_post(context.post)
    end
    
    if context.posts then
        wp.set_posts(context.posts)
    end
    
    if context.query then
        wp.set_query(context.query)
    end
    
    -- 診断ログ: 設定後の状態を確認
    ngx.log(ngx.ERR, "[DIAGNOSIS] wp.posts サイズ: ", #wp.posts)
end

-- 危険な関数のチェック
function _M.check_dangerous_function(func_name)
    if DANGEROUS_FUNCTIONS[func_name] then
        -- ngxが利用できない環境でもエラーを無視
        if ngx then
            ngx.log(ngx.ERR, "危険な関数の使用を検出: " .. func_name)
        end
        return false
    end
    return true
end

return _M