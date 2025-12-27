-- app/controllers/tag_controller.lua
-- タグコントローラー - タグ関連のHTTPエンドポイント

local cjson = require("cjson")
local Tag = require("models.tag")
local Session = require("utils.session")
local validator = require("utils.validator")

local TagController = {}

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

-- タグデータのバリデーション
-- @param data リクエストデータ
-- @param is_update 更新時かどうか
-- @return 成功フラグ、エラー情報
local function validate_tag_data(data, is_update)
    local errors = {}
    
    -- 名前の検証（新規作成時は必須）
    if not is_update or data.name then
        if not data.name or data.name == "" then
            if not is_update then
                errors.name = "タグ名は必須です"
            end
        else
            local ok, err = validator.validate_length(data.name, 1, 50)
            if not ok then
                errors.name = err
            end
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
    
    -- エラーがあれば返す
    if next(errors) then
        return false, errors
    end
    
    return true, nil
end

-- タグ一覧取得エンドポイント
-- GET /api/tags
function TagController.index()
    -- クエリパラメータを取得
    local args = ngx.req.get_uri_args()
    local limit = tonumber(args.limit) or 100
    local offset = tonumber(args.offset) or 0
    
    local options = {
        limit = limit,
        offset = offset,
        order_by = "name ASC"
    }
    
    -- タグ一覧を取得
    local tags, err = Tag.get_all_tags(options)
    if not tags then
        ngx.log(ngx.ERR, "タグ取得エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "タグの取得に失敗しました"
        }, 500)
    end
    
    -- 各タグに投稿数を追加
    for _, tag in ipairs(tags) do
        local post_count, err = Tag.count_posts(tag.id, true)
        tag.post_count = post_count or 0
    end
    
    return json_response({
        success = true,
        data = tags
    })
end

-- タグ詳細取得エンドポイント
-- GET /api/tags/:id
function TagController.show(tag_id)
    if not tag_id then
        tag_id = ngx.var.id
    end
    
    if not tag_id then
        return json_response({
            success = false,
            message = "タグIDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(tag_id)
    if not ok then
        return json_response({
            success = false,
            message = "無効なタグIDです"
        }, 400)
    end
    
    -- タグを取得
    local tag, err = Tag:find(num)
    if not tag then
        return json_response({
            success = false,
            message = "タグが見つかりません"
        }, 404)
    end
    
    -- 投稿数を追加
    local post_count, err = Tag.count_posts(tag.id, true)
    tag.post_count = post_count or 0
    
    return json_response({
        success = true,
        data = tag
    })
end

-- タグ作成エンドポイント
-- POST /api/tags
function TagController.create()
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
    local ok, errors = validate_tag_data(data, false)
    if not ok then
        return json_response({
            success = false,
            message = "バリデーションエラー",
            errors = errors
        }, 400)
    end
    
    -- 名前の重複チェック
    local existing, err = Tag:find_by({name = data.name})
    if existing and #existing > 0 then
        return json_response({
            success = false,
            message = "同じ名前のタグが既に存在します"
        }, 409)
    end
    
    -- タグデータを準備
    local tag_data = {
        name = data.name,
        slug = data.slug
    }
    
    -- タグを作成
    local tag_id, err = Tag.create_tag(tag_data)
    if not tag_id then
        ngx.log(ngx.ERR, "タグ作成エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "タグの作成に失敗しました"
        }, 500)
    end
    
    -- 作成されたタグを取得
    local tag, err = Tag:find(tag_id)
    if not tag then
        ngx.log(ngx.ERR, "タグ取得エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = "タグは作成されましたが、取得に失敗しました"
        }, 500)
    end
    
    -- 投稿数を追加
    tag.post_count = 0
    
    -- 成功レスポンス
    return json_response({
        success = true,
        data = tag
    }, 201)
end

-- タグ更新エンドポイント
-- PUT /api/tags/:id
function TagController.update(tag_id)
    -- 認証チェック
    local user_id, session, err = get_authenticated_user()
    if not user_id then
        return json_response({
            success = false,
            message = err or "認証が必要です"
        }, 401)
    end
    
    if not tag_id then
        tag_id = ngx.var.id
    end
    
    if not tag_id then
        return json_response({
            success = false,
            message = "タグIDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(tag_id)
    if not ok then
        return json_response({
            success = false,
            message = "無効なタグIDです"
        }, 400)
    end
    
    -- タグの存在確認
    local tag, err = Tag:find(num)
    if not tag then
        return json_response({
            success = false,
            message = "タグが見つかりません"
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
    local ok, errors = validate_tag_data(data, true)
    if not ok then
        return json_response({
            success = false,
            message = "バリデーションエラー",
            errors = errors
        }, 400)
    end
    
    -- 名前の重複チェック（名前が変更されている場合）
    if data.name and data.name ~= tag.name then
        local existing, err = Tag:find_by({name = data.name})
        if existing and #existing > 0 then
            return json_response({
                success = false,
                message = "同じ名前のタグが既に存在します"
            }, 409)
        end
    end
    
    -- タグを更新
    local update_data = {
        name = data.name,
        slug = data.slug
    }
    
    local ok, err = Tag.update_tag(num, update_data)
    if not ok then
        ngx.log(ngx.ERR, "タグ更新エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "タグの更新に失敗しました"
        }, 500)
    end
    
    -- 更新されたタグを取得
    local updated_tag, err = Tag:find(num)
    if updated_tag then
        local post_count, err = Tag.count_posts(num, true)
        updated_tag.post_count = post_count or 0
    end
    
    return json_response({
        success = true,
        data = updated_tag
    })
end

-- タグ削除エンドポイント
-- DELETE /api/tags/:id
function TagController.delete(tag_id)
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
    
    if not tag_id then
        tag_id = ngx.var.id
    end
    
    if not tag_id then
        return json_response({
            success = false,
            message = "タグIDが指定されていません"
        }, 400)
    end
    
    -- IDの検証
    local ok, num = validator.validate_positive_integer(tag_id)
    if not ok then
        return json_response({
            success = false,
            message = "無効なタグIDです"
        }, 400)
    end
    
    -- タグの存在確認
    local tag, err = Tag:find(num)
    if not tag then
        return json_response({
            success = false,
            message = "タグが見つかりません"
        }, 404)
    end
    
    -- タグを削除（投稿との関連は削除される）
    local ok, err = Tag.delete_tag(num, true)
    if not ok then
        ngx.log(ngx.WARN, "タグ削除エラー: ", err or "unknown error")
        return json_response({
            success = false,
            message = err or "タグの削除に失敗しました"
        }, 400)
    end
    
    return json_response({
        success = true,
        message = "タグを削除しました"
    })
end

return TagController
