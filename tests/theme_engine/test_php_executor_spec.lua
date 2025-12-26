-- PHPエグゼキューターのテスト

describe("PHP Executor", function()
    local php_executor
    
    setup(function()
        -- ngxのモック
        _G.ngx = {
            log = function() end,
            ERR = 1,
            WARN = 2,
            INFO = 3,
            var = {},
            req = {
                get_method = function() return "GET" end
            }
        }
        
        php_executor = require "theme_engine.php_executor"
    end)
    
    teardown(function()
        -- モックをクリーンアップ
        _G.ngx = nil
        package.loaded["theme_engine.php_executor"] = nil
    end)
    
    describe("PHP変数の展開", function()
        it("should expand PHP variables", function()
            local php_code = "<?php $name = 'Test'; echo $name; ?>"
            local context = {}
            
            local output, err = php_executor.execute_php_code(php_code, context)
            
            -- 変数展開が動作することを確認
            assert.is_not_nil(output)
            assert.is_nil(err)
        end)
    end)
    
    describe("PHPとHTMLの混在", function()
        it("should process mixed PHP and HTML", function()
            local php_code = "<h1>Hello</h1><?php echo 'World'; ?>"
            local context = {}
            
            local output, err = php_executor.execute_php_code(php_code, context)
            
            assert.is_not_nil(output)
            assert.is_nil(err)
            assert.has_match("Hello", output)
        end)
    end)
    
    describe("ショートタグのサポート", function()
        it("should support short echo tag", function()
            local php_code = "<?= 'test' ?>"
            local context = {}
            
            local output, err = php_executor.execute_php_code(php_code, context)
            
            assert.is_not_nil(output)
        end)
    end)
    
    describe("危険な関数の制限", function()
        it("should detect dangerous functions", function()
            local is_safe = php_executor.check_dangerous_function("eval")
            assert.is_false(is_safe)
            
            is_safe = php_executor.check_dangerous_function("echo")
            assert.is_true(is_safe)
        end)
    end)
end)
