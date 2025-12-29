-- 暗号化ユーティリティ
-- AES-256-CBC暗号化・復号化、ハッシュ生成などを提供します

local resty_string = require("resty.string")
local resty_random = require("resty.random")
local aes = require("resty.aes")

local _M = {}

-- マスター暗号化キー（環境変数から取得）
local MASTER_KEY = os.getenv("ENCRYPTION_KEY") or "default_32_byte_key_change_me!"

-- AES-256-CBC用のキーを32バイトに調整
local function normalize_key(key)
    if #key > 32 then
        return key:sub(1, 32)
    elseif #key < 32 then
        return key .. string.rep("0", 32 - #key)
    end
    return key
end

-- Hex文字列をバイナリに変換
local function from_hex(hex_str)
    if not hex_str or hex_str == "" then
        return nil
    end
    
    -- Hex文字列の長さが偶数であることを確認
    if #hex_str % 2 ~= 0 then
        return nil
    end
    
    local result = {}
    for i = 1, #hex_str, 2 do
        local byte_str = hex_str:sub(i, i + 1)
        local byte_val = tonumber(byte_str, 16)
        if not byte_val then
            return nil
        end
        table.insert(result, string.char(byte_val))
    end
    
    return table.concat(result)
end

-- ========================================
-- 暗号化・復号化
-- ========================================

-- データを暗号化（AES-256-CBC）
-- @param plaintext 平文
-- @param key 暗号化キー（オプション、デフォルトはマスターキー）
-- @return 暗号化された文字列（Hex形式）、エラー
function _M.encrypt(plaintext, key)
    if not plaintext or plaintext == "" then
        return nil, "平文が空です"
    end
    
    key = normalize_key(key or MASTER_KEY)
    
    -- IVを生成（16バイト）
    local iv = resty_random.bytes(16)
    if not iv then
        return nil, "IV生成に失敗しました"
    end
    
    -- AES暗号化オブジェクトを作成
    local cipher = aes:new(key, nil, aes.cipher(256, "cbc"), {iv = iv})
    if not cipher then
        return nil, "暗号化オブジェクトの作成に失敗しました"
    end
    
    -- 暗号化実行
    local encrypted = cipher:encrypt(plaintext)
    if not encrypted then
        return nil, "暗号化に失敗しました"
    end
    
    -- IVと暗号文を結合してHex形式で返す
    local combined = iv .. encrypted
    return resty_string.to_hex(combined), nil
end

-- データを復号化（AES-256-CBC）
-- @param ciphertext 暗号文（Hex形式）
-- @param key 復号化キー（オプション、デフォルトはマスターキー）
-- @return 復号化された文字列、エラー
function _M.decrypt(ciphertext, key)
    if not ciphertext or ciphertext == "" then
        return nil, "暗号文が空です"
    end
    
    key = normalize_key(key or MASTER_KEY)
    
    -- Hexからバイナリに変換
    local combined = from_hex(ciphertext)
    if not combined then
        return nil, "Hex変換に失敗しました"
    end
    
    -- IVと暗号文を分離（最初の16バイトがIV）
    if #combined < 17 then
        return nil, "暗号文が短すぎます"
    end
    
    local iv = combined:sub(1, 16)
    local encrypted = combined:sub(17)
    
    -- AES復号化オブジェクトを作成
    local cipher = aes:new(key, nil, aes.cipher(256, "cbc"), {iv = iv})
    if not cipher then
        return nil, "復号化オブジェクトの作成に失敗しました"
    end
    
    -- 復号化実行
    local decrypted = cipher:decrypt(encrypted)
    if not decrypted then
        return nil, "復号化に失敗しました"
    end
    
    return decrypted, nil
end

-- ========================================
-- APIキー管理
-- ========================================

-- APIキーを暗号化して保存用に変換
-- @param api_key 平文のAPIキー
-- @return 暗号化されたAPIキー、エラー
function _M.encrypt_api_key(api_key)
    return _M.encrypt(api_key)
end

-- 保存されたAPIキーを復号化
-- @param encrypted_key 暗号化されたAPIキー
-- @return 平文のAPIキー、エラー
function _M.decrypt_api_key(encrypted_key)
    return _M.decrypt(encrypted_key)
end

-- ========================================
-- ハッシュ生成
-- ========================================

-- パスワードをハッシュ化（bcrypt使用）
-- @param password 平文パスワード
-- @param rounds コストファクタ（デフォルト: 12）
-- @return ハッシュ化されたパスワード、エラー
function _M.hash_password(password, rounds)
    if not password or password == "" then
        return nil, "パスワードが空です"
    end
    
    local bcrypt = require("bcrypt")
    rounds = rounds or 12
    
    local hash, err = bcrypt.digest(password, rounds)
    if not hash then
        return nil, err or "ハッシュ化に失敗しました"
    end
    
    return hash, nil
end

-- パスワードを検証
-- @param password 平文パスワード
-- @param hash ハッシュ化されたパスワード
-- @return 検証結果（true/false）
function _M.verify_password(password, hash)
    if not password or not hash then
        return false
    end
    
    local bcrypt = require("bcrypt")
    return bcrypt.verify(password, hash)
end

-- ========================================
-- ランダム文字列生成
-- ========================================

-- ランダムなソルトを生成
-- @param length バイト数（デフォルト: 16）
-- @return ソルト（Hex形式）、エラー
function _M.generate_salt(length)
    length = length or 16
    
    local random_bytes = resty_random.bytes(length)
    if not random_bytes then
        return nil, "ランダムバイト生成に失敗しました"
    end
    
    return resty_string.to_hex(random_bytes), nil
end

-- ランダムなトークンを生成
-- @param length バイト数（デフォルト: 32）
-- @return トークン（Hex形式）、エラー
function _M.generate_token(length)
    return _M.generate_salt(length or 32)
end

-- ========================================
-- SHA256ハッシュ
-- ========================================

-- SHA256ハッシュを生成
-- @param data ハッシュ化するデータ
-- @return SHA256ハッシュ（Hex形式）
function _M.sha256(data)
    if not data then
        return nil
    end
    
    local resty_sha256 = require("resty.sha256")
    local sha256 = resty_sha256:new()
    sha256:update(data)
    local digest = sha256:final()
    
    return resty_string.to_hex(digest)
end

-- HMAC-SHA256を生成
-- @param data データ
-- @param key キー
-- @return HMAC-SHA256（Hex形式）
function _M.hmac_sha256(data, key)
    if not data or not key then
        return nil
    end
    
    local resty_hmac = require("resty.hmac")
    local hmac = resty_hmac:new(key)
    
    local ok = hmac:update(data)
    if not ok then
        return nil
    end
    
    local mac = hmac:final("sha256", true)
    return resty_string.to_hex(mac)
end

return _M
