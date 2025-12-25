-- スラッグ生成ユーティリティ
-- URL安全な文字列への変換、日本語対応スラッグ生成を提供します

local _M = {}

-- ========================================
-- 日本語からローマ字への変換テーブル
-- ========================================

local hiragana_to_romaji = {
    ["あ"] = "a", ["い"] = "i", ["う"] = "u", ["え"] = "e", ["お"] = "o",
    ["か"] = "ka", ["き"] = "ki", ["く"] = "ku", ["け"] = "ke", ["こ"] = "ko",
    ["が"] = "ga", ["ぎ"] = "gi", ["ぐ"] = "gu", ["げ"] = "ge", ["ご"] = "go",
    ["さ"] = "sa", ["し"] = "shi", ["す"] = "su", ["せ"] = "se", ["そ"] = "so",
    ["ざ"] = "za", ["じ"] = "ji", ["ず"] = "zu", ["ぜ"] = "ze", ["ぞ"] = "zo",
    ["た"] = "ta", ["ち"] = "chi", ["つ"] = "tsu", ["て"] = "te", ["と"] = "to",
    ["だ"] = "da", ["ぢ"] = "ji", ["づ"] = "zu", ["で"] = "de", ["ど"] = "do",
    ["な"] = "na", ["に"] = "ni", ["ぬ"] = "nu", ["ね"] = "ne", ["の"] = "no",
    ["は"] = "ha", ["ひ"] = "hi", ["ふ"] = "fu", ["へ"] = "he", ["ほ"] = "ho",
    ["ば"] = "ba", ["び"] = "bi", ["ぶ"] = "bu", ["べ"] = "be", ["ぼ"] = "bo",
    ["ぱ"] = "pa", ["ぴ"] = "pi", ["ぷ"] = "pu", ["ぺ"] = "pe", ["ぽ"] = "po",
    ["ま"] = "ma", ["み"] = "mi", ["む"] = "mu", ["め"] = "me", ["も"] = "mo",
    ["や"] = "ya", ["ゆ"] = "yu", ["よ"] = "yo",
    ["ら"] = "ra", ["り"] = "ri", ["る"] = "ru", ["れ"] = "re", ["ろ"] = "ro",
    ["わ"] = "wa", ["を"] = "wo", ["ん"] = "n",
}

-- ========================================
-- スラッグ生成
-- ========================================

