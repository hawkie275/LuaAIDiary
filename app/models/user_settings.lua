-- ユーザー設定モデル
-- ユーザー個別の設定管理、Gemini APIキーの暗号化保存を提供します

local Base = require("models.base")
local crypto = require("utils.crypto")
local validator = require("utils.validator")
local cjson = require("cjson")

local _M = Base.new("user_settings")

-- ========================================
-- 設定の取得
-- ========================================

-- ユーザーの設定を取得
-- @param user_id ユーザーID
-- @return 設定情報、エラー
function _M.get_settings(user_id)
    if not user_id then
        return nil, "ユーザーIDが指定されていません"
    end
    
    local settings, err = _M:find_by({user_id = user_id})
    if not settings then
        return nil, err
    end
    
    if #settings == 0 then
        -- 設定が存在しない場合はデフォルト値を返す
        return _M.get_default_settings(), nil
    end
    
    return settings[1], nil
end

-- デフォルト設定を取得
-- @return デフォルト設定
function _M.get_default_settings()
    return {
        gemini_api_key = nil,
        gemini_model = "gemini-1.5-pro",
        preferences = {}
    }
end

-- ========================================
-- Gemini APIキー管理
-- ========================================

-- Gemini APIキーを取得（復号化）
-- @param user_id ユーザーID
-- @return APIキー、エラー
function _M.get_gemini_api_key(user_id)
    if not user_id then
        return nil, "ユーザーIDが指定されていません"
    end
    
    local settings, err = _M.get_settings(user_id)
    if not settings then
        return nil, err
    end
    
    if not settings.gemini_api_key or settings.gemini_api_key == "" then
        return nil, "Gemini APIキーが設定されていません"
    end
    
    -- 暗号化されたAPIキーを復号化
    local api_key, err = crypto.decrypt_api_key(settings.gemini_api_key)
    if not api_key then
        return nil, err or "APIキーの復号化に失敗しました"
    end
    
    return api_key, nil
end

-- Gemini APIキーを設定（暗号化）
-- @param user_id ユーザーID
-- @param api_key APIキー（平文）
-- @return 成功フラグ、エラー
function _M.set_gemini_api_key(user_id, api_key)
    if not user_id then
        return false, "ユーザーIDが指定されていません"
    end
    
    if not api_key or api_key == "" then
        return false, "APIキーが空です"
    end
    
    -- APIキーを暗号化
    local encrypted_key, err = crypto.encrypt_api_key(api_key)
    if not encrypted_key then
        return false, err or "APIキーの暗号化に失敗しました"
    end
    
    -- 設定を更新または作成
    local settings, err = _M.get_settings(user_id)
    
    if settings and settings.id then
        -- 既存設定を更新
        return _M:update(settings.id, {
            gemini_api_key = encrypted_key
        })
    else
        -- 新規設定を作成
        local settings_id, err = _M:create({
            user_id = user_id,
            gemini_api_key = encrypted_key,
            gemini_model = "gemini-1.5-pro"
        })
        return settings_id ~= nil, err
    end
end

-- Gemini APIキーを削除
-- @param user_id ユーザーID
-- @return 成功フラグ、エラー
function _M.delete_gemini_api_key(user_id)
    if not user_id then
        return false, "ユーザーIDが指定されていません"
    end
    
    local settings, err = _M.get_settings(user_id)
    if not settings or not settings.id then
        return true, nil  -- 設定が存在しない場合は成功とみなす
    end
    
    return _M:update(settings.id, {
        gemini_api_key = nil
    })
end

-- ========================================
-- Geminiモデル設定
-- ========================================

-- Geminiモデルを取得
-- @param user_id ユーザーID
-- @return モデル名、エラー
function _M.get_gemini_model(user_id)
    if not user_id then
        return nil, "ユーザーIDが指定されていません"
    end
    
    local settings, err = _M.get_settings(user_id)
    if not settings then
        return nil, err
    end
    
    return settings.gemini_model or "gemini-1.5-pro", nil
end

