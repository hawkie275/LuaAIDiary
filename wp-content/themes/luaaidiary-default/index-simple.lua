-- Lua専用シンプルテーマ
local template = {}

function template.render(context)
    local output = {}
    local posts = context.posts or {}
    local query = context.query or {}
    
    table.insert(output, [[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LuaAIDiary</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .post { margin: 20px 0; padding: 20px; border: 1px solid #ddd; }
        .post-title { color: #333; }
        .post-meta { color: #666; font-size: 0.9em; }
        .post-excerpt { margin: 15px 0; }
    </style>
</head>
<body>
    <header>
        <h1>LuaAIDiary</h1>
        <p>AIと共に記録する日記システム</p>
    </header>
    <main>
]])
    
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
    else
        table.insert(output, [[
        <p>投稿が見つかりませんでした。</p>
]])
    end
    
    table.insert(output, [[
    </main>
    <footer>
        <p>&copy; 2025 LuaAIDiary. All rights reserved.</p>
    </footer>
</body>
</html>
]])
    
    return table.concat(output, "")
end

return template
