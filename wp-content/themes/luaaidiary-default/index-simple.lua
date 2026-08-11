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
        body { font-family: sans-serif; max-width: 1100px; margin: 0 auto; padding: 20px; }
        .site-layout { display: flex; gap: 24px; align-items: flex-start; }
        main { flex: 1; min-width: 0; }
        .sidebar { width: 340px; box-sizing: border-box; margin-top: 20px; padding: 20px; border: 1px solid #ddd; background: #fafafa; border-radius: 6px; overflow-wrap: anywhere; }
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
        .post { margin: 20px 0; padding: 20px; border: 1px solid #ddd; }
        .post-title { color: #333; }
        .post-meta { color: #666; font-size: 0.9em; }
        .post-excerpt { margin: 15px 0; }
        .pagination { display: flex; justify-content: center; gap: 12px; margin: 24px 0; }
        .pagination a { padding: 8px 12px; border: 1px solid #ddd; text-decoration: none; color: #333; border-radius: 4px; }
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
    <aside class="sidebar" aria-label="サイト内検索">
        <h2>記事検索</h2>
        <form class="search-form" action="/search" method="get">
            <input type="search" name="s" placeholder="検索語を入力" aria-label="検索語">
            <button type="submit">検索</button>
        </form>
        <div class="search-inline-results" aria-live="polite"></div>
    </aside>
    </div>
    <footer>
        <p>&copy; ]] .. current_year .. [[ LuaAIDiary. All rights reserved.</p>
    </footer>
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
