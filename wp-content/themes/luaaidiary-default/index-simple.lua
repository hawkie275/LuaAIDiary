-- Lua専用シンプルテーマ
local template = {}

function template.render(context)
    local output = {}
    local posts = context.posts or {}
    local query = context.query or {}
    local current_year = os.date("%Y")
    local current_page = tonumber(query.query_vars and query.query_vars.paged) or 1
    local max_pages = tonumber(query.max_num_pages) or 1
    local has_next_page = current_page < max_pages
    
    -- wp_functionsを読み込む
    local wp = require("theme_engine.wp_functions")
    local blog_title = wp.get_bloginfo("name")
    local blog_description = wp.get_bloginfo("description")
    
    table.insert(output, string.format([[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .post { margin: 20px 0; padding: 20px; border: 1px solid #ddd; }
        .post-title { color: #333; }
        .post-meta { color: #666; font-size: 0.9em; }
        .post-excerpt { margin: 15px 0; }
        .pagination { display: flex; justify-content: center; gap: 12px; margin: 24px 0; }
        .pagination a { padding: 8px 12px; border: 1px solid #ddd; text-decoration: none; color: #333; border-radius: 4px; }
        .pagination a:hover { background: #f5f5f5; }
        footer { text-align: center; margin-top: 24px; }
    </style>
</head>
<body>
    <header>
        <h1>%s</h1>
        <p>%s</p>
    </header>
    <main>
]], blog_title, blog_title, blog_description))
    
    if #posts > 0 then
        for i, post in ipairs(posts) do
            table.insert(output, string.format([[
        <article class="post">
            <h2 class="post-title"><a href="/%s">%s</a></h2>
            <div class="post-meta">
                投稿日: %s | 著者: %s
            </div>
            <div class="post-excerpt">
                %s
            </div>
        </article>
]], 
                post.slug or "",
                post.title or "無題",
                post.published_at or "",
                (post.author and post.author.display_name) or "不明",
                post.excerpt or (post.content and post.content:sub(1, 200) .. "...") or ""
            ))
        end

        if max_pages > 1 then
            local pagination_html = [[
        <nav class="pagination" aria-label="ページネーション">
]]

            if current_page > 1 then
                pagination_html = pagination_html .. string.format([[            <a href="/?paged=%d">前のページへ</a>
]], current_page - 1)
            end

            if has_next_page then
                pagination_html = pagination_html .. string.format([[            <a href="/?paged=%d">次のページへ</a>
]], current_page + 1)
            end

            pagination_html = pagination_html .. [[        </nav>
]]
            table.insert(output, pagination_html)
        end
    else
        table.insert(output, [[
        <p>投稿が見つかりませんでした。</p>
]])
    end
    
    table.insert(output, [[
    </main>
    <footer>
        <p>&copy; ]] .. current_year .. [[ LuaAIDiary. All rights reserved.</p>
    </footer>
</body>
</html>
]])
    
    return table.concat(output, "")
end

return template
