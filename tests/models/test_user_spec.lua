-- ユーザーモデルのテスト

describe("ユーザーモデル", function()
    local User
    local crypto
    
    setup(function()
        -- Luaパスを設定
        package.path = '/app/?.lua;/app/?/init.lua;' .. package.path
        User = require("models.user")
        crypto = require("utils.crypto")
    end)
    
    describe("ユーザー作成", function()
        it("正しいデータでユーザーを作成できる", function()
            local user_data = {
                username = "testuser",
                email = "test@example.com",
                password = "password123",
                display_name = "Test User",
                role = "subscriber"
            }
            
            local user_id, err = User.create_user(user_data)
            assert.is_not_nil(user_id)
            assert.is_nil(err)
            
            -- クリーンアップ
            User:delete(user_id)
        end)
        
        it("無効なメールアドレスで失敗する", function()
            local user_data = {
                username = "testuser",
                email = "invalid-email",
                password = "password123"
            }
            
            local user_id, err = User.create_user(user_data)
            assert.is_nil(user_id)
            assert.is_not_nil(err)
        end)
        
        it("短いパスワードで失敗する", function()
            local user_data = {
                username = "testuser",
                email = "test@example.com",
                password = "short"
            }
            
            local user_id, err = User.create_user(user_data)
            assert.is_nil(user_id)
            assert.is_not_nil(err)
        end)
    end)
    
    describe("認証", function()
        local test_user_id
        
        before_each(function()
            local user_data = {
                username = "authtest",
                email = "auth@example.com",
                password = "password123"
            }
            test_user_id = User.create_user(user_data)
        end)
        
        after_each(function()
            if test_user_id then
                User:delete(test_user_id)
            end
        end)
        
        it("正しいパスワードで認証できる", function()
            local user, err = User.authenticate("authtest", "password123")
            assert.is_not_nil(user)
            assert.is_nil(err)
            assert.equals("authtest", user.username)
        end)
        
        it("間違ったパスワードで認証失敗する", function()
            local user, err = User.authenticate("authtest", "wrongpassword")
            assert.is_nil(user)
            assert.is_not_nil(err)
        end)
    end)
    
    describe("ロール管理", function()
        local test_user_id
        
        before_each(function()
            local user_data = {
                username = "roletest",
                email = "role@example.com",
                password = "password123",
                role = "subscriber"
            }
            test_user_id = User.create_user(user_data)
        end)
        
        after_each(function()
            if test_user_id then
                User:delete(test_user_id)
            end
        end)
        
        it("ロールを変更できる", function()
            local ok, err = User.change_role(test_user_id, "author")
            assert.is_true(ok)
            assert.is_nil(err)
            
            local user = User:find(test_user_id)
            assert.equals("author", user.role)
        end)
        
        it("管理者権限を確認できる", function()
            User.change_role(test_user_id, "admin")
            local is_admin = User.is_admin(test_user_id)
            assert.is_true(is_admin)
        end)
    end)
end)
