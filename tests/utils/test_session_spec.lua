-- tests/utils/test_session_spec.lua

describe("Session:set_user", function()
  local Session

  before_each(function()
    package.loaded["utils.session"] = nil
    package.loaded["resty.redis"] = nil
    package.loaded["resty.random"] = nil
    package.loaded["resty.string"] = nil
    package.loaded["cjson"] = nil

    _G.ngx = {
      WARN = 2,
      ERR = 1,
      log = function() end,
      header = {},
      var = {}
    }

    package.preload["resty.redis"] = function()
      return {
        new = function()
          return {
            set_timeout = function() end
          }
        end
      }
    end

    package.preload["resty.random"] = function()
      return {
        bytes = function()
          return string.rep("a", 32)
        end
      }
    end

    package.preload["resty.string"] = function()
      return {
        to_hex = function(v)
          return v
        end
      }
    end

    package.preload["cjson"] = function()
      return {
        encode = function() return "{}" end,
        decode = function() return {} end
      }
    end

    Session = require("utils.session")
  end)

  after_each(function()
    package.loaded["utils.session"] = nil
    package.loaded["resty.redis"] = nil
    package.loaded["resty.random"] = nil
    package.loaded["resty.string"] = nil
    package.loaded["cjson"] = nil
    package.preload["resty.redis"] = nil
    package.preload["resty.random"] = nil
    package.preload["resty.string"] = nil
    package.preload["cjson"] = nil
    _G.ngx = nil
  end)

  it("契約どおり (user_id, user_data) で設定できること", function()
    local session = Session.new()
    local user = { id = 10, username = "alice" }

    local ok = session:set_user(10, user)

    assert.is_true(ok)
    assert.equals(10, session:get_user_id())
    assert.same(user, session:get_user())
  end)

  it("旧シグネチャ (user_table) でも互換動作すること", function()
    local session = Session.new()
    local user = { id = 20, username = "bob" }

    local ok = session:set_user(user)

    assert.is_true(ok)
    assert.equals(20, session:get_user_id())
    assert.same(user, session:get_user())
  end)
end)

