-- ヘルスチェックエンドポイントテスト
describe("Health Check Endpoint", function()
    local http = require("resty.http")
    local cjson = require("cjson")
    
    it("should respond to health check", function()
        local httpc = http.new()
        local res, err = httpc:request_uri("http://web/health", {
            method = "GET"
        })
        
        assert.is_nil(err)
        assert.is_not_nil(res)
        assert.equals(200, res.status)
    end)
    
    it("should return JSON response", function()
        local httpc = http.new()
        local res, err = httpc:request_uri("http://web/health", {
            method = "GET"
        })
        
        assert.is_nil(err)
        assert.is_not_nil(res)
        
        local data = cjson.decode(res.body)
        assert.is_not_nil(data)
    end)
    
    it("should return status ok", function()
        local httpc = http.new()
        local res, err = httpc:request_uri("http://web/health", {
            method = "GET"
        })
        
        assert.is_nil(err)
        assert.is_not_nil(res)
        
        local data = cjson.decode(res.body)
        assert.equals("ok", data.status)
    end)
    
    it("should return service name", function()
        local httpc = http.new()
        local res, err = httpc:request_uri("http://web/health", {
            method = "GET"
        })
        
        assert.is_nil(err)
        assert.is_not_nil(res)
        
        local data = cjson.decode(res.body)
        assert.equals("LuaAIDiary", data.service)
    end)
    
    it("should return timestamp", function()
        local httpc = http.new()
        local res, err = httpc:request_uri("http://web/health", {
            method = "GET"
        })
        
        assert.is_nil(err)
        assert.is_not_nil(res)
        
        local data = cjson.decode(res.body)
        assert.is_not_nil(data.timestamp)
        assert.is_true(data.timestamp > 0)
    end)
end)
