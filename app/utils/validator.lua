-- バリデーションユーティリティ
-- 入力検証、サニタイゼーション、XSS対策を提供します

local _M = {}

-- ========================================
-- メールアドレス検証
-- ========================================

-- メールアドレスの形式を検証
-- @param email メールアドレス
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_email(email)
    if not email or email == "" then
        return false, "メールアドレスが空です"
    end
    
    -- 基本的なメールアドレス形式チェック
    -- ローカル部分@ドメイン.TLD の形式
    local pattern = "^[%w%.%+%-_]+@[%w%.%-]+%.%w+$"
    if not email:match(pattern) then
        return false, "無効なメールアドレス形式です"
    end
    
    -- 長さチェック
    if #email > 100 then
        return false, "メールアドレスが長すぎます（100文字以内）"
    end
    
    return true, nil
end

-- ========================================
-- URL検証
-- ========================================

-- URLの形式を検証
-- @param url URL文字列
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_url(url)
    if not url or url == "" then
        return false, "URLが空です"
    end
    
    -- HTTP/HTTPSプロトコルチェック
    local pattern = "^https?://[%w%.%%%+%-]+%.[%w]+[%w%.%%%+%-/]*$"
    if not url:match(pattern) then
        return false, "無効なURL形式です"
    end
    
    return true, nil
end

-- ========================================
-- ユーザー名検証
-- ========================================

-- ユーザー名の形式を検証
-- @param username ユーザー名
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_username(username)
    if not username or username == "" then
        return false, "ユーザー名が空です"
    end
    
    -- 長さチェック（3〜50文字）
    if #username < 3 then
        return false, "ユーザー名は3文字以上にしてください"
    end
    
    if #username > 50 then
        return false, "ユーザー名は50文字以内にしてください"
    end
    
    -- 英数字とアンダースコア、ハイフンのみ許可
    local pattern = "^[%w_%-]+$"
    if not username:match(pattern) then
        return false, "ユーザー名は英数字、アンダースコア、ハイフンのみ使用できます"
    end
    
    return true, nil
end

-- ========================================
-- パスワード検証
-- ========================================

-- パスワードの強度を検証
-- @param password パスワード
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_password(password)
    if not password or password == "" then
        return false, "パスワードが空です"
    end
    
    -- 長さチェック（8文字以上）
    if #password < 8 then
        return false, "パスワードは8文字以上にしてください"
    end
    
    if #password > 100 then
        return false, "パスワードが長すぎます（100文字以内）"
    end
    
    -- 強度チェック（英字と数字を含む）
    local has_letter = password:match("[%a]")
    local has_digit = password:match("[%d]")
    
    if not has_letter or not has_digit then
        return false, "パスワードは英字と数字を含む必要があります"
    end
    
    return true, nil
end

-- ========================================
-- スラッグ検証
-- ========================================

-- スラッグの形式を検証
-- @param slug スラッグ
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_slug(slug)
    if not slug or slug == "" then
        return false, "スラッグが空です"
    end
    
    -- 長さチェック
    if #slug > 255 then
        return false, "スラッグが長すぎます（255文字以内）"
    end
    
    -- 小文字英数字とハイフンのみ許可
    local pattern = "^[a-z0-9%-]+$"
    if not slug:match(pattern) then
        return false, "スラッグは小文字英数字とハイフンのみ使用できます"
    end
    
    return true, nil
end

-- ========================================
-- サニタイゼーション
-- ========================================

-- HTMLエスケープ（XSS対策）
-- @param str 文字列
-- @return エスケープされた文字列
function _M.escape_html(str)
    if not str then
        return ""
    end
    
    str = tostring(str)
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub('"', "&quot;")
    str = str:gsub("'", "&#39;")
    
    return str
end

-- HTMLタグを除去
-- @param str 文字列
-- @return タグが除去された文字列
function _M.strip_tags(str)
    if not str then
        return ""
    end
    
    return str:gsub("<[^>]+>", "")
end

-- 安全な文字列に変換（英数字と基本記号のみ）
-- @param str 文字列
-- @return サニタイズされた文字列
function _M.sanitize_string(str)
    if not str then
        return ""
    end
    
    -- HTMLエスケープ
    str = _M.escape_html(str)
    
    -- 制御文字を除去
    str = str:gsub("[%c]", "")
    
    return str
end

-- ========================================
-- 数値検証
-- ========================================

-- 整数かどうかを検証
-- @param value 値
-- @return 検証結果（true/false）、変換後の数値
function _M.validate_integer(value)
    if not value then
        return false, nil
    end
    
    local num = tonumber(value)
    if not num then
        return false, nil
    end
    
    -- 整数チェック
    if num ~= math.floor(num) then
        return false, nil
    end
    
    return true, num
end

-- 正の整数かどうかを検証
-- @param value 値
-- @return 検証結果（true/false）、変換後の数値
function _M.validate_positive_integer(value)
    local ok, num = _M.validate_integer(value)
    if not ok then
        return false, nil
    end
    
    if num <= 0 then
        return false, nil
    end
    
    return true, num
end

-- 範囲内の数値かどうかを検証
-- @param value 値
-- @param min 最小値
-- @param max 最大値
-- @return 検証結果（true/false）、変換後の数値
function _M.validate_range(value, min, max)
    local num = tonumber(value)
    if not num then
        return false, nil
    end
    
    if num < min or num > max then
        return false, nil
    end
    
    return true, num
end

-- ========================================
-- 文字列長検証
-- ========================================

-- 文字列長を検証
-- @param str 文字列
-- @param min 最小長
-- @param max 最大長
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_length(str, min, max)
    if not str then
        return false, "文字列が空です"
    end
    
    local len = #str
    
    if min and len < min then
        return false, string.format("文字列は%d文字以上にしてください", min)
    end
    
    if max and len > max then
        return false, string.format("文字列は%d文字以内にしてください", max)
    end
    
    return true, nil
end

-- ========================================
-- ENUM検証
-- ========================================

-- 許可された値のリストに含まれるか検証
-- @param value 値
-- @param allowed_values 許可される値のテーブル
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_enum(value, allowed_values)
    if not value then
        return false, "値が空です"
    end
    
    for _, allowed in ipairs(allowed_values) do
        if value == allowed then
            return true, nil
        end
    end
    
    return false, "無効な値です"
end

-- ========================================
-- 日付検証
-- ========================================

-- 日付形式を検証（YYYY-MM-DD）
-- @param date_str 日付文字列
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_date(date_str)
    if not date_str then
        return false, "日付が空です"
    end
    
    local pattern = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"
    local year, month, day = date_str:match(pattern)
    
    if not year then
        return false, "無効な日付形式です（YYYY-MM-DD）"
    end
    
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    
    -- 月の範囲チェック
    if month < 1 or month > 12 then
        return false, "無効な月です"
    end
    
    -- 日の範囲チェック
    if day < 1 or day > 31 then
        return false, "無効な日です"
    end
    
    -- 簡易的な日付妥当性チェック
    local days_in_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    
    -- 閏年チェック
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
        days_in_month[2] = 29
    end
    
    if day > days_in_month[month] then
        return false, "無効な日付です"
    end
    
    return true, nil
end

-- ========================================
-- 複合検証
-- ========================================

-- 複数の検証を実行
-- @param value 値
-- @param validators 検証関数のテーブル
-- @return 検証結果（true/false）、エラーメッセージ
function _M.validate_all(value, validators)
    for _, validator in ipairs(validators) do
        local ok, err = validator(value)
        if not ok then
            return false, err
        end
    end
    return true, nil
end

return _M
