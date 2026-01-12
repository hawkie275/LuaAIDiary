-- app/services/cache_service.lua
-- キャッシュ無効化サービス
-- lua_shared_dict を使用してワーカープロセス間でキャッシュバージョンを共有

local M = {}

-- キャッシュバージョンのキー名
local CACHE_VERSION_KEY = "cache_version"

-- 共有辞書を取得
local function get_shared_dict()
    return ngx.shared.cache
end

-- 現在のキャッシュバージョンを取得
function M.get_version()
    local dict = get_shared_dict()
    if not dict then
        return 0
    end
    return dict:get(CACHE_VERSION_KEY) or 0
end

-- 全キャッシュを無効化（バージョンをインクリメント）
function M.invalidate_all()
    local dict = get_shared_dict()
    if not dict then
        ngx.log(ngx.ERR, "Cache invalidation failed: shared dict not available")
        return false
    end

    -- バージョンをインクリメント（アトミック操作）
    local new_version, err = dict:incr(CACHE_VERSION_KEY, 1, 0)
    if not new_version then
        ngx.log(ngx.ERR, "Cache version increment failed: ", err)
        return false
    end

    ngx.log(ngx.INFO, "Page cache invalidated, new version: ", new_version)
    return true
end

return M
