-- app/controllers/post_controller.lua
-- 投稿コントローラー - 投稿関連のHTTPエンドポイント

local cjson = require("cjson")
local Post = require("models.post")
local Category = require("models.category")
local Tag = require("models.tag")
local Session = require("utils.session")
local validator = require("utils.validator")
local csrf = require("middleware.csrf")

local PostController = {}

-- JSONレスポンスを送信するヘルパー関数
local function json_response(data, status)
    ngx.status = status or 200
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(data))
    ngx.exit(ngx.OK)
end

-- リクエストボディからJSONを取得するヘルパー関数
local function get_json_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        return nil, "リクエストボディが空です"
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        return nil, "無効なJSON形式です"
    end
    
    return data
end

-- セッションから認証されたユーザーを取得
local function get_authenticated_user()
    local session = Session.new()
    local ok = session:start()
    
    if not ok or not session:is_authenticated() then
        return nil, nil, "認証が必要です"
    end
    
    local user_id = session:get_user_id()
    if not user_id then
        return nil, nil, "ユーザー情報の取得に失敗しました"
    end
    
    return user_id, session, nil
end

-- CSRFトークンを検証
-- @param session セッションオブジェクト
-- @param json_data JSONボディデータ（オプション）
-- @return 検証結果、エラーメッセージ
local function verify_csrf_token(session, json_data)
    if not session then
        return false, "セッションが無効です"
    end
    
    -- セッションからトークンを取得
    local session_token = session:get("csrf_token")
    if not session_token or session_token == "" then
        return false, "CSRFトークンがセッションに存在しません"
    end
    
    -- リクエストヘッダーからトークンを取得
    local headers = ngx.req.get_headers()
    local request_token = headers["x-csrf-token"] or headers["X-CSRF-Token"]
    
    -- ヘッダーになければJSONボディから取得
    if not request_token and json_data then
        request_token = json_data._csrf_token or json_data.csrf_token
    end
    
    if not request_token or request_token == "" then
        return false, "CSRFトークンが提供されていません"
    end
    
    -- トークンを比較
    if session_token ~= request_token then
        return false, "CSRFトークンが一致しません"
    end
    
    return true, nil
end

-- 投稿データのバリデーション
-- @param data リクエストデータ
-- @return 成功フラグ、エラー情報
local function validate_post_data(data)
    local errors = {}
    
    -- タイトルの検証
    if not data.title or data.title == "" then
        errors.title = "タイトルは必須です"
    else
        local ok, err = validator.validate_length(data.title, 1, 255)
        if not ok then
            errors.title = err
        end
    end
    
    -- 本文の検証
    if not data.content or data.content == "" then
        errors.content = "本文は必須です"
    end
    
    -- 抜粋の検証（オプション）
    if data.excerpt and data.excerpt ~= "" then
        local ok, err = validator.validate_length(data.excerpt, 0, 500)
        if not ok then
            errors.excerpt = err
        end
    end
    
    -- ステータスの検証
    if data.status then
        local valid_statuses = {"draft", "published", "trash"}
        local ok, err = validator.validate_enum(data.status, valid_statuses)
        if not ok then
            errors.status = "ステータスは draft, published, trash のいずれかである必要があります"
        end
    end
    
    -- category_idsの検証（オプション）
    if data.category_ids then
        if type(data.category_ids) ~= "table" then
            errors.category_ids = "カテゴリーIDは配列である必要があります"
        else
            for i, category_id in ipairs(data.category_ids) do
                local ok, num = validator.validate_positive_integer(category_id)
                if not ok then
                    errors.category_ids = string.format("無効なカテゴリーID: %s", tostring(category_id))
                    break
                end
                -- カテゴリーの存在確認
                local category_exists = Category:exists(num)
                if not category_exists then
                    errors.category_ids = string.format("カテゴリーID %d が存在しません", num)
                    break
                end
            end
        end
    end
    
    -- tag_idsの検証（オプション）
    if data.tag_ids then
        if type(data.tag_ids) ~= "table" then
            errors.tag_ids = "タグIDは配列である必要があります"
        else
            for i, tag_id in ipairs(data.tag_ids) do
                local ok, num = validator.validate_positive_integer(tag_id)
                if not ok then
                    errors.tag_ids = string.format("無効なタグID: %s", tostring(tag_id))
                    break
                end
                -- タグの存在確認
                local tag_exists = Tag:exists(num)
                if not tag_exists then
                    errors.tag_ids = string.format("タグID %d が存在しません", num)
                    break
                end
            end
        end
    end
    
    -- エラーがあれば返す
    if next(errors) then
        return false, errors
    end
    
    return true, nil
