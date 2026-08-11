-- WP_Queryクラスのエミュレーション
-- WordPressのクエリとループコンテキストを管理

local _M = {}

local function trim(value)
    if not value then
        return ""
    end

    return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

-- グローバルクエリ
_M.global_query = nil
_M.current_query = nil

-- WP_Queryクラスのコンストラクタ
function _M:new(args)
    local instance = {
        posts = {},
        post_count = 0,
        current_post = -1,
        in_the_loop = false,
        query_vars = args or {},
        found_posts = 0,
        max_num_pages = 0,
        query_error = nil,
    }
    
    setmetatable(instance, {__index = self})
    
    -- クエリを実行
    instance:query(args)
    
    return instance
end

-- クエリを実行
function _M:query(args)
    args = args or {}
    
    local Post = require "models.post"
    local conditions = {}
    local order_by = "published_at DESC"
    local limit = args.posts_per_page or 10
    local offset = ((args.paged or 1) - 1) * limit
    
    -- 投稿タイプ（将来の拡張用にコメントアウト）
    -- if args.post_type then
    --     conditions.post_type = args.post_type
    -- end
    
    -- 投稿ステータス
    if args.post_status then
        conditions.status = args.post_status
    else
        conditions.status = "published"
    end
    
    -- 投稿ID
    if args.p then
        conditions.id = args.p
    end
    
    -- スラッグ
    if args.name then
        conditions.slug = args.name
    end
    
    -- カテゴリー
    if args.category_name then
        -- カテゴリーでフィルタリング（後で実装）
    end
    
    -- タグ
    if args.tag then
        -- タグでフィルタリング（後で実装）
    end
    
    -- 著者
    if args.author then
        conditions.author_id = args.author
    end
    
    -- 並び順
    if args.orderby then
        local order = args.order or "DESC"
        order_by = args.orderby .. " " .. order
    end
    
    -- 投稿を取得
    if args.s ~= nil then
        -- 検索結果
        local keyword = trim(args.s)
        if keyword == "" then
            self.posts = {}
            self.post_count = 0
            self.found_posts = 0
            self.max_num_pages = 0
        else
            local published_only = conditions.status == "published"
            local options = {
                limit = limit,
                offset = offset,
                order_by = order_by,
                published_only = published_only
            }

            local posts, search_err = Post.search(keyword, options)
            if search_err then
                self.query_error = search_err
                self.posts = {}
                self.post_count = 0
                self.found_posts = 0
                self.max_num_pages = 0
                return self.posts, search_err
            end

            self.posts = posts or {}
            self.post_count = #self.posts

            local count, count_err = Post.count_search(keyword, published_only)
            if count_err then
                self.query_error = count_err
                self.found_posts = 0
                self.max_num_pages = 0
                return self.posts, count_err
            end

            self.found_posts = count or 0
            self.max_num_pages = math.ceil(self.found_posts / limit)
        end
    elseif args.p or args.name then
        -- 単一投稿
        local post
        if args.p then
            post = Post:find(args.p)
        elseif args.name then
            post = Post.find_by_slug(args.name)
        end
        
        if post then
            self.posts = {post}
            self.post_count = 1
            self.found_posts = 1
        else
            self.posts = {}
            self.post_count = 0
            self.found_posts = 0
        end
    else
        -- 複数投稿
        local options = {
            limit = limit,
            offset = offset,
            order_by = order_by
        }
        
        -- ステータスによって取得方法を変える
        if conditions.status == "published" then
            self.posts = Post.find_published(options) or {}
        else
            -- 条件付き検索にはfind_byを使用
            self.posts = Post:find_by(conditions, options) or {}
        end
        
        -- 診断ログ: 取得した投稿数を確認
        ngx.log(ngx.ERR, "[DIAGNOSIS] wp_query:query: Post.find_published 実行完了")
        ngx.log(ngx.ERR, "[DIAGNOSIS] 取得した投稿配列サイズ: ", #self.posts)
        if #self.posts > 0 then
            ngx.log(ngx.ERR, "[DIAGNOSIS] 最初の投稿: title=", self.posts[1].title or "nil", ", id=", self.posts[1].id or "nil")
        end
        
        self.post_count = #self.posts
        ngx.log(ngx.ERR, "[DIAGNOSIS] self.post_count 設定: ", self.post_count)
        
        -- 総投稿数を取得（ページネーション用）
        local count, err = Post:count(conditions)
        self.found_posts = count or 0
        self.max_num_pages = math.ceil(self.found_posts / limit)
    end
    
    return self.posts
end

-- 投稿があるか確認
function _M:have_posts()
    return self.current_post < self.post_count - 1
end

-- 次の投稿へ
function _M:the_post()
    self.current_post = self.current_post + 1
    self.in_the_loop = true
    
    -- WordPress関数に現在の投稿を設定
    local wp = require "theme_engine.wp_functions"
    wp.set_current_post(self.posts[self.current_post + 1])
    
    return self.posts[self.current_post + 1]
end

-- ループをリセット
function _M:rewind_posts()
    self.current_post = -1
    self.in_the_loop = false
end

-- グローバルクエリを設定
function _M.set_global_query(query)
    _M.global_query = query
    _M.current_query = query
end

-- グローバルクエリを取得
function _M.get_global_query()
    return _M.global_query
end

-- 現在のクエリを取得
function _M.get_current_query()
    return _M.current_query or _M.global_query
end

-- メインクエリかどうか
function _M:is_main_query()
    return self == _M.global_query
end

-- クエリ変数を取得
function _M:get(var)
    return self.query_vars[var]
end

-- クエリ変数を設定
function _M:set(var, value)
    self.query_vars[var] = value
end

-- 便利関数: グローバルクエリで投稿があるか
function _M.have_posts_global()
    local query = _M.get_current_query()
    if query then
        return query:have_posts()
    end
    return false
end

-- 便利関数: グローバルクエリで次の投稿へ
function _M.the_post_global()
    local query = _M.get_current_query()
    if query then
        return query:the_post()
    end
    return nil
end

return _M