-- Geminiモデルを設定
-- @param user_id ユーザーID
-- @param model モデル名
-- @return 成功フラグ、エラー
function _M.set_gemini_model(user_id, model)
    if not user_id then
        return false, "ユーザーIDが指定されていません"
    end
    
    if not model or model == "" then
        return false, "モデル名が空です"
    end
    
    -- モデルのバリデーション
    local valid_models = {
        "gemini-1.5-pro",
        "gemini-1.5-flash",
        "gemini-pro",
        "gemini-pro-vision"
    }
    
    local ok, err = validator.validate_enum(model, valid_models)
    if not ok then
        return false, "無効なモデル名です"
    end
    
    -- 設定を更新または作成
    local settings, err = _M.get_settings(user_id)
    
    if settings and settings.id then
        return _M:update(settings.id, {gemini_model = model})
    else
        local settings_id, err = _M:create({
            user_id = user_id,
            gemini_model = model
        })
        return settings_id ~= nil, err
    end
end

-- ========================================
-- プリファレンス管理（JSON）
-- ========================================

-- プリファレンスを取得
-- @param user_id ユーザーID
-- @return プリファレンス、エラー
function _M.get_preferences(user_id)
    if not user_id then
        return nil, "ユーザーIDが指定されていません"
    end
    
    local settings, err = _M.get_settings(user_id)
    if not settings then
        return nil, err
    end
    
    if not settings.preferences or settings.preferences == "" then
        return {}, nil
    end
    
    -- JSON文字列の場合はデコード
    if type(settings.preferences) == "string" then
        local ok, preferences = pcall(cjson.decode, settings.preferences)
        if ok then
            return preferences, nil
        else
            return {}, nil
        end
    end
    
    return settings.preferences or {}, nil
end

-- プリファレンスを設定
-- @param user_id ユーザーID
-- @param preferences プリファレンステーブル
-- @return 成功フラグ、エラー
function _M.set_preferences(user_id, preferences)
    if not user_id then
        return false, "ユーザーIDが指定されていません"
    end
    
    if not preferences or type(preferences) ~= "table" then
        return false, "プリファレンスが無効です"
    end
    
    -- JSONエンコード
    local ok, json_str = pcall(cjson.encode, preferences)
    if not ok then
        return false, "プリファレンスのエンコードに失敗しました"
    end
    
    -- 設定を更新または作成
    local settings, err = _M.get_settings(user_id)
    
    if settings and settings.id then
        return _M:update(settings.id, {preferences = json_str})
    else
        local settings_id, err = _M:create({
            user_id = user_id,
            preferences = json_str
        })
        return settings_id ~= nil, err
    end
end

-- 特定のプリファレンス値を取得
-- @param user_id ユーザーID
-- @param key キー
-- @return 値、エラー
function _M.get_preference(user_id, key)
    if not key then
        return nil, "キーが指定されていません"
    end
    
    local preferences, err = _M.get_preferences(user_id)
    if not preferences then
        return nil, err
    end
    
    return preferences[key], nil
end

-- 特定のプリファレンス値を設定
-- @param user_id ユーザーID
-- @param key キー
-- @param value 値
-- @return 成功フラグ、エラー
function _M.set_preference(user_id, key, value)
    if not key then
        return false, "キーが指定されていません"
    end
    
    local preferences, err = _M.get_preferences(user_id)
    if not preferences then
        preferences = {}
    end
    
    preferences[key] = value
    
    return _M.set_preferences(user_id, preferences)
end

-- ========================================
-- 汎用設定管理
-- ========================================

-- 設定値を取得（汎用）
-- @param user_id ユーザーID
-- @param key キー（gemini_api_key, gemini_model, または preferences内のキー）
-- @return 値、エラー
function _M.get_setting(user_id, key)
    if not user_id or not key then
        return nil, "ユーザーIDまたはキーが指定されていません"
    end
    
    local settings, err = _M.get_settings(user_id)
    if not settings then
        return nil, err
    end
    
    -- 直接フィールドをチェック
    if key == "gemini_api_key" then
        return _M.get_gemini_api_key(user_id)
    elseif key == "gemini_model" then
        return _M.get_gemini_model(user_id)
    else
        -- プリファレンス内を検索
        return _M.get_preference(user_id, key)
    end
