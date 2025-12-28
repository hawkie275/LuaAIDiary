-- app/utils/markdown.lua
-- Markdown to HTML converter

local _M = {}

-- wpautop風の段落変換関数
local function wpautop(text)
    if not text or text == "" then
        return ""
    end
    
    -- 改行を統一
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    
    -- 複数の改行を段落に変換
    local blocks = {}
    for block in text:gmatch("([^\n]+)") do
        if block ~= "" and not block:match("^%s*$") then
            -- HTMLタグで始まる行はそのまま
            if block:match("^%s*<") then
                table.insert(blocks, block)
            else
                table.insert(blocks, "<p>" .. block .. "</p>")
            end
        end
    end
    
    return table.concat(blocks, "\n")
end

-- Markdownテーブルをレンダリング
local function render_table(table_text)
    local lines = {}
    for line in table_text:gmatch("([^\n]+)") do
        if line:match("|") then
            table.insert(lines, line)
        end
    end
    
    if #lines < 1 then
        return table_text
    end
    
    local result = {"<table>"}
    
    -- ヘッダー行を処理
    local header_line = lines[1]
    local headers = {}
    for cell in header_line:gmatch("|([^|]+)") do
        local trimmed = cell:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(headers, trimmed)
        end
    end
    
    -- 2行目が区切り行かどうかを判定
    local has_separator = false
    local alignments = {}
    local data_start_index = 2
    
    if #lines >= 2 then
        local second_line = lines[2]
        
        -- 区切り行の判定：すべてのセルが :-+: や -+: や :-+ や -+ のパターンか
        local is_separator = true
        local temp_alignments = {}
        
        for align_cell in second_line:gmatch("|([^|]+)") do
            local trimmed = align_cell:match("^%s*(.-)%s*$")
            -- 区切り行のパターンチェック
            if trimmed:match("^:%-+:$") then
                table.insert(temp_alignments, "center")
            elseif trimmed:match("^%-+:$") then
                table.insert(temp_alignments, "right")
            elseif trimmed:match("^:%-+$") then
                table.insert(temp_alignments, "left")
            elseif trimmed:match("^%-+$") then
                table.insert(temp_alignments, "left")
            elseif trimmed == "" then
                -- 空のセルは許容（行頭・行末の|の場合）
            else
                -- 区切り行ではない
                is_separator = false
                break
            end
        end
        
        if is_separator and #temp_alignments > 0 then
            has_separator = true
            alignments = temp_alignments
            data_start_index = 3
        end
    end
    
    -- ヘッダーを出力
    if #headers > 0 then
        table.insert(result, "<thead><tr>")
        for i, header in ipairs(headers) do
            local align = alignments[i] or "left"
            local style = string.format(' style="text-align:%s"', align)
            table.insert(result, "<th" .. style .. ">" .. header .. "</th>")
        end
        table.insert(result, "</tr></thead>")
    end
    
    -- データ行を処理
    if #lines >= data_start_index then
        table.insert(result, "<tbody>")
        for i = data_start_index, #lines do
            local row_cells = {}
            for cell in lines[i]:gmatch("|([^|]+)") do
                local trimmed = cell:match("^%s*(.-)%s*$")
                if trimmed ~= "" then
                    table.insert(row_cells, trimmed)
                end
            end
            
            if #row_cells > 0 then
                table.insert(result, "<tr>")
                for j, cell in ipairs(row_cells) do
                    local align = alignments[j] or "left"
                    local style = string.format(' style="text-align:%s"', align)
                    table.insert(result, "<td" .. style .. ">" .. cell .. "</td>")
                end
                table.insert(result, "</tr>")
            end
        end
        table.insert(result, "</tbody>")
    end
    
    table.insert(result, "</table>")
    return table.concat(result, "\n")
end

