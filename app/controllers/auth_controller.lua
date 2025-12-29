-- app/controllers/auth_controller.lua
-- 認証コントローラー - 認証関連のHTTPエンドポイント

local cjson = require("cjson")
local AuthService = require("services.auth_service")
local Session = require("utils.session")
local validator = require("utils.validator")
local csrf = require("middleware.csrf")
local etlua = require("etlua")

local AuthController = {}

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

-- ログインフォーム表示エンドポイント
-- GET /admin/login
function AuthController.login_form(self)
  -- セッションを開始
  local session = Session.new()
  local ok = session:start()
  
  -- 既にログイン済みの場合はダッシュボードにリダイレクト
  if ok and session:is_authenticated() then
    return {
      redirect_to = "/admin/dashboard",
      status = 302
    }
  end
  
  -- セッションが無効な場合は新規作成
  if not ok then
    session = Session.new()
    session:start()
  end
  
  -- CSRFトークンを生成
  local csrf_token, err = csrf.get_token(session)
  if not csrf_token then
    ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", err or "unknown")
    csrf_token = ""
  end
  
  -- リダイレクト先を取得（クエリパラメータから）
  local redirect_to = self.params.redirect or "/admin/dashboard"
  
  -- テンプレートファイルを読み込む
  local template_path = "/app/views/auth/login.etlua"
  local template_file = io.open(template_path, "r")
  if not template_file then
    ngx.log(ngx.ERR, "テンプレートファイルが見つかりません: ", template_path)
    ngx.status = 500
    return "テンプレートファイルが見つかりません"
  end
  local template_content = template_file:read("*all")
  template_file:close()
  
  -- テンプレートをコンパイル
  local template = etlua.compile(template_content)
  
  -- テンプレートデータ
  local data = {
    csrf_token = csrf_token,
    redirect_to = redirect_to,
    error_message = self.params.error or nil
  }
  
  -- テンプレートをレンダリング
  local html = template(data)
  
  -- HTMLレスポンスを返す
  self.res.headers["Content-Type"] = "text/html; charset=utf-8"
  return html
end

-- ログインエンドポイント
-- POST /api/auth/login (JSON API)
-- POST /admin/login (HTML Form)
function AuthController.login(self)
  -- Content-TypeをチェックしてJSON APIかHTMLフォームかを判定
  local content_type = ngx.req.get_headers()["content-type"] or ""
  local is_json_request = content_type:find("application/json") ~= nil
  
  -- データを取得
  local username_or_email, password, redirect_to
  local data
  
  if is_json_request then
    -- JSON APIの場合
    local err
    data, err = get_json_body()
    if not data then
      return json_response({
        success = false,
        error = err or "Invalid request"
      }, 400)
    end
    
    username_or_email = data.username_or_email or data.username or data.email
    password = data.password
  else
    -- HTMLフォームの場合
    username_or_email = self.params.username_or_email
    password = self.params.password
    redirect_to = self.params.redirect or "/admin/dashboard"
  end
  
  -- 入力検証
  if not username_or_email or username_or_email == "" then
    if is_json_request then
      return json_response({
        success = false,
        error = "Username or email is required"
      }, 400)
    else
      return {
        redirect_to = "/admin/login?error=" .. ngx.escape_uri("ユーザー名またはメールアドレスが必要です"),
        status = 302
      }
    end
  end

  if not password or password == "" then
    if is_json_request then
      return json_response({
        success = false,
        error = "Password is required"
      }, 400)
    else
      return {
        redirect_to = "/admin/login?error=" .. ngx.escape_uri("パスワードが必要です"),
        status = 302
      }
    end
  end

  -- ログイン処理
  local result, err = AuthService.login(username_or_email, password)
  if not result then
    if is_json_request then
      return json_response({
        success = false,
        error = err or "Login failed"
      }, 401)
    else
      return {
        redirect_to = "/admin/login?error=" .. ngx.escape_uri("ユーザー名またはパスワードが正しくありません"),
        status = 302
      }
    end
  end

  -- ログイン成功
  if is_json_request then
    return json_response({
      success = true,
      data = {
        user = result.user
      },
      message = "Login successful"
    })
  else
    -- HTMLフォームの場合はリダイレクト
    return {
      redirect_to = redirect_to,
      status = 302
    }
  end
end