end

-- 設定値を保存（汎用）
-- @param user_id ユーザーID
-- @param key キー
-- @param value 値
-- @return 成功フラグ、エラー
function _M.set_setting(user_id, key, value)
    if not user_id or not key then
        return false, "ユーザーIDまたはキーが指定されていません"
    end
    
    -- 直接フィールドをチェック
    if key == "gemini_api_key" then
        return _M.set_gemini_api_key(user_id, value)
    elseif key == "gemini_model" then
        return _M.set_gemini_model(user_id, value)
    else
        -- プリファレンスに保存
        return _M.set_preference(user_id, key, value)
    end
end

-- ========================================
-- バリデーション
-- ========================================

-- 設定データをバリデーション
-- @param data 設定データ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_settings_data(data)
    if not data then
        return false, "データが空です"
    end
    
    -- ユーザーIDチェック
    if not data.user_id then
        return false, "ユーザーIDが必要です"
    end
    
    local is_valid, user_id = validator.validate_positive_integer(data.user_id)
    if not is_valid then
        return false, "無効なユーザーIDです"
    end
    
    -- Geminiモデルチェック
    if data.gemini_model then
        local valid_models = {
            "gemini-1.5-pro",
            "gemini-1.5-flash",
            "gemini-pro",
            "gemini-pro-vision"
        }
        
        local ok, err = validator.validate_enum(data.gemini_model, valid_models)
        if not ok then
            return false, "無効なGeminiモデルです"
        end
    end
    
    return true, nil
end

-- ========================================
-- 設定の初期化
-- ========================================

-- ユーザーのデフォルト設定を作成
-- @param user_id ユーザーID
-- @return 設定ID、エラー
function _M.initialize_settings(user_id)
    if not user_id then
        return nil, "ユーザーIDが指定されていません"
    end
    
    -- 既存設定をチェック
    local existing, err = _M.get_settings(user_id)
    if existing and existing.id then
        return existing.id, nil
    end
    
    -- デフォルト設定を作成
    return _M:create({
        user_id = user_id,
        gemini_model = "gemini-1.5-pro",
        preferences = "{}"
    })
end

-- ========================================
-- 設定削除
-- ========================================

-- ユーザーの設定を削除
-- @param user_id ユーザーID
-- @return 成功フラグ、エラー
function _M.delete_settings(user_id)
    if not user_id then
        return false, "ユーザーIDが指定されていません"
    end
    
    local settings, err = _M.get_settings(user_id)
    if not settings or not settings.id then
        return true, nil  -- 設定が存在しない場合は成功とみなす
    end
    
    return _M:delete(settings.id)
end

-- ========================================
-- 一括設定更新
-- ========================================

-- 複数の設定を一度に更新
-- @param user_id ユーザーID
-- @param data 設定データ {gemini_api_key, gemini_model, preferences}
-- @return 成功フラグ、エラー
function _M.update_settings(user_id, data)
    if not user_id then
        return false, "ユーザーIDが指定されていません"
    end
    
    if not data or type(data) ~= "table" then
        return false, "データが無効です"
    end
    
    local settings, err = _M.get_settings(user_id)
    local settings_id = settings and settings.id
    
    -- 更新データを準備
    local update_data = {}
    
    -- Gemini APIキー
    if data.gemini_api_key then
        local encrypted_key, err = crypto.encrypt_api_key(data.gemini_api_key)
        if encrypted_key then
            update_data.gemini_api_key = encrypted_key
        else
            return false, err or "APIキーの暗号化に失敗しました"
        end
    end
    
    -- Geminiモデル
    if data.gemini_model then
        update_data.gemini_model = data.gemini_model
    end
    
    -- プリファレンス
    if data.preferences then
        local ok, json_str = pcall(cjson.encode, data.preferences)
        if ok then
            update_data.preferences = json_str
        else
            return false, "プリファレンスのエンコードに失敗しました"
        end
    end
    
    if settings_id then
        return _M:update(settings_id, update_data)
    else
        update_data.user_id = user_id
        local new_id, err = _M:create(update_data)
        return new_id ~= nil, err
    end
end

return _M
