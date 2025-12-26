-- app/services/auth_service.lua
-- 認証サービス - ユーザー認証、パスワード管理

local crypto = require("utils.crypto")
local User = require("models.user")
local Session = require("utils.session")

local AuthService = {}

-- パスワードをハッシュ化
-- @param password string 平文パスワード
-- @return string ハッシュ化されたパスワード
function AuthService.hash_password(password)
  return crypto.hash_password(password)
end

-- パスワードを検証
-- @param password string 平文パスワード
-- @param hash string ハッシュ化されたパスワード
-- @return boolean 一致すればtrue
function AuthService.verify_password(password, hash)
  return crypto.verify_password(password, hash)
end

-- ユーザーを認証（ログイン処理）
-- @param username_or_email string ユーザー名またはメールアドレス
-- @param password string パスワード
-- @return table|nil ユーザー情報またはnil
-- @return string エラーメッセージ
function AuthService.authenticate(username_or_email, password)
  -- 入力検証
  if not username_or_email or username_or_email == "" then
    return nil, "Username or email is required"
  end

  if not password or password == "" then
    return nil, "Password is required"
  end

  -- ユーザーを認証（ユーザー名またはメールアドレス）
  local user, err
  
  if string.find(username_or_email, "@") then
    -- メールアドレスで認証
    user, err = User.authenticate_by_email(username_or_email, password)
  else
    -- ユーザー名で認証
    user, err = User.authenticate(username_or_email, password)
  end

  if not user then
    return nil, err or "Invalid credentials"
  end

  return user
end

-- ユーザーを登録
-- @param data table ユーザー情報 {username, email, password, display_name?, role?}
-- @return table|nil ユーザー情報またはnil
-- @return string エラーメッセージ
function AuthService.register(data)
  -- 入力検証
  if not data.username or data.username == "" then
    return nil, "Username is required"
  end

  if not data.email or data.email == "" then
    return nil, "Email is required"
  end

  if not data.password or data.password == "" then
    return nil, "Password is required"
  end

  -- ユーザーを作成（User.create_userが検証とハッシュ化を行う）
  local user_id, err = User.create_user(data)
  if not user_id then
    ngx.log(ngx.ERR, "Failed to create user: ", err or "unknown error")
    return nil, err or "Failed to create user"
  end

  -- 作成したユーザー情報を取得
  local user = User.get_safe_user(user_id)
  if not user then
    return nil, "User created but failed to retrieve"
  end

  return user
end

-- ログイン処理（セッションを作成）
-- @param username_or_email string ユーザー名またはメールアドレス
-- @param password string パスワード
-- @return table|nil セッション情報またはnil
-- @return string エラーメッセージ
function AuthService.login(username_or_email, password)
  -- ユーザーを認証
  local user, err = AuthService.authenticate(username_or_email, password)
  if not user then
    return nil, err
  end

  -- セッションを開始
  local session = Session.new()
  local ok, err = session:start()
  if not ok then
    ngx.log(ngx.ERR, "Failed to start session: ", err)
    return nil, "Failed to create session"
  end

  -- ユーザー情報をセッションに保存
  session:set_user(user.id, user)

  -- セッションを保存
  ok, err = session:save()
  if not ok then
    ngx.log(ngx.ERR, "Failed to save session: ", err)
    return nil, "Failed to save session"
  end

  return {
    user = user,
    session_id = session.session_id
  }
end

-- ログアウト処理（セッションを破棄）
-- @param session Session セッションオブジェクト
-- @return boolean 成功すればtrue
function AuthService.logout(session)
  if not session then
    return false
  end

  local ok, err = session:destroy()
  if not ok then
    ngx.log(ngx.ERR, "Failed to destroy session: ", err)
    return false
  end

  return true
end

-- 現在のユーザーを取得
-- @param session Session セッションオブジェクト
-- @return table|nil ユーザー情報またはnil
function AuthService.get_current_user(session)
  if not session then
    return nil
  end

  if not session:is_authenticated() then
    return nil
  end

  return session:get_user()
end

-- ユーザーIDから完全なユーザー情報を取得
-- @param user_id number ユーザーID
-- @return table|nil ユーザー情報またはnil
function AuthService.get_user_by_id(user_id)
  if not user_id then
    return nil
  end

  local user, err = User:find(user_id)
  if not user then
    return nil
  end

  -- パスワードハッシュを除外
  local safe_user = {
    id = user.id,
    username = user.username,
    email = user.email,
    display_name = user.display_name,
    role = user.role,
    created_at = user.created_at
  }

  return safe_user
end

-- パスワードを変更
-- @param user_id number ユーザーID
-- @param old_password string 現在のパスワード
-- @param new_password string 新しいパスワード
-- @return boolean 成功すればtrue
-- @return string エラーメッセージ
function AuthService.change_password(user_id, old_password, new_password)
  return User.change_password(user_id, old_password, new_password)
end

-- パスワードをリセット（管理者用）
-- @param user_id number ユーザーID
-- @param new_password string 新しいパスワード
-- @return boolean 成功すればtrue
-- @return string エラーメッセージ
function AuthService.reset_password(user_id, new_password)
  -- 新しいパスワードの強度チェック
  if #new_password < 8 then
    return false, "New password must be at least 8 characters"
  end

  -- 新しいパスワードをハッシュ化
  local new_hash, err = AuthService.hash_password(new_password)
  if not new_hash then
    return false, err or "Failed to hash password"
  end

  -- パスワードを更新
  local ok, err = User:update(user_id, { password_hash = new_hash })
  if not ok then
    ngx.log(ngx.ERR, "Failed to reset password: ", err)
    return false, "Failed to reset password"
  end

  return true
end

-- 権限をチェック
-- @param user table ユーザー情報
-- @param required_role string 必要な権限レベル
-- @return boolean 権限があればtrue
function AuthService.check_permission(user, required_role)
  if not user or not user.role then
    return false
  end

  local role_hierarchy = {
    subscriber = 1,
    contributor = 2,
    author = 3,
    editor = 4,
    admin = 5
  }

  local user_level = role_hierarchy[user.role] or 0
  local required_level = role_hierarchy[required_role] or 0

  return user_level >= required_level
end

return AuthService
