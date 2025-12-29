local GeminiService = require("services.gemini_service")
local UserSettings = require("models.user_settings")
local Session = require("utils.session")

local GeminiController = {}

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
    
    local user = session:get_user()
    if not user then
        return nil, nil, "ユーザー情報の取得に失敗しました"
    end
    
    return user, session, nil
end

-- ユーザー設定からAI設定を取得
local function get_ai_preferences(user_id)
    local preferences, err = UserSettings.get_preferences(user_id)
    if not preferences then
        return nil, err or "ユーザー設定の取得に失敗しました"
    end
    
    local ai_preferences = preferences.ai_preferences
    
    if not ai_preferences then
        return nil, "AI設定が見つかりません"
    end
    
    return ai_preferences
end

-- APIキーを取得（復号化）
local function get_decrypted_api_key(user_id)
    local api_key, err = UserSettings.get_gemini_api_key(user_id)
    if not api_key then
        return nil, err or "Gemini APIキーの取得に失敗しました"
    end
    
    return api_key
end

-- 記事生成エンドポイント
function GeminiController.generate_article(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { json = { success = false, error = err or "認証が必要です" }, status = 401 }
    end
    
    -- CSRFトークンの検証
    local csrf_token = ngx.var.http_x_csrf_token
    if not csrf_token or csrf_token ~= session:get("csrf_token") then
        return { json = { success = false, error = "CSRFトークンが無効です" }, status = 403 }
    end
    
    -- リクエストボディをパース
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body or body == "" then
        return { json = { success = false, error = "リクエストボディが空です" }, status = 400 }
    end
    
    local cjson_decode = require("cjson.safe").decode
    local params = cjson_decode(body)
    if not params then
        return { json = { success = false, error = "JSONのパースに失敗しました" }, status = 400 }
    end
    
    -- リクエストパラメータの検証
    local topic = params.topic
    if not topic or topic == "" then
        return { json = { success = false, error = "テーマが指定されていません" }, status = 400 }
    end
    
    -- AI設定を取得
    local ai_preferences, err = get_ai_preferences(user.id)
    if not ai_preferences then
        return { json = { success = false, error = err }, status = 400 }
    end
    
    -- APIキーを取得
    local api_key, err = get_decrypted_api_key(user.id)
    if not api_key then
        return { json = { success = false, error = err }, status = 400 }
    end
    
    -- プロンプトテンプレートを取得
    local prompt_template = ai_preferences.generate_article_prompt
    if not prompt_template then
        return { json = { success = false, error = "記事生成用のプロンプトが設定されていません" }, status = 400 }
    end
    
    -- パラメータを準備
    local request_params = {
        api_key = api_key,
        prompt_template = prompt_template,
        topic = topic,
        keywords = params.keywords or "",
        target_audience = params.target_audience or ai_preferences.default_target_audience,
        word_count = tonumber(params.word_count) or 2000,
        tone = params.tone or ai_preferences.default_tone,
        model = ai_preferences.model  -- ユーザー設定からモデル名を取得
    }
    
    -- Gemini APIを呼び出し
    local result, err = GeminiService.generate_article(request_params)
    if not result then
        ngx.log(ngx.ERR, "記事生成エラー: " .. (err or "不明なエラー"))
        return { json = { success = false, error = err or "記事生成に失敗しました" }, status = 500 }
    end
    
    return { json = { success = true, data = result } }
end

-- 校正エンドポイント
function GeminiController.proofread(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { json = { success = false, error = err or "認証が必要です" }, status = 401 }
    end
    
    -- CSRFトークンの検証
    local csrf_token = ngx.var.http_x_csrf_token
    if not csrf_token or csrf_token ~= session:get("csrf_token") then
        return { json = { success = false, error = "CSRFトークンが無効です" }, status = 403 }
    end
    
    -- リクエストボディをパース
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body or body == "" then
        return { json = { success = false, error = "リクエストボディが空です" }, status = 400 }
    end
    
    local cjson_decode = require("cjson.safe").decode
    local params = cjson_decode(body)
    if not params then
        return { json = { success = false, error = "JSONのパースに失敗しました" }, status = 400 }
    end
    
    -- リクエストパラメータの検証
    local content = params.content
    if not content or content == "" then
        return { json = { success = false, error = "校正する本文が指定されていません" }, status = 400 }
    end
    
    -- AI設定を取得
    local ai_preferences, err = get_ai_preferences(user.id)
    if not ai_preferences then
        return { json = { success = false, error = err }, status = 400 }
    end
    
    -- APIキーを取得
    local api_key, err = get_decrypted_api_key(user.id)
    if not api_key then
        return { json = { success = false, error = err }, status = 400 }
    end
    
    -- プロンプトテンプレートを取得
    local prompt_template = ai_preferences.proofread_prompt
    if not prompt_template then
        return { json = { success = false, error = "校正用のプロンプトが設定されていません" }, status = 400 }
    end
    
    -- オプションを準備
    local options = {
        api_key = api_key,
        prompt_template = prompt_template,
        tone = params.tone or ai_preferences.default_tone,
        model = ai_preferences.model  -- ユーザー設定からモデル名を取得
    }
    
    -- Gemini APIを呼び出し
    local result, err = GeminiService.proofread(content, options)
    if not result then
        ngx.log(ngx.ERR, "校正エラー: " .. (err or "不明なエラー"))
        return { json = { success = false, error = err or "校正に失敗しました" }, status = 500 }
    end
    
    -- 元のコンテンツを結果に追加
    result.original = content
    
    return { json = result }
end

-- API接続テストエンドポイント
function GeminiController.test_connection(self)
    -- 認証チェック
    local user, session, err = get_authenticated_user()
    if not user then
        return { json = { success = false, error = err or "認証が必要です" }, status = 401 }
    end
    
    -- CSRFトークンの検証
    local csrf_token = ngx.var.http_x_csrf_token
    if not csrf_token or csrf_token ~= session:get("csrf_token") then
        return { json = { success = false, error = "CSRFトークンが無効です" }, status = 403 }
    end
    
    -- リクエストボディをパース
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local params = {}
    if body and body ~= "" then
        local cjson_decode = require("cjson.safe").decode
        params = cjson_decode(body) or {}
    end
    
    -- リクエストパラメータからAPIキーを取得（テスト用）
    local api_key = params.api_key
    
    -- パラメータにAPIキーがない場合は保存済みのものを使用
    if not api_key or api_key == "" then
        local err
        api_key, err = get_decrypted_api_key(user.id)
        if not api_key then
            return { json = { success = false, error = err }, status = 400 }
        end
    end
    
    -- AI設定からモデル名を取得
    local ai_preferences, err = get_ai_preferences(user.id)
    local model = nil
    if ai_preferences and ai_preferences.model then
        model = ai_preferences.model
    end
    
    -- Gemini APIを呼び出し
    local result, err = GeminiService.test_connection(api_key, model)
    if not result then
        ngx.log(ngx.ERR, "API接続テストエラー: " .. (err or "不明なエラー"))
        return { json = { success = false, error = err or "API接続テストに失敗しました" }, status = 500 }
    end
    
    return { json = { success = true, data = result } }
end

return GeminiController
