-- tests/controllers/test_user_controller_spec.lua
-- ユーザーコントローラー（プロフィール）のテスト

describe("ユーザーコントローラー: プロフィール編集", function()
  local mock_session
  local mock_User
  local mock_csrf

  local function call_edit_profile()
    local UserController = require("controllers.user_controller")
    local self = { res = { headers = {} }, req = { params_get = {} } }
    local result = UserController:edit_profile(self)
    return result, self
  end

  before_each(function()
    package.loaded["controllers.user_controller"] = nil
    package.loaded["utils.session"] = nil
    package.loaded["models.user"] = nil
    package.loaded["middleware.csrf"] = nil
    package.loaded["config.database"] = nil
    package.loaded["etlua"] = nil

    _G.ngx = {
      status = 200,
      header = {},
      var = {},
      log = function() end,
      ERR = 1,
      WARN = 2
    }

    mock_session = {
      authenticated = true,
      user_id = 1,
      user = {
        id = 1,
        username = "old_name",
        email = "old@example.com",
        display_name = "Old Display",
        role = "admin"
      },
      start = function(self)
        return true
      end,
      is_authenticated = function(self)
        return self.authenticated
      end,
      get_user_id = function(self)
        return self.user_id
      end,
      get_user = function(self)
        return self.user
      end
    }

    package.preload["utils.session"] = function()
      return {
        new = function()
          return mock_session
        end
      }
    end

    mock_User = {
      find = function(self, id)
        return {
          id = id,
          username = "latest_name",
          email = "latest@example.com",
          display_name = "Latest Display",
          role = "admin"
        }, nil
      end
    }

    package.preload["models.user"] = function()
      return mock_User
    end

    mock_csrf = {
      generate_token = function(session)
        return "csrf_token_for_test"
      end
    }
    package.preload["middleware.csrf"] = function()
      return mock_csrf
    end

    package.preload["config.database"] = function()
      return {}
    end

    package.preload["etlua"] = function()
      return {
        compile = function()
          return function(data)
            return string.format("username=%s,email=%s", data.user.username, data.user.email)
          end
        end
      }
    end
  end)

  after_each(function()
    _G.ngx = nil
    package.loaded["controllers.user_controller"] = nil
    package.loaded["utils.session"] = nil
    package.loaded["models.user"] = nil
    package.loaded["middleware.csrf"] = nil
    package.loaded["config.database"] = nil
    package.loaded["etlua"] = nil
    package.preload["utils.session"] = nil
    package.preload["models.user"] = nil
    package.preload["middleware.csrf"] = nil
    package.preload["config.database"] = nil
    package.preload["etlua"] = nil
  end)

  it("プロフィール編集画面はDBから再取得した最新ユーザー情報を初期値として使うこと", function()
    local result = call_edit_profile()

    assert.is_not_nil(result)
    assert.is_true(result:match("username=latest_name") ~= nil)
    assert.is_true(result:match("email=latest@example.com") ~= nil)
    assert.is_true(result:match("old_name") == nil)
    assert.is_true(result:match("old@example.com") == nil)
  end)
end)