-- 文字列をスラッグに変換
-- @param str 元の文字列
-- @param options オプション {max_length, separator, transliterate}
-- @return スラッグ文字列
function _M.slugify(str, options)
    if not str or str == "" then
        return ""
    end
    
    options = options or {}
    local max_length = options.max_length or 255
    local separator = options.separator or "-"
    local transliterate = options.transliterate ~= false  -- デフォルトはtrue
    
    -- 小文字に変換
    str = str:lower()
    
    -- 日本語をローマ字に変換（オプション）
    if transliterate then
        str = _M.transliterate_japanese(str)
    end
    
    -- URL安全でない文字を削除または変換
    -- 英数字とハイフン、スペース以外を削除
    str = str:gsub("[^%w%s%-]", "")
    
    -- 連続するスペースを単一のセパレータに変換
    str = str:gsub("%s+", separator)
    
    -- 連続するセパレータを単一に
    str = str:gsub(separator .. "+", separator)
    
    -- 先頭と末尾のセパレータを削除
    str = str:gsub("^" .. separator, "")
    str = str:gsub(separator .. "$", "")
    
    -- 最大長に切り詰め
    if #str > max_length then
        str = str:sub(1, max_length)
        -- 最後のセパレータで切る
        local last_sep = str:reverse():find(separator)
        if last_sep then
            str = str:sub(1, #str - last_sep + 1)
        end
        -- 末尾のセパレータを削除
        str = str:gsub(separator .. "$", "")
    end
    
    return str
end

-- 日本語文字列をローマ字に変換
-- @param str 日本語文字列
-- @return ローマ字文字列
function _M.transliterate_japanese(str)
    if not str then
        return ""
    end
    
    local result = ""
    local i = 1
    
    while i <= #str do
        local char = str:sub(i, i)
        local byte = string.byte(char)
        
        -- UTF-8マルチバイト文字の処理
        if byte >= 0xE0 and byte <= 0xEF then
            -- 3バイト文字（ひらがな、カタカナ、漢字など）
            local utf8_char = str:sub(i, i + 2)
            local romaji = hiragana_to_romaji[utf8_char]
            
            if romaji then
                result = result .. romaji
            else
                -- ローマ字変換できない場合はそのまま
                result = result .. utf8_char
            end
            i = i + 3
        elseif byte >= 0xC0 and byte <= 0xDF then
            -- 2バイト文字
            result = result .. str:sub(i, i + 1)
            i = i + 2
        else
            -- 1バイト文字（ASCII）
            result = result .. char
            i = i + 1
        end
    end
    
    return result
end

-- ========================================
-- ユニークスラッグ生成
-- ========================================

-- ユニークなスラッグを生成（データベースチェック付き）
-- @param str 元の文字列
-- @param model モデルオブジェクト
-- @param id 除外するID（更新時）
-- @return ユニークなスラッグ
function _M.generate_unique_slug(str, model, id)
    local base_slug = _M.slugify(str)
    
    if not model then
        return base_slug
    end
    
    local slug = base_slug
    local counter = 1
    
    while true do
        -- 同じスラッグが存在するかチェック
        local conditions = {slug = slug}
        local existing, err = model:find_by(conditions)
        
        if err then
            ngx.log(ngx.ERR, "スラッグ検索エラー: ", err)
            return base_slug
        end
        
        -- 既存レコードがない、または自分自身のレコードの場合
        if not existing or #existing == 0 then
            return slug
        end
        
        -- 更新時：自分自身のレコードのみの場合はOK
        if id and #existing == 1 and existing[1].id == id then
            return slug
        end
        
        -- 重複がある場合は番号を付ける
        counter = counter + 1
        slug = base_slug .. "-" .. counter
        
        -- 無限ループ防止
        if counter > 1000 then
            ngx.log(ngx.WARN, "スラッグ生成の試行回数が上限に達しました")
            -- ランダムな数値を追加
            local random = require("resty.random")
            local bytes = random.bytes(4)
            if bytes then
                local str_module = require("resty.string")
                local random_str = str_module.to_hex(bytes):sub(1, 8)
                return base_slug .. "-" .. random_str
            end
            return base_slug .. "-" .. os.time()
        end
    end
end

-- ========================================
-- URL安全な文字列変換
-- ========================================

-- URL安全な文字列に変換
-- @param str 文字列
-- @return URL安全な文字列
function _M.url_safe(str)
    if not str then
        return ""
    end
    
    -- URLエンコード
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    
    return str
end

-- URLデコード
-- @param str URLエンコードされた文字列
-- @return デコードされた文字列
function _M.url_decode(str)
    if not str then
        return ""
    end
    
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    
    return str
end

-- ========================================
-- パステンプレート処理
-- ========================================

-- パステンプレートからスラッグを生成
-- @param template テンプレート文字列（例: "{year}/{month}/{slug}"）
-- @param data データテーブル
-- @return 生成されたパス
function _M.generate_path(template, data)
    if not template or not data then
        return ""
    end
    
    local path = template
    
    -- プレースホルダーを置換
    for key, value in pairs(data) do
        path = path:gsub("{" .. key .. "}", tostring(value))
    end
    
    return path
end

-- ========================================
-- スラッグバリデーション
-- ========================================

-- スラッグが有効な形式かチェック
-- @param slug スラッグ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.is_valid_slug(slug)
    if not slug or slug == "" then
        return false, "スラッグが空です"
    end
    
    -- 長さチェック
    if #slug > 255 then
        return false, "スラッグが長すぎます（255文字以内）"
    end
    
    -- 形式チェック（小文字英数字とハイフンのみ）
    if not slug:match("^[a-z0-9%-]+$") then
        return false, "スラッグは小文字英数字とハイフンのみ使用できます"
    end
    
    -- 先頭・末尾がハイフンでないか
    if slug:match("^%-") or slug:match("%-$") then
        return false, "スラッグの先頭・末尾にハイフンは使用できません"
    end
    
    -- 連続するハイフンがないか
    if slug:match("%-%-") then
        return false, "連続するハイフンは使用できません"
    end
    
    return true, nil
end

-- ========================================
-- 予約語チェック
-- ========================================

-- 予約されたスラッグのリスト
local reserved_slugs = {
    "admin", "api", "login", "logout", "register", "dashboard",
    "settings", "profile", "search", "tag", "category", "archive",
    "wp-admin", "wp-content", "wp-includes", "assets", "static"
}

-- スラッグが予約語でないかチェック
-- @param slug スラッグ
-- @return 予約語かどうか（true=予約語）
function _M.is_reserved(slug)
    for _, reserved in ipairs(reserved_slugs) do
        if slug == reserved then
            return true
        end
    end
    return false
end

-- 予約語を回避したスラッグを生成
-- @param slug スラッグ
-- @return 予約語でないスラッグ
function _M.avoid_reserved(slug)
    if _M.is_reserved(slug) then
        return slug .. "-post"
    end
    return slug
end

return _M