end

-- 投稿作成エンドポイント
-- POST /api/posts
function PostController.create()
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            error = err or "認証が必要です"
        }, 401)
    end
    
    -- JSONボディを取得
    local data, err = get_json_body()
    if not data then
        return json_response({
            success = false,
            error = err or "無効なリクエスト"
        }, 400)
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = verify_csrf_token(session, data)
    if not csrf_valid then
        return json_response({
            success = false,
            error = csrf_err or "CSRF検証に失敗しました"
        }, 403)
    end
    
    -- バリデーション
    local ok, errors = validate_post_data(data)
    if not ok then
        return json_response({
            success = false,
            error = "バリデーションエラー",
            errors = errors
        }, 400)
    end
    
    -- 投稿データを準備
    local post_data = {
        title = data.title,
        content = data.content,
        excerpt = data.excerpt or "",
        author_id = user_id,  -- 認証されたユーザーIDを使用
        status = data.status or "draft",
        categories = data.category_ids or {},
        tags = data.tag_ids or {}
    }
    
    -- スラッグが指定されている場合は使用
    if data.slug and data.slug ~= "" then
        post_data.slug = data.slug
    end
    
    -- 投稿を作成
    local post_id, err = Post.create_post(post_data)
    if not post_id then
        ngx.log(ngx.ERR, "投稿作成エラー: ", err or "unknown error")
        return json_response({
            success = false,
            error = err or "投稿の作成に失敗しました"
        }, 500)
    end
    
    -- 作成された投稿を取得
    local post, err = Post:find(post_id)
    if not post then
        ngx.log(ngx.ERR, "投稿取得エラー: ", err or "unknown error")
        return json_response({
            success = false,
            error = "投稿は作成されましたが、取得に失敗しました"
        }, 500)
    end
    
    -- カテゴリーとタグを含める
    post.categories = Post.get_categories(post_id) or {}
    post.tags = Post.get_tags(post_id) or {}
    
    -- user_id フィールドを追加（API仕様に合わせる）
    post.user_id = post.author_id
    
    -- 成功レスポンス
    return json_response({
        success = true,
        post = post
    }, 201)
end

