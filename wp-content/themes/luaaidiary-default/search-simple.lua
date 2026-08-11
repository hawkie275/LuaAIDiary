-- 検索結果表示用Luaテンプレート
local template = {}

local function escape_html(value)
    value = tostring(value or "")
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub('"', "&quot;")
    value = value:gsub("'", "&#39;")
    return value
end

local function ascii_lower(value)
    return tostring(value or ""):gsub("%u", string.lower)
end

local function highlight_keyword(value, keyword)
    value = tostring(value or "")
    keyword = tostring(keyword or "")

    if keyword == "" then
        return escape_html(value)
    end

    local lower_value = ascii_lower(value)
    local lower_keyword = ascii_lower(keyword)
    local parts = {}
    local search_from = 1

    while true do
        local start_pos, end_pos = lower_value:find(lower_keyword, search_from, true)
        if not start_pos then
            table.insert(parts, escape_html(value:sub(search_from)))
            break
        end

        table.insert(parts, escape_html(value:sub(search_from, start_pos - 1)))
        table.insert(parts, "<mark>" .. escape_html(value:sub(start_pos, end_pos)) .. "</mark>")
        search_from = end_pos + 1
    end

    return table.concat(parts, "")
end

local function build_content_snippet(content, keyword, length)
    content = tostring(content or "")
    keyword = tostring(keyword or "")
    length = length or 120

    content = content:gsub("!%[[^%]]*%]%([^%)]*%)", " ")
    content = content:gsub("%[[^%]]+%]%([^%)]*%)", function(label)
        return label:match("%[([^%]]+)%]") or " "
    end)
    content = content:gsub("[#>*_`%-]", " ")
    content = content:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if content == "" then
        return ""
    end

    local chars = {}
    local byte_pos = 1
    for char in content:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local char_start = byte_pos
        local char_end = byte_pos + #char - 1
        table.insert(chars, { value = char, start_pos = char_start, end_pos = char_end })
        byte_pos = char_end + 1
    end

    if #chars == 0 then
        return ""
    end

    local start_index = 1
    if keyword ~= "" then
        local match_start = ascii_lower(content):find(ascii_lower(keyword), 1, true)
        if match_start then
            local match_index = 1
            for index, char in ipairs(chars) do
                if char.start_pos <= match_start and match_start <= char.end_pos then
                    match_index = index
                    break
                end
            end
            start_index = math.max(1, match_index - math.floor(length / 3))
        end
    end

    local end_index = math.min(#chars, start_index + length - 1)
    local snippet_parts = {}
    for index = start_index, end_index do
        table.insert(snippet_parts, chars[index].value)
    end

    local snippet = table.concat(snippet_parts, "")
    if start_index > 1 then
        snippet = "..." .. snippet
    end
    if end_index < #chars then
        snippet = snippet .. "..."
    end

    return snippet
end

local function build_search_url(search_query, page)
    local encoded_query = search_query or ""
    if ngx and ngx.escape_uri then
        encoded_query = ngx.escape_uri(encoded_query)
    end

    return string.format("/search?s=%s&paged=%d", encoded_query, page)
end

function template.render(context)
    local output = {}
    local posts = context.posts or {}
    local query = context.query or {}
    local search_query = context.search_query or ""
    local current_year = os.date("%Y")
    local current_page = tonumber(query.query_vars and query.query_vars.paged) or 1
    local max_pages = tonumber(query.max_num_pages) or 0
    local found_posts = tonumber(query.found_posts) or 0
    local has_search_query = search_query ~= ""

    local wp = require("theme_engine.wp_functions")
    local blog_title = wp.get_bloginfo("name")
    local blog_description = wp.get_bloginfo("description")

    table.insert(output, string.format([[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>記事検索 - %s</title>
    <style>
        body { font-family: sans-serif; max-width: 1100px; margin: 0 auto; padding: 20px; }
        .site-layout { display: flex; gap: 24px; align-items: flex-start; }
        main { flex: 1; min-width: 0; }
        .sidebar { width: 360px; padding: 20px; border: 1px solid #ddd; background: #fafafa; border-radius: 6px; }
        .search-form { display: flex; gap: 8px; margin-bottom: 18px; }
        .search-form input[type="search"] { flex: 1; min-width: 0; padding: 8px; border: 1px solid #ccc; border-radius: 4px; }
        .search-form button { padding: 8px 12px; border: 1px solid #333; background: #333; color: #fff; border-radius: 4px; cursor: pointer; }
        .search-form button:hover { background: #555; }
        .search-summary { color: #666; font-size: 0.95em; margin: 12px 0; }
        .search-results { list-style: none; padding: 0; margin: 16px 0; }
        .search-result { padding: 14px 0; border-top: 1px solid #ddd; }
        .search-result-title { margin: 0 0 6px; font-size: 1.05em; }
        .search-result-title a { color: #005fcc; font-weight: 700; text-decoration: underline; text-underline-offset: 2px; }
        .search-result-title a:hover { color: #003f8c; }
        .search-result-meta { color: #666; font-size: 0.85em; }
        .search-result-excerpt { margin: 8px 0 0; line-height: 1.6; }
        mark { background: #fff3a3; padding: 0 2px; }
        .pagination { display: flex; justify-content: center; gap: 12px; margin: 20px 0 0; }
        .pagination a { padding: 8px 12px; border: 1px solid #ddd; text-decoration: none; color: #333; border-radius: 4px; background: #fff; }
        .pagination a:hover { background: #f5f5f5; }
        footer { text-align: center; margin-top: 24px; }
        @media (max-width: 768px) {
            .site-layout { flex-direction: column; }
            .sidebar { width: 100%%; box-sizing: border-box; }
        }
    </style>
</head>
<body>
    <header>
        <h1>%s</h1>
        <p>%s</p>
    </header>
    <div class="site-layout">
    <main>
        <h2>記事検索</h2>
        <p>検索フォームにキーワードを入力すると、公開記事のタイトル・抜粋・本文から部分一致で検索できます。</p>
        <p><a href="/">トップページに戻る</a></p>
    </main>
    <aside class="sidebar" aria-label="検索結果">
        <h2>検索</h2>
        <form class="search-form" action="/search" method="get">
            <input type="search" name="s" value="%s" placeholder="検索語を入力" aria-label="検索語">
            <button type="submit">検索</button>
        </form>
        <div class="search-inline-results" aria-live="polite">
]], blog_title, blog_title, blog_description, escape_html(search_query)))

    if not has_search_query then
        table.insert(output, [[
        <p>検索語を入力してください。</p>
]])
    elseif #posts > 0 then
        table.insert(output, string.format([[
        <p class="search-summary">「%s」の検索結果: %d件</p>
        <ul class="search-results">
]], escape_html(search_query), found_posts))

        for _, post in ipairs(posts) do
            local snippet = build_content_snippet(post.content, search_query, 140)
            if snippet == "" then
                snippet = post.title or ""
            end

            table.insert(output, string.format([[
            <li class="search-result">
                <h3 class="search-result-title"><a href="/%s">%s</a></h3>
                <div class="search-result-meta">投稿日: %s</div>
                <p class="search-result-excerpt">%s</p>
            </li>
]],
                escape_html(post.slug or ""),
                highlight_keyword(post.title or "無題", search_query),
                escape_html(post.published_at or ""),
                highlight_keyword(snippet, search_query)
            ))
        end

        table.insert(output, [[
        </ul>
]])

        if max_pages > 1 then
            table.insert(output, [[
        <nav class="pagination" aria-label="検索結果ページネーション">
]])
            if current_page > 1 then
                table.insert(output, string.format([[            <a href="%s">前のページへ</a>
]], build_search_url(search_query, current_page - 1)))
            end
            if current_page < max_pages then
                table.insert(output, string.format([[            <a href="%s">次のページへ</a>
]], build_search_url(search_query, current_page + 1)))
            end
            table.insert(output, [[        </nav>
]])
        end
    else
        table.insert(output, string.format([[
        <p class="search-summary">「%s」の検索結果はありませんでした。</p>
]], escape_html(search_query)))
    end

    table.insert(output, [[
        </div>
    </aside>
    </div>
    <footer>
        <p>&copy; ]] .. current_year .. [[ LuaAIDiary. All rights reserved.</p>
    </footer>
</body>
</html>
]])

    return table.concat(output, "")
end

return template
