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
        body { font-family: sans-serif; max-width: 1100px; margin: 0 auto; padding: 20px; }
        .site-layout { display: flex; gap: 24px; align-items: flex-start; }
        main { flex: 1; min-width: 0; }
        .sidebar { width: 340px; box-sizing: border-box; padding: 20px; border: 1px solid #ddd; background: #fafafa; border-radius: 6px; overflow-wrap: anywhere; }
        .search-form { display: flex; gap: 8px; }
        .search-form input[type="search"] { flex: 1; min-width: 0; padding: 8px; border: 1px solid #ccc; border-radius: 4px; }
        .search-form button { padding: 8px 12px; border: 1px solid #333; background: #333; color: #fff; border-radius: 4px; cursor: pointer; }
        .search-form button:hover { background: #555; }
        .search-status { color: #666; margin: 12px 0 0; }
        .search-summary { color: #333; font-size: 0.95em; margin: 16px 0 10px; }
        .search-results { list-style: none; padding: 0; margin: 12px 0 0; }
        .search-result { padding: 14px 0; border-top: 1px solid #ddd; }
        .search-result-title { margin: 0 0 8px; font-size: 1em; line-height: 1.45; }
        .search-result-title a { color: #005fcc; font-weight: 700; text-decoration: underline; text-underline-offset: 2px; }
        .search-result-title a:hover { color: #003f8c; }
        .search-result-meta { color: #666; font-size: 0.85em; margin-bottom: 8px; }
        .search-result-excerpt { margin: 0; line-height: 1.6; font-size: 0.95em; }
        .search-inline-results mark { background: #fff3a3; padding: 0 2px; }
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
        @media (max-width: 768px) {
            .site-layout { flex-direction: column; }
            .sidebar { width: 100%%; box-sizing: border-box; }
        }
    </style>
</head>
<body>
    <div class="site-layout">
    <main>
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
    </main>
    <aside class="sidebar" aria-label="サイト内検索">
        <h2>記事検索</h2>
        <form class="search-form" action="/search" method="get">
            <input type="search" name="s" placeholder="検索語を入力" aria-label="検索語">
            <button type="submit">検索</button>
        </form>
        <div class="search-inline-results" aria-live="polite"></div>
    </aside>
    </div>
    <script>
        (function () {
            var sidebar = document.querySelector('.sidebar');
            var form = sidebar && sidebar.querySelector('.search-form');
            if (!sidebar || !form || !window.fetch || !window.DOMParser) { return; }

            form.addEventListener('submit', function (event) {
                event.preventDefault();

                var input = form.querySelector('input[name="s"]');
                var searchQuery = input ? input.value.trim() : '';
                var results = sidebar.querySelector('.search-inline-results');

                if (!results) {
                    results = document.createElement('div');
                    results.className = 'search-inline-results';
                    results.setAttribute('aria-live', 'polite');
                    sidebar.appendChild(results);
                }

                if (!searchQuery) {
                    results.innerHTML = '<p class="search-status">検索語を入力してください。</p>';
                    return;
                }

                results.innerHTML = '<p class="search-status">検索中...</p>';

                fetch('/search?s=' + encodeURIComponent(searchQuery), {
                    headers: { 'X-Requested-With': 'XMLHttpRequest' }
                })
                    .then(function (response) { return response.text(); })
                    .then(function (html) {
                        var doc = new DOMParser().parseFromString(html, 'text/html');
                        var remoteSidebar = doc.querySelector('.sidebar');
                        var remoteResults = remoteSidebar && remoteSidebar.querySelector('.search-inline-results');

                        if (remoteResults) {
                            results.innerHTML = remoteResults.innerHTML;
                        } else if (remoteSidebar) {
                            var remoteForm = remoteSidebar.querySelector('.search-form');
                            if (remoteForm) { remoteForm.remove(); }
                            var remoteHeading = remoteSidebar.querySelector('h2');
                            if (remoteHeading) { remoteHeading.remove(); }
                            results.innerHTML = remoteSidebar.innerHTML;
                        } else {
                            results.innerHTML = '<p class="search-status">検索結果を取得できませんでした。</p>';
                        }
                    })
                    .catch(function () {
                        results.innerHTML = '<p class="search-status">検索結果を取得できませんでした。</p>';
                    });
            });
        })();
    </script>
</body>
</html>
]])
    
    return table.concat(output, "")
end

return template