-- 投稿一覧取得エンドポイント
-- GET /api/posts
function PostController.index()
    -- クエリパラメータを取得
    local args = ngx.req.get_uri_args()
    local limit = tonumber(args.limit) or 10
    local offset = tonumber(args.offset) or 0
    local status = args.status
    local category_id = args.category_id
    local tag_id = args.tag_id
    
    -- 認証チェック（オプション）
    local user_id, _ = get_authenticated_user()
    
    local options = {
        limit = limit,
        offset = offset,
        order_by = "created_at DESC"
    }
    
    -- 公開済みのみの場合は published_only フラグを設定
    if not user_id then
        options.published_only = true
    end
    
    local posts, err
    
    -- カテゴリーIDとタグIDの両方が指定された場合
    if category_id and tag_id then
        -- カテゴリーIDのバリデーション
        local ok, cat_num = validator.validate_positive_integer(category_id)
        if not ok then
            return json_response({
                success = false,
                error = "無効なカテゴリーIDです"
            }, 400)
        end
        
        -- タグIDのバリデーション
        ok, tag_num = validator.validate_positive_integer(tag_id)
        if not ok then
            return json_response({
                success = false,
                error = "無効なタグIDです"
            }, 400)
        end
        
        -- カテゴリーとタグの両方で絞り込み（AND条件）
        local cat_posts, cat_err = Post.find_by_category(cat_num, options)
        if not cat_posts then
            return json_response({
                success = false,
                error = cat_err or "投稿の取得に失敗しました"
            }, 500)
        end
        
        -- カテゴリーで絞り込んだ投稿からタグでさらに絞り込み
        posts = {}
        for _, post in ipairs(cat_posts) do
            for _, tag in ipairs(post.tags or {}) do
                if tonumber(tag.id) == tag_num then
                    table.insert(posts, post)
                    break
                end
            end
        end
        
    -- カテゴリーIDのみ指定された場合
    elseif category_id then
        -- カテゴリーIDのバリデーション
        local ok, cat_num = validator.validate_positive_integer(category_id)
        if not ok then
            return json_response({
                success = false,
                error = "無効なカテゴリーIDです"
            }, 400)
        end
        
        -- カテゴリーの存在確認
        if not Category:exists(cat_num) then
            return json_response({
                success = false,
                error = "カテゴリーが存在しません"
            }, 400)
        end
        
        posts, err = Post.find_by_category(cat_num, options)
        
    -- タグIDのみ指定された場合
    elseif tag_id then
        -- タグIDのバリデーション
        local ok, tag_num = validator.validate_positive_integer(tag_id)
        if not ok then
            return json_response({
                success = false,
                error = "無効なタグIDです"
            }, 400)
        end
        
        -- タグの存在確認
        if not Tag:exists(tag_num) then
            return json_response({
                success = false,
                error = "タグが存在しません"
            }, 400)
        end
        
        posts, err = Post.find_by_tag(tag_num, options)
        
    -- カテゴリーもタグも指定されていない場合
    else
        -- 認証されている場合は全ステータスの投稿を取得可能
        -- 未認証の場合は公開済み投稿のみ
        if user_id then
            if status then
                options.where = string.format("status = '%s'", status)
            end
            posts, err = Post:all(options)
        else
            -- 公開済み投稿のみ
            posts, err = Post.find_published(options)
        end
    end
    
    if not posts then
        return json_response({
            success = false,
            error = err or "投稿の取得に失敗しました"
        }, 500)
    end
    
    -- N+1問題を回避：一括取得を使用
    if #posts > 0 then
        -- 投稿IDのリストを作成
        local post_ids = {}
        for _, post in ipairs(posts) do
            table.insert(post_ids, post.id)
        end
        
        -- カテゴリーとタグを一括取得
        local categories_map = Post.get_categories_batch(post_ids)
        local tags_map = Post.get_tags_batch(post_ids)
        
        -- 各投稿にカテゴリーとタグを追加
        for _, post in ipairs(posts) do
            local post_id_str = tostring(post.id)
            post.categories = categories_map[post_id_str] or {}
            post.tags = tags_map[post_id_str] or {}
            post.user_id = post.author_id
        end
    end
    
    return json_response({
        success = true,
        posts = posts,
        pagination = {
            limit = limit,
            offset = offset,
            total = #posts
        }
    })
end