-- Markdownをレンダリング
function _M.render_markdown(text)
    if not text or text == "" then
        return ""
    end
    
    local html = text
    
    -- テーブルを一時的に保護してレンダリング
    local tables = {}
    local table_index = 0
    local in_table = false
    local table_lines = {}
    local non_table_lines = {}
    
    for line in (html .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^%s*|") then
            -- テーブル行
            if not in_table then
                in_table = true
                table_lines = {}
            end
            table.insert(table_lines, line)
        else
            -- テーブル以外の行
            if in_table then
                -- テーブルを終了してレンダリング
                table_index = table_index + 1
                local placeholder = "___TABLE_" .. table_index .. "___"
                tables[placeholder] = render_table(table.concat(table_lines, "\n"))
                table.insert(non_table_lines, placeholder)
                in_table = false
                table_lines = {}
            end
            table.insert(non_table_lines, line)
        end
    end
    
    -- 最後のテーブルを処理
    if in_table and #table_lines > 0 then
        table_index = table_index + 1
        local placeholder = "___TABLE_" .. table_index .. "___"
        tables[placeholder] = render_table(table.concat(table_lines, "\n"))
        table.insert(non_table_lines, placeholder)
    end
    
    html = table.concat(non_table_lines, "\n")
    
    -- コードブロック（```）を一時的に保護
    local code_blocks = {}
    local code_block_index = 0
    html = html:gsub("```([^`]+)```", function(code)
        code_block_index = code_block_index + 1
        local placeholder = "___CODE_BLOCK_" .. code_block_index .. "___"
        code_blocks[placeholder] = "<pre><code>" .. code .. "</code></pre>"
        return placeholder
    end)
    
    -- インラインコード（`）を一時的に保護
    local inline_codes = {}
    local inline_code_index = 0
    html = html:gsub("`([^`]+)`", function(code)
        inline_code_index = inline_code_index + 1
        local placeholder = "___INLINE_CODE_" .. inline_code_index .. "___"
        inline_codes[placeholder] = "<code>" .. code .. "</code>"
        return placeholder
    end)
    
    -- 見出し（行頭のみマッチ）
    html = html:gsub("^#### ([^\n]+)", "<h4>%1</h4>")
    html = html:gsub("\n#### ([^\n]+)", "\n<h4>%1</h4>")
    html = html:gsub("^### ([^\n]+)", "<h3>%1</h3>")
    html = html:gsub("\n### ([^\n]+)", "\n<h3>%1</h3>")
    html = html:gsub("^## ([^\n]+)", "<h2>%1</h2>")
    html = html:gsub("\n## ([^\n]+)", "\n<h2>%1</h2>")
    html = html:gsub("^# ([^\n]+)", "<h1>%1</h1>")
    html = html:gsub("\n# ([^\n]+)", "\n<h1>%1</h1>")
    
    -- 太字（**text**）
    html = html:gsub("%*%*([^%*\n]+)%*%*", "<strong>%1</strong>")
    
    -- 斜体（*text*）
    html = html:gsub("%*([^%*\n]+)%*", "<em>%1</em>")
    
    -- リンク（[text](url)）
    html = html:gsub("%[([^%]]+)%]%(([^%)]+)%)", "<a href='%2'>%1</a>")
    
    -- リスト（順序なし、ネスト対応）
    local input_lines = {}
    for line in html:gmatch("([^\n]*)\n?") do
        table.insert(input_lines, line)
    end
    
    local output_lines = {}
    local level_stack = {}  -- 各レベルのul開閉状態を追跡
    local i = 1
    
    while i <= #input_lines do
        local line = input_lines[i]
        
        -- インデントレベルを取得（スペース2個で1レベル）
        local spaces = line:match("^(%s*)")
        local level = spaces and math.floor(#spaces / 2) or 0
        
        -- リスト項目をマッチ
        local marker, item = line:match("^%s*([%*%-])%s+(.+)")
        
        if marker and item then
            local current_depth = #level_stack
            
            -- レベルが上がった場合（ネストが深くなる）
            while level > current_depth do
                table.insert(output_lines, "<ul>")
                table.insert(level_stack, true)
                current_depth = #level_stack
            end
            
            -- レベルが下がった場合（ネストが浅くなる）
            while level < current_depth do
                table.insert(output_lines, "</li>")
                table.insert(output_lines, "</ul>")
                table.remove(level_stack)
                current_depth = #level_stack
            end
            
            -- 同じレベルの項目の場合、前のliを閉じる
            if current_depth > 0 and level == current_depth - 1 then
                table.insert(output_lines, "</li>")
            end
            
            -- 新しいリスト項目を開始
            table.insert(output_lines, "<li>" .. item)
        else
            -- リスト以外の行
            -- すべてのリストを閉じる
            while #level_stack > 0 do
                table.insert(output_lines, "</li>")
                table.insert(output_lines, "</ul>")
                table.remove(level_stack)
            end
            
            if line ~= "" then
                table.insert(output_lines, line)
            end
        end
        
        i = i + 1
    end
    
    -- 残っているリストを閉じる
    while #level_stack > 0 do
        table.insert(output_lines, "</li>")
        table.insert(output_lines, "</ul>")
        table.remove(level_stack)
    end
    
    html = table.concat(output_lines, "\n")
    
    -- テーブルを先に復元（段落変換の前）
    -- gsubは改行を含むパターンに弱いので、split/joinで置換
    for placeholder, table_html in pairs(tables) do
        -- プレースホルダーを単純な文字列置換で処理
        local parts = {}
        local last_pos = 1
        local pos = 1
        while pos <= #html do
            local found_pos = html:find(placeholder, pos, true)  -- plainテキスト検索
            if found_pos then
                table.insert(parts, html:sub(last_pos, found_pos - 1))
                table.insert(parts, table_html)
                last_pos = found_pos + #placeholder
                pos = last_pos
            else
                break
            end
        end
        if last_pos <= #html then
            table.insert(parts, html:sub(last_pos))
        end
        if #parts > 0 then
            html = table.concat(parts)
        end
    end
    
    -- 段落変換（HTMLタグがすでにある行は除く）
    local final_lines = {}
    for line in html:gmatch("([^\n]*)\n?") do
        if line ~= "" then
            -- すでにHTMLタグで囲まれている行はそのまま
            if line:match("^%s*<") then
                table.insert(final_lines, line)
            else
                -- プレースホルダーを含む行もそのまま
                if line:match("___CODE_BLOCK_") or line:match("___INLINE_CODE_") then
                    table.insert(final_lines, line)
                else
                    table.insert(final_lines, "<p>" .. line .. "</p>")
                end
            end
        end
    end
    html = table.concat(final_lines, "\n")
    
    -- コードブロックを復元
    for placeholder, code_html in pairs(code_blocks) do
        html = html:gsub(placeholder, code_html)
    end
    
    -- インラインコードを復元
    for placeholder, code_html in pairs(inline_codes) do
        html = html:gsub(placeholder, code_html)
    end
    
    return html
end

return _M
