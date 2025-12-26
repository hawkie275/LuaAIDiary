-- app/controllers/auth_controller.lua
-- 認証コントローラー - 認証関連のHTTPエンドポイント

local cjson = require("cjson")
local AuthService = require("services.auth_service")
local Session = require("utils.session")
local validator = require("utils.validator")

local AuthController = {}

-- JSONレスポンスを送信するヘルパー関数
local function json_response(data, status)
  ngx.status = status or 200
  ngx.header.content_type = "application/json"
  ngx.say(cjson.encode(data))
end

-- リクエストボディからJSONを取得するヘルパー関数
local function get_json_body()
  ngx.req.read_body()
  local body = ngx.req.get_body_data()
  if not body then
    return nil, "Empty request body"
  end
  
  local ok, data = pcall(cjson.decode, body)
  if not ok then
    return nil, "Invalid JSON"
  end
  
  return data
end

-- ユーザー登録エンドポイント
-- POST /api/auth/register
function AuthController.register()
  -- JSONボディを取得
  local data, err = get_json_body()
  if not data then
    return json_response({
      success = false,
      error = err or "Invalid request"
    }, 400)
  end

  -- 入力検証
  if not data.username or data.username == "" then
    return json_response({
      success = false,
      error = "Username is required"
    }, 400)
  end

  local valid, err = validator.validate_username(data.username)
  if not valid then
    return json_response({
      success = false,
      error = err or "Invalid username format"
    }, 400)
  end

  if not data.email or data.email == "" then
    return json_response({
      success = false,
      error = "Email is required"
    }, 400)
  end

  local valid, err = validator.validate_email(data.email)
  if not valid then
    return json_response({
      success = false,
      error = err or "Invalid email format"
    }, 400)
  end

  if not data.password or data.password == "" then
    return json_response({
      success = false,
      error = "Password is required"
    }, 400)
  end

  if #data.password < 8 then
    return json_response({
      success = false,
      error = "Password must be at least 8 characters"
    }, 400)
  end

  -- ユーザー登録
  local user, err = AuthService.register(data)
  if not user then
    return json_response({
      success = false,
      error = err or "Registration failed"
    }, 400)
  end

  -- 自動ログイン
  local result, err = AuthService.login(data.username, data.password)
  if not result then
    -- 登録は成功したがログインに失敗した場合
    return json_response({
      success = true,
      data = { user = user },
      message = "Registration successful. Please login."
    }, 201)
  end

  return json_response({
    success = true,
    data = {
      user = result.user
    },
    message = "Registration successful"
  }, 201)
end

-- ログインエンドポイント
-- POST /api/auth/login
function AuthController.login()
  -- JSONボディを取得
  local data, err = get_json_body()
  if not data then
    return json_response({
      success = false,
      error = err or "Invalid request"
    }, 400)
  end

  -- 入力検証
  if not data.username_or_email or data.username_or_email == "" then
    return json_response({
      success = false,
      error = "Username or email is required"
    }, 400)
  end

  if not data.password or data.password == "" then
    return json_response({
      success = false,
      error = "Password is required"
    }, 400)
  end

  -- ログイン処理
  local result, err = AuthService.login(data.username_or_email, data.password)
  if not result then
    return json_response({
      success = false,
      error = err or "Login failed"
    }, 401)
  end

  return json_response({
    success = true,
    data = {
      user = result.user
    },
    message = "Login successful"
  })
end

-- ログアウトエンドポイント
-- POST /api/auth/logout
function AuthController.logout()
  -- セッションを取得
  local session = Session.new()
  local ok = session:start()

  if ok and session:is_authenticated() then
    -- ログアウト処理
    AuthService.logout(session)
  end

  return json_response({
    success = true,
    message = "Logout successful"
  })
end

-- 現在のユーザー情報取得エンドポイント
-- GET /api/auth/me
function AuthController.me()
  -- セッションを取得
  local session = Session.new()
  local ok = session:start()

  if not ok or not session:is_authenticated() then
    return json_response({
      success = false,
      error = "Not authenticated"
    }, 401)
  end

  -- ユーザー情報を取得
  local user = session:get_user()
  if not user then
    return json_response({
      success = false,
      error = "User not found"
    }, 404)
  end

  return json_response({
    success = true,
    data = {
      user = user
    }
  })
end

-- パスワード変更エンドポイント
-- POST /api/auth/change-password
function AuthController.change_password()
  -- セッションを取得
  local session = Session.new()
  local ok = session:start()

  if not ok or not session:is_authenticated() then
    return json_response({
      success = false,
      error = "Not authenticated"
    }, 401)
  end

  -- JSONボディを取得
  local data, err = get_json_body()
  if not data then
    return json_response({
      success = false,
      error = err or "Invalid request"
    }, 400)
  end

  -- 入力検証
  if not data.old_password or data.old_password == "" then
    return json_response({
      success = false,
      error = "Current password is required"
    }, 400)
  end

  if not data.new_password or data.new_password == "" then
    return json_response({
      success = false,
      error = "New password is required"
    }, 400)
  end

  if #data.new_password < 8 then
    return json_response({
      success = false,
      error = "New password must be at least 8 characters"
    }, 400)
  end

  -- パスワード変更
  local user_id = session:get_user_id()
  local ok, err = AuthService.change_password(user_id, data.old_password, data.new_password)

  if not ok then
    return json_response({
      success = false,
      error = err or "Failed to change password"
    }, 400)
  end

  -- セッションを再生成（セキュリティのため）
  session:regenerate()

  return json_response({
    success = true,
    message = "Password changed successfully"
  })
end

-- 認証状態チェックエンドポイント
-- GET /api/auth/check
function AuthController.check()
  -- セッションを取得
  local session = Session.new()
  local ok = session:start()

  local is_authenticated = ok and session:is_authenticated()

  return json_response({
    success = true,
    data = {
      authenticated = is_authenticated
    }
  })
end

return AuthController
