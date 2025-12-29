local http = require("resty.http")
local cjson = require("cjson.safe")
local ngx = ngx

local GeminiService = {}

-- Gemini API のベースURL (v1beta を使用)
local GEMINI_API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"
local DEFAULT_MODEL = "gemini-2.5-flash"  -- デフォルトモデル（2025年時点）
local DEFAULT_TIMEOUT = 30000  -- 30秒
local MAX_RETRIES = 3
local RETRY_DELAY = 1000  -- 1秒

-- プロンプト内のプレースホルダーを置換する
local function replace_placeholders(prompt, params)
    local result = prompt
    for key, value in pairs(params) do
        local placeholder = "{" .. key .. "}"
        if type(value) == "table" then
            value = table.concat(value, ", ")
        end
        result = string.gsub(result, placeholder, tostring(value))
    end
    return result
end

-- JSON レスポンスからテキストを抽出
local function extract_text_from_response(response_body)
    local data, err = cjson.decode(response_body)
    if not data then
        return nil, "JSONのパースに失敗しました: " .. (err or "不明なエラー")
    end
    
    if data.error then
        return nil, "Gemini APIエラー: " .. (data.error.message or "不明なエラー")
    end
    
    if not data.candidates or #data.candidates == 0 then
        return nil, "レスポンスに候補が含まれていません"
    end
    
    local candidate = data.candidates[1]
    if not candidate.content or not candidate.content.parts or #candidate.content.parts == 0 then
        return nil, "レスポンスにコンテンツが含まれていません"
    end
    
    local text = candidate.content.parts[1].text
    if not text then
        return nil, "レスポンスにテキストが含まれていません"
    end
    
    return text
end

-- Gemini API にリクエストを送信（リトライ機能付き）
local function call_gemini_api(api_key, prompt, model, retries)
    retries = retries or 0
    model = model or DEFAULT_MODEL
    
    local httpc = http.new()
    httpc:set_timeout(DEFAULT_TIMEOUT)
    
    local url = string.format("%s/%s:generateContent?key=%s",
        GEMINI_API_BASE_URL, model, api_key)
    
    local request_body = cjson.encode({
        contents = {
            {
                parts = {
                    { text = prompt }
                }
            }
        },
        generationConfig = {
            temperature = 0.7,
            topK = 40,
            topP = 0.95,
            maxOutputTokens = 8192,  -- トークン数を増やして長いJSON応答に対応
        }
    })
    
    local res, err = httpc:request_uri(url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        body = request_body,
        ssl_verify = false
    })
    
    if not res then
        if retries < MAX_RETRIES then
            ngx.sleep(RETRY_DELAY / 1000)
            return call_gemini_api(api_key, prompt, model, retries + 1)
        end
        return nil, "APIリクエストに失敗しました: " .. (err or "不明なエラー")
    end
    
    if res.status ~= 200 then
        if retries < MAX_RETRIES and (res.status >= 500 or res.status == 429) then
            ngx.sleep(RETRY_DELAY / 1000)
            return call_gemini_api(api_key, prompt, model, retries + 1)
        end
        return nil, string.format("APIリクエストが失敗しました (ステータスコード: %d): %s", 
            res.status, res.body or "不明なエラー")
    end
    
    return res.body
end

