-- app/middleware/auth.lua
-- 認証ミドルウェア - リクエストの認証と権限チェック

local Session = require("utils.session")
local AuthService = require("services.auth_service")

local AuthMiddleware = {}

-- 認証が必要なエンドポイント用ミドルウェア
-- 使用例: before_filter(AuthMiddleware.require_auth)
function AuthMiddleware.require_auth(self)
  -- セッションを開始
  local session = Session.new()
  local ok, err = session:start()

  if not ok then
    ngx.log(ngx.ERR, "Failed to start session: ", err)
    self:write({
      json = {
        success = false,
        error = "Session error"
      },
      status = 500
    })
    return
  end

  -- 認証状態をチェック
  if not session:is_authenticated() then
    self:write({
      json = {
        success = false,
        error = "Authentication required"
      },
      status = 401
    })
    return
  end

  -- セッションとユーザー情報をリクエストに添付
  self.session = session
  self.current_user = session:get_user()
end

-- 特定の権限レベルが必要なエンドポイント用ミドルウェアファクトリー
-- @param required_role string 必要な権限レベル ("admin", "editor", "author", "contributor", "subscriber")
-- @return function ミドルウェア関数
-- 使用例: before_filter(AuthMiddleware.require_role("admin"))
function AuthMiddleware.require_role(required_role)
  return function(self)
    -- まず認証をチェック
    AuthMiddleware.require_auth(self)
    
    -- 既にエラーレスポンスが書き込まれている場合は終了
    if self.res and self.res.status and self.res.status ~= 200 then
      return
    end

    -- 権限をチェック
    if not self.current_user then
      self:write({
        json = {
          success = false,
          error = "User information not found"
        },
        status = 401
      })
      return
    end

    local has_permission = AuthService.check_permission(self.current_user, required_role)
    if not has_permission then
      self:write({
        json = {
          success = false,
          error = "Insufficient permissions"
        },
        status = 403
      })
      return
    end
  end
end

-- 管理者権限が必要なエンドポイント用ミドルウェア
-- 使用例: before_filter(AuthMiddleware.require_admin)
function AuthMiddleware.require_admin(self)
  return AuthMiddleware.require_role("admin")(self)
end

-- エディター権限以上が必要なエンドポイント用ミドルウェア
-- 使用例: before_filter(AuthMiddleware.require_editor)
function AuthMiddleware.require_editor(self)
  return AuthMiddleware.require_role("editor")(self)
end

-- 著者権限以上が必要なエンドポイント用ミドルウェア
-- 使用例: before_filter(AuthMiddleware.require_author)
function AuthMiddleware.require_author(self)
  return AuthMiddleware.require_role("author")(self)
end

-- オプション認証ミドルウェア（認証されている場合のみユーザー情報を取得）
-- 認証されていなくてもエラーを返さない
-- 使用例: before_filter(AuthMiddleware.optional_auth)
function AuthMiddleware.optional_auth(self)
  -- セッションを開始
  local session = Session.new()
  local ok, err = session:start()

  if ok and session:is_authenticated() then
    -- セッションとユーザー情報をリクエストに添付
    self.session = session
    self.current_user = session:get_user()
  end
  
  -- 認証されていなくてもエラーを返さない
end

-- セッションをリクエストに添付するだけのミドルウェア
-- 認証チェックは行わない
-- 使用例: before_filter(AuthMiddleware.load_session)
function AuthMiddleware.load_session(self)
  local session = Session.new()
  local ok, err = session:start()

  if ok then
    self.session = session
    if session:is_authenticated() then
      self.current_user = session:get_user()
    end
  end
end

-- 自分自身または管理者のみアクセス可能なリソース用ミドルウェアファクトリー
-- @param get_resource_user_id function リソースのuser_idを取得する関数
-- @return function ミドルウェア関数
-- 使用例: before_filter(AuthMiddleware.require_self_or_admin(function(self) return self.params.user_id end))
function AuthMiddleware.require_self_or_admin(get_resource_user_id)
  return function(self)
    -- まず認証をチェック
    AuthMiddleware.require_auth(self)
    
    -- 既にエラーレスポンスが書き込まれている場合は終了
    if self.res and self.res.status and self.res.status ~= 200 then
      return
    end

    if not self.current_user then
      self:write({
        json = {
          success = false,
          error = "User information not found"
        },
        status = 401
      })
      return
    end

    -- 管理者の場合はアクセス許可
    if self.current_user.role == "admin" then
      return
    end

    -- リソースのuser_idを取得
    local resource_user_id = get_resource_user_id(self)
    
    -- 自分自身のリソースの場合はアクセス許可
    if self.current_user.id == tonumber(resource_user_id) then
      return
    end

    -- それ以外はアクセス拒否
    self:write({
      json = {
        success = false,
        error = "Access denied"
      },
      status = 403
    })
  end
end

-- 投稿の所有者または管理者のみアクセス可能なミドルウェアファクトリー
-- @param get_post_id function 投稿IDを取得する関数
-- @return function ミドルウェア関数
function AuthMiddleware.require_post_owner_or_admin(get_post_id)
  return function(self)
    -- まず認証をチェック
    AuthMiddleware.require_auth(self)
    
    -- 既にエラーレスポンスが書き込まれている場合は終了
    if self.res and self.res.status and self.res.status ~= 200 then
      return
    end

    if not self.current_user then
      self:write({
        json = {
          success = false,
          error = "User information not found"
        },
        status = 401
      })
      return
    end

    -- 管理者またはエディターの場合はアクセス許可
    if AuthService.check_permission(self.current_user, "editor") then
      return
    end

    -- 投稿を取得
    local Post = require("models.post")
    local post_id = get_post_id(self)
    local post = Post:find(tonumber(post_id))

    if not post then
      self:write({
        json = {
          success = false,
          error = "Post not found"
        },
        status = 404
      })
      return
    end

    -- 投稿の所有者の場合はアクセス許可
    if post.author_id == self.current_user.id then
      return
    end

    -- それ以外はアクセス拒否
    self:write({
      json = {
        success = false,
        error = "Access denied"
      },
      status = 403
    })
  end
end

return AuthMiddleware
