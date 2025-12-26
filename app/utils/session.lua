-- app/utils/session.lua
-- Redisベースのセッション管理ユーティリティ

local redis = require("resty.redis")
local random = require("resty.random")
local str = require("resty.string")
local cjson = require("cjson")

local Session = {}
Session.__index = Session

-- セッション設定
local SESSION_CONFIG = {
  prefix = "session:",
  cookie_name = "luaaidiary_session",
  expire_time = 3600 * 24 * 7, -- 7日間
  cookie_lifetime = 3600 * 24 * 7,
  cookie_path = "/",
  cookie_secure = false, -- 本番環境ではtrueに
  cookie_httponly = true,
  cookie_samesite = "Lax"
}

-- Redis接続を取得
local function get_redis_connection()
  local red = redis:new()
  red:set_timeout(1000) -- 1秒

  local ok, err = red:connect("redis", 6379)
  if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return nil, err
  end

  return red
end

-- Redis接続を閉じる
local function close_redis_connection(red)
  if not red then
    return
  end

  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    ngx.log(ngx.ERR, "Failed to set keepalive: ", err)
  end
end

-- セッションIDを生成
local function generate_session_id()
  local random_bytes = random.bytes(32)
  if not random_bytes then
    ngx.log(ngx.ERR, "Failed to generate random bytes")
    return nil
  end
  return str.to_hex(random_bytes)
end

-- 新しいセッションを作成
function Session.new()
  local self = setmetatable({}, Session)
  self.session_id = nil
  self.data = {}
  self.is_new = true
  return self
end

-- セッションを開始（既存のセッションを読み込むか新規作成）
function Session:start()
  -- クッキーからセッションIDを取得
  local cookie = ngx.var["cookie_" .. SESSION_CONFIG.cookie_name]
  
  if cookie then
    -- 既存のセッションを読み込み
    local ok, err = self:load(cookie)
    if ok then
      self.session_id = cookie
      self.is_new = false
      return true
    end
  end

  -- 新しいセッションを作成
  self.session_id = generate_session_id()
  if not self.session_id then
    return nil, "Failed to generate session ID"
  end

  self.is_new = true
  return true
end

-- セッションデータを読み込み
function Session:load(session_id)
  local red, err = get_redis_connection()
  if not red then
    return nil, err
  end

  local key = SESSION_CONFIG.prefix .. session_id
  local data, err = red:get(key)
  
  close_redis_connection(red)

  if not data or data == ngx.null then
    return nil, "Session not found"
  end

  local ok, decoded = pcall(cjson.decode, data)
  if not ok then
    ngx.log(ngx.ERR, "Failed to decode session data: ", decoded)
    return nil, "Invalid session data"
  end

  self.data = decoded
  return true
end

-- セッションデータを保存
function Session:save()
  if not self.session_id then
    return nil, "No session ID"
  end

  local red, err = get_redis_connection()
  if not red then
    return nil, err
  end

  local key = SESSION_CONFIG.prefix .. self.session_id
  local encoded = cjson.encode(self.data)
  
  local ok, err = red:setex(key, SESSION_CONFIG.expire_time, encoded)
  
  close_redis_connection(red)

  if not ok then
    ngx.log(ngx.ERR, "Failed to save session: ", err)
    return nil, err
  end

  -- クッキーを設定
  self:set_cookie()

  return true
end

-- セッションクッキーを設定
function Session:set_cookie()
  local cookie_str = SESSION_CONFIG.cookie_name .. "=" .. self.session_id
  cookie_str = cookie_str .. "; Path=" .. SESSION_CONFIG.cookie_path
  cookie_str = cookie_str .. "; Max-Age=" .. SESSION_CONFIG.cookie_lifetime

  if SESSION_CONFIG.cookie_httponly then
    cookie_str = cookie_str .. "; HttpOnly"
  end

  if SESSION_CONFIG.cookie_secure then
    cookie_str = cookie_str .. "; Secure"
  end

  if SESSION_CONFIG.cookie_samesite then
    cookie_str = cookie_str .. "; SameSite=" .. SESSION_CONFIG.cookie_samesite
  end

  ngx.header["Set-Cookie"] = cookie_str
end

-- セッション値を取得
function Session:get(key)
  return self.data[key]
end

-- セッション値を設定
function Session:set(key, value)
  self.data[key] = value
end

-- セッションを破棄
function Session:destroy()
  if not self.session_id then
    return true
  end

  local red, err = get_redis_connection()
  if not red then
    return nil, err
  end

  local key = SESSION_CONFIG.prefix .. self.session_id
  red:del(key)
  
  close_redis_connection(red)

  -- クッキーを削除
  local cookie_str = SESSION_CONFIG.cookie_name .. "=; Path=" .. SESSION_CONFIG.cookie_path .. "; Max-Age=0"
  ngx.header["Set-Cookie"] = cookie_str

  self.data = {}
  self.session_id = nil

  return true
end

-- セッションの有効期限を更新
function Session:regenerate()
  -- 古いセッションを削除
  if self.session_id then
    local red, err = get_redis_connection()
    if red then
      local key = SESSION_CONFIG.prefix .. self.session_id
      red:del(key)
      close_redis_connection(red)
    end
  end

  -- 新しいセッションIDを生成
  self.session_id = generate_session_id()
  if not self.session_id then
    return nil, "Failed to generate session ID"
  end

  return self:save()
end

-- ユーザーがログインしているかチェック
function Session:is_authenticated()
  return self.data.user_id ~= nil
end

-- ログインユーザーIDを取得
function Session:get_user_id()
  return self.data.user_id
end

-- ログインユーザー情報を設定
function Session:set_user(user_id, user_data)
  self.data.user_id = user_id
  self.data.user = user_data
end

-- ログインユーザー情報を取得
function Session:get_user()
  return self.data.user
end

-- セッションからユーザー情報をクリア
function Session:clear_user()
  self.data.user_id = nil
  self.data.user = nil
end

return Session
