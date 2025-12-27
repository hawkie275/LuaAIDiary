-- app/controllers/category_controller.lua
-- カテゴリーコントローラー - カテゴリー関連のHTTPエンドポイント

local cjson = require("cjson")
local Category = require("models.category")
local Session = require("utils.session")
local validator = require("utils.validator")

local CategoryController = {}

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

-- カテゴリーデータのバリデーション
-- @param data リクエストデータ
-- @param is_update 更新時かどうか
-- @return 成功フラグ、エラー情報
local function validate_category_data(data, is_update)
    local errors = {}
    
    -- 名前の検証（新規作成時は必須）
    if not is_update or data.name then
        if not data.name or data.name == "" then
            if not is_update then
                errors.name = "カテゴリー名は必須です"
            end
        else
            local ok, err = validator.validate_length(data.name, 1, 100)
            if not ok then
                errors.name = err
            end
        end
    end
    
    -- 説明の検証（オプション）
    if data.description and data.description ~= "" then
        local ok, err = validator.validate_length(data.description, 0, 500)
        if not ok then
            errors.description = err
        end
    end
    
    -- スラッグの検証（指定されている場合）
    if data.slug and data.slug ~= "" then
        local slug_util = require("utils.slug")
        local ok, err = slug_util.is_valid_slug(data.slug)
        if not ok then
            errors.slug = err
        end
    end
    
    -- 親カテゴリーIDの検証（オプション）
    if data.parent_id then
        local ok, num = validator.validate_positive_integer(data.parent_id)
        if not ok then
            errors.parent_id = "無効な親カテゴリーIDです"
        else
            -- 親カテゴリーの存在確認
            local parent_exists = Category:exists(num)
            if not parent_exists then
                errors.parent_id = "指定された親カテゴリーが存在しません"
            end
        end
    end
    
    -- エラーがあれば返す
    if next(errors) then
        return false, errors
    end
    
    return true, nil
end

-- カテゴリー一覧取得エンドポイント
-- GET /api/categories
function CategoryController.index()
    -- クエリパラメータを取得
    local args = ngx.req.get_uri_args()
    local limit = tonumber(args.limit) or 100
    local offset = tonumber(args.offset) or 0
    
    local options = {
        limit = limit,
        offset = offset,
        order_by = "name ASC"
    }
    
    -- カテゴリー一覧を取得
    local categories, err = Category.get_all_categories(options)
    if not categories then
        ngx.log(ngx.ERR, "カテゴリー取得エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "カテゴリーの取得に失敗しました"
        }, 500)
    end
    
    -- 各カテゴリーに投稿数を追加
    for _, category in ipairs(categories) do
        local post_count, err = Category.count_posts(category.id, true)
        category.post_count = post_count or 0
    end
    
    return json_response({
        success = true,
        data = categories
    })
end

-- カテゴリー詳細取得エンドポイント
-- GET /api/categories/:id
function CategoryController.show(category_id)
    if not category_id then
        category_id = ngx.var.id
    end
    
    if not category_id then
        return json_response({
            success = false,
            message = "カテゴリーIDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(category_id)
    if not ok then
        return json_response({
            success = false,
            message = "無効なカテゴリーIDです"
        }, 400)
    end
    
    -- カテゴリーを取得
    local category, err = Category:find(num)
    if not category then
        return json_response({
            success = false,
            message = "カテゴリーが見つかりません"
        }, 404)
    end
    
    -- 投稿数を追加
    local post_count, err = Category.count_posts(category.id, true)
    category.post_count = post_count or 0
    
    return json_response({
        success = true,
        data = category
    })
end

-- カテゴリー作成エンドポイント
-- POST /api/categories
function CategoryController.create()
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            message = err or "認証が必要です"
        }, 401)
    end
    
    -- JSONボディを取得
    local data, err = get_json_body()
    if not data then
        return json_response({
            success = false,
            message = err or "無効なリクエスト"
        }, 400)
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = verify_csrf_token(session, data)
    if not csrf_valid then
        return json_response({
            success = false,
            message = csrf_err or "CSRF検証に失敗しました"
        }, 403)
    end
    
    -- バリデーション
    local ok, errors = validate_category_data(data, false)
    if not ok then
        return json_response({
            success = false,
            message = "バリデーションエラー",
            errors = errors
        }, 400)
    end
    
    -- 名前の重複チェック
    local existing, err = Category:find_by({name = data.name})
    if existing and #existing > 0 then
        return json_response({
            success = false,
            message = "同じ名前のカテゴリーが既に存在します"
        }, 409)
    end
    
    -- カテゴリーデータを準備
    local category_data = {
        name = data.name,
        description = data.description,
        slug = data.slug,
        parent_id = data.parent_id
    }
    
    -- カテゴリーを作成
    local category_id, err = Category.create_category(category_data)
    if not category_id then
        ngx.log(ngx.ERR, "カテゴリー作成エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "カテゴリーの作成に失敗しました"
        }, 500)
    end
    
    -- 作成されたカテゴリーを取得
    local category, err = Category:find(category_id)
    if not category then
        ngx.log(ngx.ERR, "カテゴリー取得エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = "カテゴリーは作成されましたが、取得に失敗しました"
        }, 500)
    end
    
    -- 投稿数を追加
    category.post_count = 0
    
    -- 成功レスポンス
    return json_response({
        success = true,
        data = category
    }, 201)