-- ログアウトエンドポイント
-- POST /api/auth/logout (JSON API)
-- POST /auth/logout (HTML Form)
function AuthController.logout(self)
  -- Content-TypeをチェックしてJSON APIかHTMLフォームかを判定
  local content_type = ngx.req.get_headers()["content-type"] or ""
  local is_json_request = content_type:find("application/json") ~= nil
  
  -- セッションを取得
  local session = Session.new()
  local ok = session:start()

  if ok and session:is_authenticated() then
    -- ログアウト処理
    AuthService.logout(session)
  end

  -- レスポンスの返却
  if is_json_request then
    -- JSON APIの場合
    return json_response({
      success = true,
      message = "Logout successful"
    })
  else
    -- HTMLフォームの場合はログイン画面にリダイレクト
    return {
      redirect_to = "/admin/login",
      status = 302
    }
  end
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

-- パスワード変更フォーム表示エンドポイント
-- GET /admin/change-password
function AuthController.change_password_form(self)
  -- セッションを開始
  local session = Session.new()
  local ok = session:start()
  
  -- 認証チェック（require_authミドルウェアで既にチェックされているはず）
  if not ok or not session:is_authenticated() then
    return {
      redirect_to = "/admin/login?redirect=" .. ngx.escape_uri("/admin/change-password"),
      status = 302
    }
  end
  
  -- CSRFトークンを生成
  local csrf_token, err = csrf.get_token(session)
  if not csrf_token then
    ngx.log(ngx.ERR, "CSRFトークン生成エラー: ", err or "unknown")
    csrf_token = ""
  end
  
  -- テンプレートファイルを読み込む
  local template_path = "/app/views/auth/change_password.etlua"
  local template_file = io.open(template_path, "r")
  if not template_file then
    ngx.log(ngx.ERR, "テンプレートファイルが見つかりません: ", template_path)
    ngx.status = 500
    return "テンプレートファイルが見つかりません"
  end
  local template_content = template_file:read("*all")
  template_file:close()
  
  -- テンプレートをコンパイル
  local template = etlua.compile(template_content)
  
  -- テンプレートデータ
  local data = {
    csrf_token = csrf_token,
    error_message = self.params.error or nil,
    success_message = self.params.success or nil
  }
  
  -- テンプレートをレンダリング
  local html = template(data)
  
  -- HTMLレスポンスを返す
  self.res.headers["Content-Type"] = "text/html; charset=utf-8"
  return html
end

-- パスワード変更処理エンドポイント
-- POST /admin/change-password
function AuthController.change_password_submit(self)
  -- セッションを取得
  local session = Session.new()
  local ok = session:start()
  
  -- 認証チェック
  if not ok or not session:is_authenticated() then
    return {
      redirect_to = "/admin/login",
      status = 302
    }
  end
  
  -- CSRFトークン検証
  local csrf_valid, csrf_err = csrf.verify_token(self, session)
  if not csrf_valid then
    ngx.log(ngx.ERR, "CSRF検証失敗: ", csrf_err or "unknown")
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("セキュリティトークンが無効です。再度お試しください。"),
      status = 302
    }
  end
  
  -- フォームデータ取得
  local current_password = self.params.current_password
  local new_password = self.params.new_password
  local confirm_password = self.params.confirm_password
  
  -- バリデーション: 必須フィールド
  if not current_password or current_password == "" then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("現在のパスワードを入力してください"),
      status = 302
    }
  end
  
  if not new_password or new_password == "" then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("新しいパスワードを入力してください"),
      status = 302
    }
  end
  
  if not confirm_password or confirm_password == "" then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("新しいパスワード（確認）を入力してください"),
      status = 302
    }
  end
  
  -- バリデーション: パスワード一致確認
  if new_password ~= confirm_password then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("新しいパスワードと確認用パスワードが一致しません"),
      status = 302
    }
  end
  
  -- バリデーション: パスワード長
  if #new_password < 8 then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("新しいパスワードは8文字以上である必要があります"),
      status = 302
    }
  end
  
  -- バリデーション: パスワード要件（英字+数字）
  local has_letter = new_password:match("[a-zA-Z]")
  local has_number = new_password:match("[0-9]")
  if not has_letter or not has_number then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri("新しいパスワードには英字と数字の両方を含める必要があります"),
      status = 302
    }
  end
  
  -- パスワード変更処理
  local user_id = session:get_user_id()
  local success, err = AuthService.change_password(user_id, current_password, new_password)
  
  if not success then
    return {
      redirect_to = "/admin/change-password?error=" .. ngx.escape_uri(err or "パスワード変更に失敗しました"),
      status = 302
    }
  end
  
  -- セッションを再生成（セキュリティのため）
  session:regenerate()
  
  -- 成功メッセージとともにフォームを再表示
  return {
    redirect_to = "/admin/change-password?success=" .. ngx.escape_uri("パスワードが正常に変更されました"),
    status = 302
  }
end

return AuthController