-- 投稿詳細取得エンドポイント
-- GET /api/posts/:id
function PostController.show(post_id)
    if not post_id then
        post_id = ngx.var.id
    end
    
    if not post_id then
        return json_response({
            success = false,
            error = "投稿IDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(post_id)
    if not ok then
        return json_response({
            success = false,
            error = "無効な投稿IDです"
        }, 400)
    end
    
    -- 投稿を取得
    local post, err = Post:find(num)
    if not post then
        return json_response({
            success = false,
            error = "投稿が見つかりません"
        }, 404)
    end
    
    -- 認証チェック（下書きや非公開投稿の場合）
    if post.status ~= "published" then
        local user_id, _ = get_authenticated_user()
        if not user_id or user_id ~= post.author_id then
            return json_response({
                success = false,
                error = "この投稿にアクセスする権限がありません"
            }, 403)
        end
    end
    
    -- カテゴリーとタグを含める
    post.categories = Post.get_categories(post.id) or {}
    post.tags = Post.get_tags(post.id) or {}
    post.user_id = post.author_id
    
    return json_response({
        success = true,
        post = post
    })
end

-- 投稿更新エンドポイント
-- PUT /api/posts/:id
function PostController.update(post_id)
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            error = err or "認証が必要です"
        }, 401)
    end
    
    if not post_id then
        post_id = ngx.var.id
    end
    
    if not post_id then
        return json_response({
            success = false,
            error = "投稿IDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(post_id)
    if not ok then
        return json_response({
            success = false,
            error = "無効な投稿IDです"
        }, 400)
    end
    
    -- 投稿の存在確認と権限チェック
    local post, err = Post:find(num)
    if not post then
        return json_response({
            success = false,
            error = "投稿が見つかりません"
        }, 404)
    end
    
    if post.author_id ~= user_id then
        return json_response({
            success = false,
            error = "この投稿を更新する権限がありません"
        }, 403)
    end
    
    -- JSONボディを取得
    local data, err = get_json_body()
    if not data then
        return json_response({
            success = false,
            error = err or "無効なリクエスト"
        }, 400)
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = verify_csrf_token(session, data)
    if not csrf_valid then
        return json_response({
            success = false,
            error = csrf_err or "CSRF検証に失敗しました"
        }, 403)
    end
    
    -- バリデーション（更新時は一部のフィールドのみチェック）
    local errors = {}
    
    if data.title then
        local ok, err = validator.validate_length(data.title, 1, 255)
        if not ok then
            errors.title = err
        end
    end
    
    if data.excerpt then
        local ok, err = validator.validate_length(data.excerpt, 0, 500)
        if not ok then
            errors.excerpt = err
        end
    end
    
    if data.status then
        local valid_statuses = {"draft", "published", "trash"}
        local ok, err = validator.validate_enum(data.status, valid_statuses)
        if not ok then
            errors.status = "ステータスは draft, published, trash のいずれかである必要があります"
        end
    end
    
    if next(errors) then
        return json_response({
            success = false,
            error = "バリデーションエラー",
            errors = errors
        }, 400)
    end
    
    -- 投稿を更新
    local update_data = {
        title = data.title,
        content = data.content,
        excerpt = data.excerpt,
        status = data.status,
        slug = data.slug,
        categories = data.category_ids,
        tags = data.tag_ids
    }
    
    local ok, err = Post.update_post(num, update_data)
    if not ok then
        return json_response({
            success = false,
            error = err or "投稿の更新に失敗しました"
        }, 500)
    end
    
    -- 更新された投稿を取得
    local updated_post, err = Post:find(num)
    if updated_post then
        updated_post.categories = Post.get_categories(num) or {}
        updated_post.tags = Post.get_tags(num) or {}
        updated_post.user_id = updated_post.author_id
    end
    
    return json_response({
        success = true,
        post = updated_post
    })
end

-- 投稿削除エンドポイント
-- DELETE /api/posts/:id
function PostController.delete(post_id)
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            error = err or "認証が必要です"
        }, 401)
    end
    
    -- CSRFトークン検証（DELETEリクエストの場合はヘッダーのみから取得）
    local csrf_valid, csrf_err = verify_csrf_token(session, nil)
    if not csrf_valid then
        return json_response({
            success = false,
            error = csrf_err or "CSRF検証に失敗しました"
        }, 403)
    end
    
    if not post_id then
        post_id = ngx.var.id
    end
    
    if not post_id then
        return json_response({
            success = false,
            error = "投稿IDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(post_id)
    if not ok then
        return json_response({
            success = false,
            error = "無効な投稿IDです"
        }, 400)
    end
    
    -- 投稿の存在確認と権限チェック
    local post, err = Post:find(num)
    if not post then
        return json_response({
            success = false,
            error = "投稿が見つかりません"
        }, 404)
    end
    
    if post.author_id ~= user_id then
        return json_response({
            success = false,
            error = "この投稿を削除する権限がありません"
        }, 403)
    end
    
    -- 投稿を削除
    local ok, err = Post:delete(num)
    if not ok then
        return json_response({
            success = false,
            error = err or "投稿の削除に失敗しました"
        }, 500)
    end
    
    return json_response({
        success = true,
        message = "投稿を削除しました"
    })
end

return PostController