end

-- カテゴリー更新エンドポイント
-- PUT /api/categories/:id
function CategoryController.update(category_id)
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            message = err or "認証が必要です"
        }, 401)
    end
    
    if not category_id then
        category_id = ngx.var.id
    end
    
    if not category_id then
        return json_response({
            success = false,
            message = "カテゴリーIDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(category_id)
    if not ok then
        return json_response({
            success = false,
            message = "無効なカテゴリーIDです"
        }, 400)
    end
    
    -- カテゴリーの存在確認
    local category, err = Category:find(num)
    if not category then
        return json_response({
            success = false,
            message = "カテゴリーが見つかりません"
        }, 404)
    end
    
    -- JSONボディを取得
    local data, err = get_json_body()
    if not data then
        return json_response({
            success = false,
            message = err or "無効なリクエスト"
        }, 400)
    end
    
    -- CSRFトークン検証
    local csrf_valid, csrf_err = verify_csrf_token(session, data)
    if not csrf_valid then
        return json_response({
            success = false,
            message = csrf_err or "CSRF検証に失敗しました"
        }, 403)
    end
    
    -- バリデーション
    local ok, errors = validate_category_data(data, true)
    if not ok then
        return json_response({
            success = false,
            message = "バリデーションエラー",
            errors = errors
        }, 400)
    end
    
    -- 名前の重複チェック（名前が変更されている場合）
    if data.name and data.name ~= category.name then
        local existing, err = Category:find_by({name = data.name})
        if existing and #existing > 0 then
            return json_response({
                success = false,
                message = "同じ名前のカテゴリーが既に存在します"
            }, 409)
        end
    end
    
    -- カテゴリーを更新
    local update_data = {
        name = data.name,
        description = data.description,
        slug = data.slug,
        parent_id = data.parent_id
    }
    
    local ok, err = Category.update_category(num, update_data)
    if not ok then
        ngx.log(ngx.ERR, "カテゴリー更新エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "カテゴリーの更新に失敗しました"
        }, 500)
    end
    
    -- 更新されたカテゴリーを取得
    local updated_category, err = Category:find(num)
    if updated_category then
        local post_count, err = Category.count_posts(num, true)
        updated_category.post_count = post_count or 0
    end
    
    return json_response({
        success = true,
        data = updated_category
    })
end

-- カテゴリー削除エンドポイント
-- DELETE /api/categories/:id
function CategoryController.delete(category_id)
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            message = err or "認証が必要です"
        }, 401)
    end
    
    -- CSRFトークン検証（DELETEリクエストの場合はヘッダーのみから取得）
    local csrf_valid, csrf_err = verify_csrf_token(session, nil)
    if not csrf_valid then
        return json_response({
            success = false,
            message = csrf_err or "CSRF検証に失敗しました"
        }, 403)
    end
    
    if not category_id then
        category_id = ngx.var.id
    end
    
    if not category_id then
        return json_response({
            success = false,
            message = "カテゴリーIDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(category_id)
    if not ok then
        return json_response({
            success = false,
            message = "無効なカテゴリーIDです"
        }, 400)
    end
    
    -- カテゴリーの存在確認
    local category, err = Category:find(num)
    if not category then
        return json_response({
            success = false,
            message = "カテゴリーが見つかりません"
        }, 404)
    end
    
    -- カテゴリーを削除（子カテゴリーや投稿の関連がある場合はエラー）
    local ok, err = Category.delete_category(num, false)
    if not ok then
        ngx.log(ngx.WARN, "カテゴリー削除エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "カテゴリーの削除に失敗しました"
        }, 400)
    end
    
    return json_response({
        success = true,
        message = "カテゴリーを削除しました"
    })
end

return CategoryController
