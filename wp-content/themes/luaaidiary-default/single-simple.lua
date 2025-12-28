-- 個別投稿表示用Luaテンプレート
local template = {}

function template.render(context)
    local output = {}
    local post = context.post
    
    if not post then
        table.insert(output, [[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>投稿が見つかりません - LuaAIDiary</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
    </style>
</head>
<body>
    <h1>投稿が見つかりません</h1>
    <p><a href="/">トップページに戻る</a></p>
</body>
</html>
]])
        return table.concat(output, "")
    end
    
    table.insert(output, string.format([[
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s - LuaAIDiary</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .post-header { border-bottom: 2px solid #333; padding-bottom: 20px; margin-bottom: 30px; }
        .post-title { color: #333; margin-bottom: 10px; }
        .post-meta { color: #666; font-size: 0.9em; }
        .post-content { line-height: 1.8; margin: 30px 0; }
        .post-footer { border-top: 1px solid #ddd; padding-top: 20px; margin-top: 40px; }
        .back-link { display: inline-block; margin-top: 20px; color: #0066cc; text-decoration: none; }
        .back-link:hover { text-decoration: underline; }
        
        /* テーブルスタイル */
        .post-content table { border-collapse: collapse; width: 100%%; margin: 20px 0; }
        .post-content th, .post-content td { border: 1px solid #ddd; padding: 8px 12px; }
        .post-content th { background-color: #f5f5f5; font-weight: bold; }
        .post-content tr:nth-child(even) { background-color: #f9f9f9; }
    </style>
</head>
<body>
    <article class="post">
        <header class="post-header">
            <h1 class="post-title">%s</h1>
            <div class="post-meta">
                投稿日: %s
]], 
        post.title or "無題",
        post.title or "無題",
        post.published_at or post.created_at or ""
    ))
    
    if post.author and post.author.display_name then
        table.insert(output, string.format(" | 著者: %s", post.author.display_name))
    end
    
    table.insert(output, [[

            </div>
        </header>
        <div class="post-content">
]])
    
    -- Markdownをレンダリング
    local content = post.content or ""
    local ok, markdown = pcall(require, "utils.markdown")
    if ok and content ~= "" then
        content = markdown.render_markdown(content)
    end
    table.insert(output, content)
    
    table.insert(output, [[

        </div>
        <footer class="post-footer">
]])
    
    if post.categories and #post.categories > 0 then
        table.insert(output, "            <div>カテゴリ: ")
        local cat_links = {}
        for _, cat in ipairs(post.categories) do
            table.insert(cat_links, string.format('<a href="/category/%s">%s</a>', cat.slug, cat.name))
        end
        table.insert(output, table.concat(cat_links, ", "))
        table.insert(output, "</div>\n")
    end
    
    if post.tags and #post.tags > 0 then
        table.insert(output, "            <div>タグ: ")
        local tag_links = {}
        for _, tag in ipairs(post.tags) do
            table.insert(tag_links, string.format('<a href="/tag/%s">%s</a>', tag.slug, tag.name))
        end
        table.insert(output, table.concat(tag_links, ", "))
        table.insert(output, "</div>\n")
    end
    
    table.insert(output, [[
        </footer>
    </article>
    <a href="/" class="back-link">← トップページに戻る</a>
</body>
</html>
]])
    
    return table.concat(output, "")
end

return template