-- 記事を生成
function GeminiService.generate_article(params)
    if not params.api_key then
        return nil, "APIキーが指定されていません"
    end
    
    if not params.prompt_template then
        return nil, "プロンプトテンプレートが指定されていません"
    end
    
    -- 必須パラメータのチェック
    if not params.topic then
        return nil, "テーマが指定されていません"
    end
    
    -- デフォルト値の設定
    params.keywords = params.keywords or ""
    params.target_audience = params.target_audience or "一般読者"
    params.word_count = params.word_count or 2000
    params.tone = params.tone or "formal"
    params.model = params.model or DEFAULT_MODEL
    
    -- プレースホルダーを置換
    local prompt = replace_placeholders(params.prompt_template, {
        topic = params.topic,
        keywords = params.keywords,
        target_audience = params.target_audience,
        word_count = params.word_count,
        tone = params.tone
    })
    
    ngx.log(ngx.INFO, "Gemini API: 記事生成リクエスト - トピック: " .. params.topic .. ", モデル: " .. params.model)
    
    -- APIを呼び出し
    local response_body, err = call_gemini_api(params.api_key, prompt, params.model)
    if not response_body then
        return nil, err
    end
    
    -- レスポンスからテキストを抽出
    local text, err = extract_text_from_response(response_body)
    if not text then
        return nil, err
    end
    
    -- JSONマークダウン記号を削除
    text = string.gsub(text, "^```json%s*", "")
    text = string.gsub(text, "^```%s*", "")
    text = string.gsub(text, "%s*```$", "")
    
    -- 前後の余分なテキストを削除（最初の{から最後の}まで）
    local json_start = string.find(text, "{")
    local json_end = string.find(text, "}[^}]*$")
    
    if json_start and json_end then
        text = string.sub(text, json_start, json_end)
    end
    
    -- 前後の空白を削除
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    
    -- JSONをパース
    local result, err = cjson.decode(text)
    if not result then
        ngx.log(ngx.ERR, "記事生成のJSONパースエラー: " .. (err or "不明なエラー"))
        ngx.log(ngx.ERR, "レスポンステキスト長: " .. #text)
        ngx.log(ngx.ERR, "レスポンステキスト（最初の500文字）: " .. string.sub(text, 1, 500))
        ngx.log(ngx.ERR, "レスポンステキスト（最後の500文字）: " .. string.sub(text, -500))
        return nil, "記事生成のJSONパースに失敗しました。プロンプトを調整して再試行してください。"
    end
    
    return result
end

-- 記事を校正
function GeminiService.proofread(content, options)
    if not options.api_key then
        return nil, "APIキーが指定されていません"
    end
    
    if not options.prompt_template then
        return nil, "プロンプトテンプレートが指定されていません"
    end
    
    if not content or content == "" then
        return nil, "校正する本文が指定されていません"
    end
    
    -- デフォルト値の設定
    options.tone = options.tone or "formal"
    options.model = options.model or DEFAULT_MODEL
    
    -- プレースホルダーを置換
    local prompt = replace_placeholders(options.prompt_template, {
        content = content,
        tone = options.tone
    })
    
    ngx.log(ngx.INFO, "Gemini API: 校正リクエスト - 文字数: " .. #content .. ", モデル: " .. options.model)
    
    -- APIを呼び出し
    local response_body, err = call_gemini_api(options.api_key, prompt, options.model)
    if not response_body then
        return nil, err
    end
    
    -- レスポンスからテキストを抽出
    local text, err = extract_text_from_response(response_body)
    if not text then
        return nil, err
    end
    
    -- JSONマークダウン記号を削除
    text = string.gsub(text, "^```json%s*", "")
    text = string.gsub(text, "^```%s*", "")
    text = string.gsub(text, "%s*```$", "")
    
    -- 前後の余分なテキストを削除（最初の{から最後の}まで）
    local json_start = string.find(text, "{")
    local json_end = string.find(text, "}[^}]*$")
    
    if json_start and json_end then
        text = string.sub(text, json_start, json_end)
    end
    
    -- 前後の空白を削除
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    
    -- JSONをパース
    local result, err = cjson.decode(text)
    if not result then
        ngx.log(ngx.ERR, "校正結果のJSONパースエラー: " .. (err or "不明なエラー"))
        ngx.log(ngx.ERR, "レスポンステキスト長: " .. #text)
        ngx.log(ngx.ERR, "レスポンステキスト（最初の500文字）: " .. string.sub(text, 1, 500))
        ngx.log(ngx.ERR, "レスポンステキスト（最後の500文字）: " .. string.sub(text, -500))
        return nil, "校正結果のJSONパースに失敗しました。プロンプトを調整して再試行してください。"
    end
    
    return result
end

-- API接続をテスト
function GeminiService.test_connection(api_key, model)
    if not api_key or api_key == "" then
        return nil, "APIキーが指定されていません"
    end
    
    model = model or DEFAULT_MODEL
    
    local test_prompt = "こんにちは。このメッセージは接続テストです。「接続成功」と返答してください。"
    
    ngx.log(ngx.INFO, "Gemini API: 接続テスト - モデル: " .. model)
    
    -- APIを呼び出し
    local response_body, err = call_gemini_api(api_key, test_prompt, model)
    if not response_body then
        return nil, err
    end
    
    -- レスポンスからテキストを抽出
    local text, err = extract_text_from_response(response_body)
    if not text then
        return nil, err
    end
    
    return {
        success = true,
        message = "API接続に成功しました",
        response = text
    }
end

return GeminiService
