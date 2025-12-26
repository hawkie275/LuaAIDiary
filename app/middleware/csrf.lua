-- app/middleware/csrf.lua
-- CSRF（Cross-Site Request Forgery）保護ミドルウェア
-- クロスサイトリクエストフォージェリ攻撃から保護するための機能を提供

local crypto = require("utils.crypto")
local Session = require("utils.session")
local bit = require("bit")

local M = {}

-- セッションキー名
local CSRF_TOKEN_KEY = "csrf_token"

-- 安全でないHTTPメソッド（CSRF保護が必要なメソッド）
local UNSAFE_METHODS = {
  POST = true,
  PUT = true,
  DELETE = true,
  PATCH = true
}

-- ========================================
-- 定数時間比較（タイミング攻撃対策）
-- ========================================

-- 2つの文字列を定数時間で比較
-- @param a 比較する文字列1
-- @param b 比較する文字列2
-- @return 一致する場合true、それ以外false
local function constant_time_compare(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then
    return false
  end
  
  -- 長さが異なる場合は不一致
  if #a ~= #b then
    return false
  end
  
  -- ビット単位で比較し、結果を累積
  local result = 0
  for i = 1, #a do
    result = bit.bor(result, bit.bxor(string.byte(a, i), string.byte(b, i)))
  end
  
  return result == 0
end

-- ========================================
-- CSRFトークン生成
-- ========================================

-- 新しいCSRFトークンを生成してセッションに保存
-- @param session セッションオブジェクト
-- @return 生成されたトークン、エラー
function M.generate_token(session)
  if not session then
    return nil, "セッションが無効です"
  end
  
  -- 32バイト（64文字のHex文字列）の暗号学的に安全なトークンを生成
  local token, err = crypto.generate_token(32)
  if not token then
    ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", err or "unknown")
    return nil, "トークンの生成に失敗しました"
  end
  
  -- セッションに保存
  session:set(CSRF_TOKEN_KEY, token)
  
  -- セッションを永続化
  local ok, save_err = session:save()
  if not ok then
    ngx.log(ngx.ERR, "セッション保存エラー: ", save_err or "unknown")
    return nil, "トークンの保存に失敗しました"
  end
  
  return token, nil
end

-- ========================================
-- CSRFトークン取得
-- ========================================

-- セッションから現在のCSRFトークンを取得
-- @param session セッションオブジェクト
-- @return トークン、エラー
function M.get_token(session)
  if not session then
    return nil, "セッションが無効です"
  end
  
  local token = session:get(CSRF_TOKEN_KEY)
  if not token then
    -- トークンが存在しない場合は新規生成
    return M.generate_token(session)
  end
  
  return token, nil
end

-- ========================================
-- CSRFトークン検証
-- ========================================

-- リクエストからCSRFトークンを抽出
-- @param req リクエストオブジェクト（Lapisのself）
-- @return トークン、エラー
local function extract_token_from_request(req)
  -- 1. X-CSRF-Tokenヘッダーから取得（優先）
  local token = req.req.headers["x-csrf-token"] or req.req.headers["X-CSRF-Token"]
  if token and token ~= "" then
    return token, nil
  end
  
  -- 2. リクエストボディの_csrf_tokenフィールドから取得（フォールバック）
  if req.params then
    token = req.params._csrf_token or req.params["_csrf_token"]
    if token and token ~= "" then
      return token, nil
    end
  end
  
  return nil, "CSRFトークンが見つかりません"
end

-- CSRFトークンを検証
-- @param req リクエストオブジェクト（Lapisのself）
-- @param session セッションオブジェクト
-- @return 検証結果（true/false）、エラーメッセージ
function M.verify_token(req, session)
  if not req then
    return false, "リクエストが無効です"
  end
  
  if not session then
    return false, "セッションが無効です"
  end
  
  -- セッションからトークンを取得
  local session_token = session:get(CSRF_TOKEN_KEY)
  if not session_token or session_token == "" then
    return false, "セッションにCSRFトークンがありません"
  end
  
  -- リクエストからトークンを抽出
  local request_token, err = extract_token_from_request(req)
  if not request_token then
    return false, err or "CSRFトークンが提供されていません"
  end
  
  -- 定数時間比較でトークンを検証
  if not constant_time_compare(session_token, request_token) then
    return false, "CSRFトークンが一致しません"
  end
  
  return true, nil
end

-- ========================================
-- ミドルウェア関数
-- ========================================

-- CSRF保護ミドルウェア
-- Lapisのbefore_filterで使用するための関数を返す
-- @return ミドルウェア関数
function M.protect()
  return function(self)
    -- HTTPメソッドを取得
    local method = self.req.method or ngx.req.get_method()
    
    -- 安全なメソッド（GET, HEAD, OPTIONS, TRACE）はスキップ
    if not UNSAFE_METHODS[method] then
      return -- 検証をスキップして次の処理へ
    end
    
    -- セッションを開始
    local session = Session.new()
    local ok, err = session:start()
    if not ok then
      ngx.log(ngx.ERR, "セッション開始エラー: ", err or "unknown")
      self:write({
        status = 403,
        json = {
          error = "セッションエラー",
          message = "セッションの初期化に失敗しました"
        }
      })
      return
    end
    
    -- CSRFトークンを検証
    local valid, verify_err = M.verify_token(self, session)
    if not valid then
      ngx.log(ngx.WARN, "CSRF検証失敗: ", verify_err or "unknown", " (Method: ", method, ")")
      self:write({
        status = 403,
        json = {
          error = "CSRF検証エラー",
          message = "不正なリクエストです"
        }
      })
      return
    end
    
    -- 検証成功 - セッションをリクエストコンテキストに保存
    self.session = session
  end
end

-- ========================================
-- APIエンドポイント用ヘルパー
-- ========================================

-- CSRFトークンを取得するAPIエンドポイント用の関数
-- @param self Lapisのリクエストハンドラのself
-- @return レスポンス
function M.get_token_endpoint(self)
  -- セッションを開始
  local session = Session.new()
  local ok, err = session:start()
  if not ok then
    ngx.log(ngx.ERR, "セッション開始エラー: ", err or "unknown")
    return {
      status = 500,
      json = {
        error = "セッションエラー",
        message = "セッションの初期化に失敗しました"
      }
    }
  end
  
  -- トークンを取得（存在しなければ生成）
  local token, token_err = M.get_token(session)
  if not token then
    ngx.log(ngx.ERR, "CSRFトークン取得エラー: ", token_err or "unknown")
    return {
      status = 500,
      json = {
        error = "トークン生成エラー",
        message = "CSRFトークンの生成に失敗しました"
      }
    }
  end
  
  return {
    json = {
      csrf_token = token
    }
  }
end

return M
