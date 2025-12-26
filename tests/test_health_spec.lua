-- ヘルスチェックエンドポイントテスト
describe("Health Check Endpoint", function()
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local cjson = require("cjson")
    
    local function http_get(url)
        local response_body = {}
        local res, code, response_headers = http.request({
            url = url,
            sink = ltn12.sink.table(response_body)
        })
        return table.concat(response_body), code, response_headers
    end
    
    it("should respond to health check", function()
        local body, code = http_get("http://localhost/health")
        assert.is_not_nil(body)
        assert.equals(200, code)
    end)
    
    it("should return JSON response", function()
        local body, code = http_get("http://localhost/health")
        assert.equals(200, code)
        
        local success, data = pcall(cjson.decode, body)
        assert.is_true(success)
        assert.is_not_nil(data)
    end)
    
    it("should return status ok", function()
        local body, code = http_get("http://localhost/health")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.equals("ok", data.status)
    end)
    
    it("should return service name", function()
        local body, code = http_get("http://localhost/health")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.equals("LuaAIDiary", data.service)
    end)
    
    it("should return version", function()
        local body, code = http_get("http://localhost/health")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.is_not_nil(data.version)
    end)
    
    it("should return timestamp", function()
        local body, code = http_get("http://localhost/health")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.is_not_nil(data.timestamp)
        assert.is_true(data.timestamp > 0)
    end)
end)

describe("Database Test Endpoint", function()
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local cjson = require("cjson")
    
    local function http_get(url)
        local response_body = {}
        local res, code, response_headers = http.request({
            url = url,
            sink = ltn12.sink.table(response_body)
        })
        return table.concat(response_body), code, response_headers
    end
    
    it("should connect to database successfully", function()
        local body, code = http_get("http://localhost/api/db-test")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.equals("success", data.status)
    end)
    
    it("should return PostgreSQL version", function()
        local body, code = http_get("http://localhost/api/db-test")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.is_not_nil(data.postgres_version)
    end)
    
    it("should return database name", function()
        local body, code = http_get("http://localhost/api/db-test")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.equals("luaaidiary", data.database)
    end)
end)

describe("Redis Test Endpoint", function()
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local cjson = require("cjson")
    
    local function http_get(url)
        local response_body = {}
        local res, code, response_headers = http.request({
            url = url,
            sink = ltn12.sink.table(response_body)
        })
        return table.concat(response_body), code, response_headers
    end
    
    it("should connect to Redis successfully", function()
        local body, code = http_get("http://localhost/api/redis-test")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.equals("success", data.status)
    end)
    
    it("should receive PONG response", function()
        local body, code = http_get("http://localhost/api/redis-test")
        assert.equals(200, code)
        
        local data = cjson.decode(body)
        assert.equals("PONG", data.response)
    end)
end)