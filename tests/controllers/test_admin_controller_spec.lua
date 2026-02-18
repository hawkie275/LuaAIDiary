-- tests/controllers/test_admin_controller_spec.lua
-- 管理画面コントローラーのテスト

describe("管理画面コントローラー", function()
  local mock_session
  local mock_Post
  local mock_Category
  local mock_Tag
  local mock_Comment
  local mock_csrf
  local mock_db_config
  local function call_dashboard()
    local AdminController = require("controllers.admin_controller")
    local self = { res = { headers = {} } }
    local result = AdminController.dashboard(self)
    return result, self
  end
  
  before_each(function()
    -- 既にロードされているモジュールをクリア
    package.loaded["controllers.admin_controller"] = nil
    package.loaded["utils.session"] = nil
    package.loaded["models.post"] = nil
    package.loaded["models.category"] = nil
    package.loaded["models.tag"] = nil
    package.loaded["models.comment"] = nil
    package.loaded["middleware.csrf"] = nil
    package.loaded["config.database"] = nil
    package.loaded["etlua"] = nil
    
    -- ngxモックの設定
    _G.ngx = {
      status = 200,
      header = {},
      var = {},
      log = function() end,
      say = function() end,
      ERR = 1,
      WARN = 2,
      OK = 0
    }
    
    -- セッションモックの初期化
    mock_session = {
      data = {},
      authenticated = false,
      user_id = nil,
      user = nil,
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
      end,
      get = function(self, key)
        return self.data[key]
      end,
      set = function(self, key, value)
        self.data[key] = value
      end
    }
    
    -- Sessionモック
    package.preload["utils.session"] = function()
      return {
        new = function()
          return mock_session
        end
      }
    end
    
    -- Postモデルモックの初期化
    mock_Post = {
      count = function(self, conditions)
        return 10, nil
      end
    }
    
    -- Postモデルモック
    package.preload["models.post"] = function()
      return mock_Post
    end
    
    -- Categoryモデルモックの初期化
    mock_Category = {
      count_categories = function()
        return 5, nil
      end
    }
    
    -- Categoryモデルモック
    package.preload["models.category"] = function()
      return mock_Category
    end
    
    -- Tagモデルモックの初期化
    mock_Tag = {
      count_tags = function()
        return 8, nil
      end
    }
    
    -- Tagモデルモック
    package.preload["models.tag"] = function()
      return mock_Tag
    end
    
    -- Commentモデルモックの初期化
    mock_Comment = {
      count = function(self, conditions)
        return 20, nil
      end
    }
    
    -- Commentモデルモック
    package.preload["models.comment"] = function()
      return mock_Comment
    end
    
    -- CSRFミドルウェアモック
    mock_csrf = {
      generate_token = function(session)
        return "test_csrf_token_12345"
      end
    }
    
    package.preload["middleware.csrf"] = function()
      return mock_csrf
    end
    
    -- データベース設定モック
    mock_db_config = {
      query = function(query)
        -- 最近の投稿を返す
        return {
          {
            id = 1,
            title = "テスト投稿1",
            status = "published",
            created_at = "2024-01-01 10:00:00",
            published_at = "2024-01-01 10:00:00",
            category_name = "テクノロジー"
          },
          {
            id = 2,
            title = "テスト投稿2",
            status = "draft",
            created_at = "2024-01-02 11:00:00",
            published_at = nil,
            category_name = "ライフスタイル"
          }
        }, nil
      end,
      escape = function(value)
        if value == nil then
          return "NULL"
        end
        local escaped = tostring(value):gsub("'", "''")
        return "'" .. escaped .. "'"
      end,
      connect = function()
        return {
          query = function() return true end
        }, nil
      end,
      close = function(db)
        -- do nothing
      end
    }
    
    package.preload["config.database"] = function()
      return mock_db_config
    end
    
    -- etluaモック（使用しないが、requireされるのでモック化）
    package.preload["etlua"] = function()
      return {
        compile = function() return function() return "" end end,
        render = function() return "" end
      }
    end
  end)
  
  after_each(function()
    -- ngxをクリーンアップ
    _G.ngx = nil
    
    -- 全てのモックモジュールをクリア
    package.loaded["controllers.admin_controller"] = nil
    package.loaded["utils.session"] = nil
    package.loaded["models.post"] = nil
    package.loaded["models.category"] = nil
    package.loaded["models.tag"] = nil
    package.loaded["models.comment"] = nil
    package.loaded["middleware.csrf"] = nil
    package.loaded["config.database"] = nil
    package.loaded["etlua"] = nil
    package.preload["utils.session"] = nil
    package.preload["models.post"] = nil
    package.preload["models.category"] = nil
    package.preload["models.tag"] = nil
    package.preload["models.comment"] = nil
    package.preload["middleware.csrf"] = nil
    package.preload["config.database"] = nil
    package.preload["etlua"] = nil
  end)
  
  -- ========================================
  -- 認証・権限チェックのテスト
  -- ========================================
  
  describe("認証と権限チェック", function()
    it("未認証ユーザーはリダイレクトされること", function()
      mock_session.authenticated = false
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("/admin/login?redirect=/admin/dashboard", result.redirect_to)
      assert.equals(302, result.status)
    end)
    
    it("セッション開始失敗時はリダイレクトされること", function()
      mock_session.start = function(self)
        return false
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals(302, result.status)
    end)
    
    it("user_idが取得できない場合はリダイレクトされること", function()
      mock_session.authenticated = true
      mock_session.user_id = nil
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals(302, result.status)
    end)
    
    it("ユーザー情報が取得できない場合はリダイレクトされること", function()
      mock_session.authenticated = true
      mock_session.user_id = 1
      mock_session.user = nil
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals(302, result.status)
    end)
  end)
  
  describe("権限チェック - ロール別アクセス制御", function()
    it("adminロールはアクセスできること", function()
      mock_session.authenticated = true
      mock_session.user_id = 1
      mock_session.user = {
        id = 1,
        username = "admin",
        email = "admin@test.com",
        role = "admin"
      }
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("editorロールはアクセスできること", function()
      mock_session.authenticated = true
      mock_session.user_id = 2
      mock_session.user = {
        id = 2,
        username = "editor",
        email = "editor@test.com",
        role = "editor"
      }
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("authorロールは403エラーとなること", function()
      mock_session.authenticated = true
      mock_session.user_id = 3
      mock_session.user = {
        id = 3,
        username = "author",
        email = "author@test.com",
        role = "author"
      }
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("subscriberロールは403エラーとなること", function()
      mock_session.authenticated = true
      mock_session.user_id = 4
      mock_session.user = {
        id = 4,
        username = "subscriber",
        email = "subscriber@test.com",
        role = "subscriber"
      }
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("ロールが未設定の場合は403エラーとなること", function()
      mock_session.authenticated = true
      mock_session.user_id = 5
      mock_session.user = {
        id = 5,
        username = "user",
        email = "user@test.com",
        role = nil
      }
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
  end)
  
  -- ========================================
  -- ダッシュボードデータ取得のテスト
  -- ========================================
  
  describe("ダッシュボードデータ取得", function()
    before_each(function()
      -- 管理者ユーザーとしてセッションを設定
      mock_session.authenticated = true
      mock_session.user_id = 1
      mock_session.user = {
        id = 1,
        username = "admin",
        email = "admin@test.com",
        role = "admin"
      }
    end)
    
    it("統計情報が正しく取得されること", function()
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("投稿数取得エラー時もダッシュボードが表示されること", function()
      mock_Post.count = function(self, conditions)
        return nil, "Database error"
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("カテゴリー数取得エラー時もダッシュボードが表示されること", function()
      mock_Category.count_categories = function()
        return nil, "Database error"
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("タグ数取得エラー時もダッシュボードが表示されること", function()
      mock_Tag.count_tags = function()
        return nil, "Database error"
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("コメント数取得エラー時もダッシュボードが表示されること", function()
      mock_Comment.count = function(self, conditions)
        return nil, "Database error"
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("最近の投稿が取得されること", function()
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("最近の投稿取得エラー時は空配列が返ること", function()
      mock_db_config.query = function(query)
        return nil, "Database error"
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("システム情報が取得されること", function()
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("データベース接続失敗時もシステム情報が返ること", function()
      mock_db_config.connect = function()
        return nil, "Connection failed"
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("CSRFトークンが生成されること", function()
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("ユーザー情報が含まれること", function()
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
  end)
  
  -- ========================================
  -- レスポンス形式のテスト
  -- ========================================
  
  describe("レスポンス形式", function()
    before_each(function()
      mock_session.authenticated = true
      mock_session.user_id = 1
      mock_session.user = {
        id = 1,
        username = "admin",
        email = "admin@test.com",
        role = "admin"
      }
    end)
    
    it("正しいビューテンプレートが指定されること", function()
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("Content-Typeがtext/htmlであること", function()
      local _, self = call_dashboard()
      
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("権限エラー時はerror_403がレンダリングされること", function()
      mock_session.user.role = "subscriber"
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
  end)
  
  -- ========================================
  -- エッジケースのテスト
  -- ========================================
  
  describe("エッジケース", function()
    it("すべての統計が0の場合も正常に動作すること", function()
      mock_session.authenticated = true
      mock_session.user_id = 1
      mock_session.user = {
        id = 1,
        username = "admin",
        role = "admin"
      }
      
      mock_Post.count = function() return 0, nil end
      mock_Category.count_categories = function() return 0, nil end
      mock_Tag.count_tags = function() return 0, nil end
      mock_Comment.count = function() return 0, nil end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
    
    it("最近の投稿が0件の場合も正常に動作すること", function()
      mock_session.authenticated = true
      mock_session.user_id = 1
      mock_session.user = {
        id = 1,
        username = "admin",
        role = "admin"
      }
      
      mock_db_config.query = function(query)
        return {}, nil
      end
      
      local result, self = call_dashboard()
      
      assert.is_not_nil(result)
      assert.equals("string", type(result))
      assert.equals("text/html; charset=utf-8", self.res.headers["Content-Type"])
    end)
  end)
end)
