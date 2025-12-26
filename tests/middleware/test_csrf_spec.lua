-- tests/middleware/test_csrf_spec.lua
-- CSRFミドルウェアのテスト

describe("CSRFミドルウェア", function()
  local csrf
  local crypto
  local mock_session
  local mock_req
  local original_ngx
  
  setup(function()
    -- bitモジュールのモック（Lua 5.1互換）
    package.preload["bit"] = function()
      local bit = {}
      
      function bit.bor(a, b)
        local result = 0
        local bitval = 1
        while a > 0 or b > 0 do
          local a_bit = a % 2
          local b_bit = b % 2
          if a_bit == 1 or b_bit == 1 then
            result = result + bitval
          end
          bitval = bitval * 2
          a = math.floor(a / 2)
          b = math.floor(b / 2)
        end
        return result
      end
      
      function bit.bxor(a, b)
        local result = 0
        local bitval = 1
        while a > 0 or b > 0 do
          local a_bit = a % 2
          local b_bit = b % 2
          if a_bit ~= b_bit then
            result = result + bitval
          end
          bitval = bitval * 2
          a = math.floor(a / 2)
          b = math.floor(b / 2)
        end
        return result
      end
      
      function bit.band(a, b)
        local result = 0
        local bitval = 1
        while a > 0 and b > 0 do
          local a_bit = a % 2
          local b_bit = b % 2
          if a_bit == 1 and b_bit == 1 then
            result = result + bitval
          end
          bitval = bitval * 2
          a = math.floor(a / 2)
          b = math.floor(b / 2)
        end
        return result
      end
      
      return bit
    end
    
    -- ngxのモック
    _G.ngx = {
      log = function() end,
      ERR = 1,
      WARN = 2,
      var = {},
      req = {
        get_method = function() return "POST" end
      },
      socket = {
        tcp = function()
          return {
            connect = function() return true end,
            setkeepalive = function() return true end,
            close = function() return true end,
            settimeout = function() return true end,
            send = function() return true end,
            receive = function() return "+OK\r\n" end
          }
        end
      }
    }
    
    -- resty.randomのモック
    package.preload["resty.random"] = function()
      return {
        bytes = function(length)
          local bytes = {}
          for i = 1, length do
            bytes[i] = string.char(math.random(0, 255))
          end
          return table.concat(bytes)
        end
      }
    end
    
    -- resty.stringのモック
    package.preload["resty.string"] = function()
      return {
        to_hex = function(str)
          local hex = ""
          for i = 1, #str do
            hex = hex .. string.format("%02x", string.byte(str, i))
          end
          return hex
        end
      }
    end
    
    -- cryptoモジュールのモック
    package.preload["utils.crypto"] = function()
      return {
        generate_token = function(length)
          -- 固定長のトークンを生成（テスト用）
          local token = ""
          for i = 1, length * 2 do
            token = token .. string.format("%x", math.random(0, 15))
          end
          return token
        end
      }
    end
    
    csrf = require("middleware.csrf")
    crypto = require("utils.crypto")
  end)
  
  teardown(function()
    -- ngxモックを削除
    _G.ngx = nil
    package.loaded["middleware.csrf"] = nil
    package.loaded["utils.crypto"] = nil
  end)
  
  before_each(function()
    -- セッションモックの初期化
    mock_session = {
      data = {},
      set = function(self, key, value)
        self.data[key] = value
      end,
      get = function(self, key)
        return self.data[key]
      end,
      save = function(self)
        return true, nil
      end,
      start = function(self)
        return true, nil
      end
    }
    
    -- リクエストモックの初期化
    mock_req = {
      req = {
        headers = {},
        method = "POST"
      },
      params = {},
      write = function(self, response)
        self.response = response
      end
    }
  end)
  
  -- ========================================
  -- トークン生成のテスト
  -- ========================================
  
  describe("generate_token", function()
    it("32バイト（64文字のHex）のトークンを生成すること", function()
      local token, err = csrf.generate_token(mock_session)
      
      assert.is_nil(err)
      assert.is_not_nil(token)
      assert.is_string(token)
      assert.equals(64, #token)
      -- Hex文字列であることを確認
      assert.is_true(token:match("^%x+$") ~= nil)
    end)
    
    it("生成したトークンがセッションに保存されること", function()
      local token, err = csrf.generate_token(mock_session)
      
      assert.is_nil(err)
      assert.equals(token, mock_session:get("csrf_token"))
    end)
    
    it("複数回呼び出すと異なるトークンが生成されること", function()
      local token1, _ = csrf.generate_token(mock_session)
      local token2, _ = csrf.generate_token(mock_session)
      
      assert.is_not_equal(token1, token2)
    end)
    
    it("セッションがnilの場合エラーを返すこと", function()
      local token, err = csrf.generate_token(nil)
      
      assert.is_nil(token)
      assert.is_not_nil(err)
      assert.equals("セッションが無効です", err)
    end)
    
    it("セッション保存失敗時にエラーを返すこと", function()
      mock_session.save = function(self)
        return false, "保存エラー"
      end
      
      local token, err = csrf.generate_token(mock_session)
      
      assert.is_nil(token)
      assert.is_not_nil(err)
      assert.equals("トークンの保存に失敗しました", err)
    end)
  end)
  
  -- ========================================
  -- トークン取得のテスト
  -- ========================================
  
  describe("get_token", function()
    it("セッションからトークンを取得できること", function()
      local test_token = "abc123def456"
      mock_session:set("csrf_token", test_token)
      
      local token, err = csrf.get_token(mock_session)
      
      assert.is_nil(err)
      assert.equals(test_token, token)
    end)
    
    it("トークンが存在しない場合、新規生成すること", function()
      local token, err = csrf.get_token(mock_session)
      
      assert.is_nil(err)
      assert.is_not_nil(token)
      assert.equals(64, #token)
      -- セッションに保存されていることを確認
      assert.equals(token, mock_session:get("csrf_token"))
    end)
    
    it("既存のトークンがある場合、それを返すこと", function()
      local test_token = "existing_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      
      local token1, _ = csrf.get_token(mock_session)
      local token2, _ = csrf.get_token(mock_session)
      
      assert.equals(test_token, token1)
      assert.equals(test_token, token2)
      assert.equals(token1, token2)
    end)
    
    it("セッションがnilの場合エラーを返すこと", function()
      local token, err = csrf.get_token(nil)
      
      assert.is_nil(token)
      assert.is_not_nil(err)
      assert.equals("セッションが無効です", err)
    end)
  end)
  
  -- ========================================
  -- トークン検証のテスト（定数時間比較も含む）
  -- ========================================
  
  describe("verify_token", function()
    it("正しいトークンでtrueを返すこと", function()
      local test_token = "abc123def456789012345678901234567890123456789012345678901234"
      mock_session:set("csrf_token", test_token)
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("誤ったトークンでfalseを返すこと", function()
      local session_token = "abc123def456789012345678901234567890123456789012345678901234"
      local wrong_token = "xyz789def456789012345678901234567890123456789012345678901234"
      mock_session:set("csrf_token", session_token)
      mock_req.req.headers["X-CSRF-Token"] = wrong_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.equals("CSRFトークンが一致しません", err)
    end)
    
    it("トークンが無い場合、falseを返すこと", function()
      local session_token = "abc123def456789012345678901234567890123456789012345678901234"
      mock_session:set("csrf_token", session_token)
      -- リクエストにトークンを設定しない
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)
    
    it("セッションにトークンが無い場合、falseを返すこと", function()
      mock_req.req.headers["X-CSRF-Token"] = "some_token"
      -- セッションにトークンを設定しない
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.equals("セッションにCSRFトークンがありません", err)
    end)
    
    it("リクエストがnilの場合エラーを返すこと", function()
      local valid, err = csrf.verify_token(nil, mock_session)
      
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.equals("リクエストが無効です", err)
    end)
    
    it("セッションがnilの場合エラーを返すこと", function()
      local valid, err = csrf.verify_token(mock_req, nil)
      
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.equals("セッションが無効です", err)
    end)
  end)
  
  -- ========================================
  -- リクエストからのトークン抽出テスト
  -- ========================================
  
  describe("リクエストからのトークン抽出", function()
    it("ヘッダー（X-CSRF-Token）からトークンを取得できること", function()
      local test_token = "header_token_12345678901234567890123456789012345678901234567"
      mock_session:set("csrf_token", test_token)
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("小文字のヘッダー（x-csrf-token）からトークンを取得できること", function()
      local test_token = "header_token_12345678901234567890123456789012345678901234567"
      mock_session:set("csrf_token", test_token)
      mock_req.req.headers["x-csrf-token"] = test_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("ボディ（_csrf_token）からトークンを取得できること", function()
      local test_token = "body_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      mock_req.params._csrf_token = test_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("ヘッダーがボディより優先されること", function()
      local header_token = "header_token_1234567890123456789012345678901234567890123456"
      local body_token = "body_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", header_token)
      mock_req.req.headers["X-CSRF-Token"] = header_token
      mock_req.params._csrf_token = body_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_true(valid)
      assert.is_nil(err)
    end)
    
    it("両方が無い場合、falseを返すこと", function()
      local test_token = "session_token_123456789012345678901234567890123456789012345"
      mock_session:set("csrf_token", test_token)
      -- ヘッダーもボディも設定しない
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_false(valid)
      assert.is_not_nil(err)
    end)
  end)
  
  -- ========================================
  -- 定数時間比較のテスト（間接的）
  -- ========================================
  
  describe("定数時間比較", function()
    it("同じ文字列でtrueを返すこと", function()
      local token = "same_token_12345678901234567890123456789012345678901234567890"
      mock_session:set("csrf_token", token)
      mock_req.req.headers["X-CSRF-Token"] = token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_true(valid)
    end)
    
    it("異なる文字列でfalseを返すこと", function()
      local session_token = "token_a_1234567890123456789012345678901234567890123456789012"
      local request_token = "token_b_1234567890123456789012345678901234567890123456789012"
      mock_session:set("csrf_token", session_token)
      mock_req.req.headers["X-CSRF-Token"] = request_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_false(valid)
    end)
    
    it("長さが異なる文字列でfalseを返すこと", function()
      local session_token = "short_token"
      local request_token = "very_long_token_1234567890123456789012345678901234567890123"
      mock_session:set("csrf_token", session_token)
      mock_req.req.headers["X-CSRF-Token"] = request_token
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      assert.is_false(valid)
    end)
    
    it("空文字列を適切に処理すること", function()
      mock_session:set("csrf_token", "")
      mock_req.req.headers["X-CSRF-Token"] = ""
      
      local valid, err = csrf.verify_token(mock_req, mock_session)
      
      -- 空文字列はセッションにトークンがないとみなされる
      assert.is_false(valid)
    end)
  end)
  
  -- ========================================
  -- ミドルウェア保護機能のテスト
  -- ========================================
  
  describe("protect ミドルウェア", function()
    local middleware
    local mock_session_class
    
    before_each(function()
      -- Sessionクラスのモック
      mock_session_class = {
        new = function()
          return mock_session
        end
      }
      
      package.preload["utils.session"] = function()
        return mock_session_class
      end
      
      -- CSRFモジュールとutils.sessionをリロード
      package.loaded["middleware.csrf"] = nil
      package.loaded["utils.session"] = nil
      csrf = require("middleware.csrf")
      
      middleware = csrf.protect()
    end)
    
    it("POST メソッドで検証が実行されること", function()
      local test_token = "valid_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      mock_req.req.method = "POST"
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      middleware(mock_req)
      
      -- 検証成功時はセッションがリクエストに設定される
      assert.equals(mock_session, mock_req.session)
      assert.is_nil(mock_req.response)
    end)
    
    it("PUT メソッドで検証が実行されること", function()
      local test_token = "valid_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      mock_req.req.method = "PUT"
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      middleware(mock_req)
      
      assert.equals(mock_session, mock_req.session)
      assert.is_nil(mock_req.response)
    end)
    
    it("DELETE メソッドで検証が実行されること", function()
      local test_token = "valid_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      mock_req.req.method = "DELETE"
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      middleware(mock_req)
      
      assert.equals(mock_session, mock_req.session)
      assert.is_nil(mock_req.response)
    end)
    
    it("PATCH メソッドで検証が実行されること", function()
      local test_token = "valid_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      mock_req.req.method = "PATCH"
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      middleware(mock_req)
      
      assert.equals(mock_session, mock_req.session)
      assert.is_nil(mock_req.response)
    end)
    
    it("GET メソッドで検証がスキップされること", function()
      mock_req.req.method = "GET"
      -- トークンを設定しない
      
      middleware(mock_req)
      
      -- 検証がスキップされるのでエラーレスポンスは設定されない
      assert.is_nil(mock_req.response)
    end)
    
    it("HEAD メソッドで検証がスキップされること", function()
      mock_req.req.method = "HEAD"
      
      middleware(mock_req)
      
      assert.is_nil(mock_req.response)
    end)
    
    it("OPTIONS メソッドで検証がスキップされること", function()
      mock_req.req.method = "OPTIONS"
      
      middleware(mock_req)
      
      assert.is_nil(mock_req.response)
    end)
    
    it("トークン検証失敗時に403エラーが返ること", function()
      mock_req.req.method = "POST"
      mock_session:set("csrf_token", "valid_token_123456789012345678901234567890123456789012345678")
      mock_req.req.headers["X-CSRF-Token"] = "invalid_token_12345678901234567890123456789012345678901234"
      
      middleware(mock_req)
      
      assert.is_not_nil(mock_req.response)
      assert.equals(403, mock_req.response.status)
      assert.is_not_nil(mock_req.response.json)
      assert.equals("CSRF検証エラー", mock_req.response.json.error)
    end)
    
    it("正しいトークンで処理が継続すること", function()
      local test_token = "valid_token_123456789012345678901234567890123456789012345678"
      mock_session:set("csrf_token", test_token)
      mock_req.req.method = "POST"
      mock_req.req.headers["X-CSRF-Token"] = test_token
      
      middleware(mock_req)
      
      -- エラーレスポンスが設定されていない
      assert.is_nil(mock_req.response)
      -- セッションがリクエストコンテキストに保存されている
      assert.equals(mock_session, mock_req.session)
    end)
    
    it("セッション開始失敗時に403エラーが返ること", function()
      mock_session.start = function(self)
        return false, "セッション開始失敗"
      end
      mock_req.req.method = "POST"
      
      middleware(mock_req)
      
      assert.is_not_nil(mock_req.response)
      assert.equals(403, mock_req.response.status)
      assert.is_not_nil(mock_req.response.json)
      assert.equals("セッションエラー", mock_req.response.json.error)
    end)
  end)
  
  -- ========================================
  -- get_token_endpoint のテスト
  -- ========================================
  
  describe("get_token_endpoint", function()
    local mock_session_class
    
    before_each(function()
      mock_session_class = {
        new = function()
          return mock_session
        end
      }
      
      package.preload["utils.session"] = function()
        return mock_session_class
      end
      
      package.loaded["middleware.csrf"] = nil
      package.loaded["utils.session"] = nil
      csrf = require("middleware.csrf")
    end)
    
    it("CSRFトークンをJSON形式で返すこと", function()
      local response = csrf.get_token_endpoint(mock_req)
      
      assert.is_not_nil(response)
      assert.is_not_nil(response.json)
      assert.is_not_nil(response.json.csrf_token)
      assert.equals(64, #response.json.csrf_token)
    end)
    
    it("既存のトークンがある場合それを返すこと", function()
      local existing_token = "existing_12345678901234567890123456789012345678901234567890"
      mock_session:set("csrf_token", existing_token)
      
      local response = csrf.get_token_endpoint(mock_req)
      
      assert.equals(existing_token, response.json.csrf_token)
    end)
    
    it("セッション開始失敗時に500エラーを返すこと", function()
      mock_session.start = function(self)
        return false, "セッション開始失敗"
      end
      
      local response = csrf.get_token_endpoint(mock_req)
      
      assert.equals(500, response.status)
      assert.is_not_nil(response.json)
      assert.equals("セッションエラー", response.json.error)
    end)
  end)
end)
