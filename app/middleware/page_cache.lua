-- app/middleware/page_cache.lua
-- ページキャッシュミドルウェア - パフォーマンス改善のためのレスポンスキャッシュ

local lrucache = require "resty.lrucache"
local cjson = require "cjson"

local M = {}

-- ========================================
-- キャッシュインスタンスの初期化
-- ========================================

-- LRUキャッシュインスタンス（1000アイテム）
-- TTLは個別に設定可能
M.cache = lrucache.new(1000)

if not M.cache then
  ngx.log(ngx.ERR, "ページキャッシュ: LRUキャッシュの初期化に失敗しました")
end

-- キャッシュキーのプレフィックス（無効化パターンマッチング用）
local CACHE_KEY_PREFIX = "page_cache:"

-- ========================================
-- キャッシュキー生成
-- ========================================

-- リクエストのURIとクエリパラメータからキャッシュキーを生成
-- @param uri string リクエストURI
-- @param args table クエリパラメータ（オプション）
-- @return string キャッシュキー
function M.generate_cache_key(uri, args)
  if not uri then
    ngx.log(ngx.ERR, "ページキャッシュ: URIが指定されていません")
    return nil
  end
  
  local key = CACHE_KEY_PREFIX .. uri
  
  -- クエリパラメータがある場合は追加
  if args and type(args) == "table" and next(args) then
    -- パラメータをソートして一貫性のあるキーを生成
    local sorted_params = {}
    for k, v in pairs(args) do
      table.insert(sorted_params, k .. "=" .. tostring(v))
    end
    table.sort(sorted_params)
    
    key = key .. "?" .. table.concat(sorted_params, "&")
  end
  
  return key
end

-- ========================================
-- キャッシュ可能パスの判定
-- ========================================

-- リクエストがキャッシュ可能かどうかを判定
-- @param uri string リクエストURI
-- @param method string HTTPメソッド
-- @return boolean キャッシュ可能な場合true
function M.is_cacheable(uri, method)
  if not uri or not method then
    return false
  end
  
  -- GETリクエストのみキャッシュ対象
  if method ~= "GET" then
    ngx.log(ngx.DEBUG, "ページキャッシュ: ", method, " リクエストはキャッシュ対象外です")
    return false
  end
  
  -- 管理画面はキャッシュ対象外
  if string.match(uri, "^/admin") then
    ngx.log(ngx.DEBUG, "ページキャッシュ: 管理画面はキャッシュ対象外です: ", uri)
    return false
  end
  
  -- 認証関連はキャッシュ対象外
  if string.match(uri, "^/auth") then
    ngx.log(ngx.DEBUG, "ページキャッシュ: 認証関連はキャッシュ対象外です: ", uri)
    return false
  end
  
  -- API エンドポイントはキャッシュ対象外（認証が必要な可能性があるため）
  if string.match(uri, "^/api") then
    ngx.log(ngx.DEBUG, "ページキャッシュ: APIエンドポイントはキャッシュ対象外です: ", uri)
    return false
  end
  
  -- キャッシュ対象のパス
  -- トップページ
  if uri == "/" then
    return true
  end
  
  -- 個別記事ページ (/posts/:slug)
  if string.match(uri, "^/posts/[^/]+$") then
    return true
  end
  
  -- カテゴリーページ (/category/:slug)
  if string.match(uri, "^/category/[^/]+$") then
    return true
  end
  
  -- タグページ (/tag/:slug)
  if string.match(uri, "^/tag/[^/]+$") then
    return true
  end
  
  -- その他はキャッシュ対象外
  ngx.log(ngx.DEBUG, "ページキャッシュ: 対象外のパス: ", uri)
  return false
end

-- ========================================
-- ミドルウェア関数
-- ========================================

-- ページキャッシュミドルウェアを生成
-- @param ttl number キャッシュのTTL（秒）デフォルト: 300秒（5分）
-- @return function ミドルウェア関数
function M.cache_middleware(ttl)
  ttl = ttl or 300 -- デフォルトTTL: 5分
  
  return function(self)
    -- キャッシュが初期化されていない場合はスキップ
    if not M.cache then
      ngx.log(ngx.WARN, "ページキャッシュ: キャッシュが初期化されていません")
      return
    end
    
    -- HTTPメソッドとURIを取得
    local method = self.req.method or ngx.req.get_method()
    local uri = self.req.parsed_url.path or ngx.var.uri
    
    -- キャッシュ可能かチェック
    if not M.is_cacheable(uri, method) then
      return -- キャッシュ対象外の場合は次の処理へ
    end
    
    -- クエリパラメータを取得
    local args = ngx.req.get_uri_args()
    
    -- キャッシュキーを生成
    local cache_key = M.generate_cache_key(uri, args)
    if not cache_key then
      ngx.log(ngx.ERR, "ページキャッシュ: キャッシュキー生成に失敗しました")
      return
    end
    
    -- キャッシュから取得を試みる
    local cached_data = M.cache:get(cache_key)
    
    if cached_data then
      -- キャッシュヒット
      ngx.log(ngx.INFO, "ページキャッシュ: HIT - ", cache_key)
      
      -- キャッシュされたレスポンスをデコード
      local success, response = pcall(cjson.decode, cached_data)
      if not success then
        ngx.log(ngx.ERR, "ページキャッシュ: デコードエラー: ", response)
        -- キャッシュが破損している場合は削除
        M.cache:delete(cache_key)
        return
      end
      
      -- X-Cache: HIT ヘッダーを追加
      ngx.header["X-Cache"] = "HIT"
      
      -- Content-Typeヘッダーを設定
      if response.content_type then
        ngx.header["Content-Type"] = response.content_type
      end
      
      -- その他のヘッダーを設定
      if response.headers then
        for k, v in pairs(response.headers) do
          ngx.header[k] = v
        end
      end
      
      -- キャッシュされたレスポンスを返す
      self:write({
        status = response.status or 200,
        layout = false, -- レイアウトをスキップ
        response.body
      })
      
      return
    end
    
    -- キャッシュミス
    ngx.log(ngx.INFO, "ページキャッシュ: MISS - ", cache_key)
    
    -- 元のレスポンスをキャプチャするためのフック
    -- before_filterの後、実際のハンドラが実行される
    -- after_filterでレスポンスをキャッシュする
    
    -- X-Cache: MISS ヘッダーを追加（after_filterで設定）
    self._cache_key = cache_key
    self._cache_ttl = ttl
    self._cache_miss = true
  end
end

-- レスポンスをキャッシュするための after_filter 用関数
-- @param ttl number キャッシュのTTL（秒）
-- @return function after_filter関数
function M.cache_response()
  return function(self)
    -- キャッシュミスフラグがない場合はスキップ
    if not self._cache_miss or not self._cache_key then
      return
    end
    
    -- キャッシュが初期化されていない場合はスキップ
    if not M.cache then
      return
    end
    
    -- X-Cache: MISS ヘッダーを追加
    ngx.header["X-Cache"] = "MISS"
    
    -- レスポンスのステータスコードを確認
    local status = self.res.status or ngx.status or 200
    
    -- 成功レスポンス（200 OK）のみキャッシュ
    if status ~= 200 then
      ngx.log(ngx.DEBUG, "ページキャッシュ: ステータス ", status, " のレスポンスはキャッシュしません")
      return
    end
    
    -- レスポンスボディを取得
    local body = self.res.content
    if not body or body == "" then
      ngx.log(ngx.DEBUG, "ページキャッシュ: レスポンスボディが空です")
      return
    end
    
    -- キャッシュするデータを構築
    local cache_data = {
      status = status,
      body = body,
      content_type = ngx.header["Content-Type"] or "text/html",
      headers = {}
    }
    
    -- 必要なヘッダーをコピー（X-Cache以外）
    for k, v in pairs(ngx.header) do
      if k ~= "X-Cache" and k ~= "Set-Cookie" then
        cache_data.headers[k] = v
      end
    end
    
    -- JSONエンコード
    local success, encoded = pcall(cjson.encode, cache_data)
    if not success then
      ngx.log(ngx.ERR, "ページキャッシュ: エンコードエラー: ", encoded)
      return
    end
    
    -- キャッシュに保存（TTL付き）
    local ok, err = M.cache:set(self._cache_key, encoded, self._cache_ttl)
    if not ok then
      ngx.log(ngx.ERR, "ページキャッシュ: キャッシュ保存エラー: ", err or "unknown")
      return
    end
    
    ngx.log(ngx.INFO, "ページキャッシュ: 保存成功 - ", self._cache_key, " (TTL: ", self._cache_ttl, "秒)")
  end
end

-- ========================================
-- キャッシュ無効化API
-- ========================================

-- パターンマッチでキャッシュを無効化
-- @param pattern string マッチパターン（Luaパターン）
-- @return number 無効化されたキャッシュ数
function M.invalidate_cache(pattern)
  if not M.cache then
    ngx.log(ngx.WARN, "ページキャッシュ: キャッシュが初期化されていません")
    return 0
  end
  
  if not pattern or pattern == "" then
    ngx.log(ngx.ERR, "ページキャッシュ: パターンが指定されていません")
    return 0
  end
  
  local count = 0
  
  -- Note: lua-resty-lrucache はキーのイテレーションをサポートしていないため、
  -- 完全なパターンマッチングによる無効化は実装が困難です。
  -- 代わりに、特定のキーを直接削除する方法を使用することを推奨します。
  -- ここでは、将来の拡張のためのプレースホルダーとして実装します。
  
  ngx.log(ngx.WARN, "ページキャッシュ: パターンマッチング無効化は現在サポートされていません: ", pattern)
  ngx.log(ngx.INFO, "ページキャッシュ: 代わりに invalidate_all() を使用するか、特定のキーを削除してください")
  
  return count
end

-- 特定のURIのキャッシュを無効化
-- @param uri string 無効化するURI
-- @param args table クエリパラメータ（オプション）
-- @return boolean 成功した場合true
function M.invalidate_uri(uri, args)
  if not M.cache then
    ngx.log(ngx.WARN, "ページキャッシュ: キャッシュが初期化されていません")
    return false
  end
  
  local cache_key = M.generate_cache_key(uri, args)
  if not cache_key then
    return false
  end
  
  M.cache:delete(cache_key)
  ngx.log(ngx.INFO, "ページキャッシュ: 無効化 - ", cache_key)
  
  return true
end

-- すべてのキャッシュをクリア
-- @return boolean 成功した場合true
function M.invalidate_all()
  if not M.cache then
    ngx.log(ngx.WARN, "ページキャッシュ: キャッシュが初期化されていません")
    return false
  end
  
  -- 新しいキャッシュインスタンスを作成して置き換える
  M.cache = lrucache.new(1000)
  
  if not M.cache then
    ngx.log(ngx.ERR, "ページキャッシュ: キャッシュの再初期化に失敗しました")
    return false
  end
  
  ngx.log(ngx.INFO, "ページキャッシュ: すべてのキャッシュをクリアしました")
  
  return true
end

-- ========================================
-- ヘルパー関数
-- ========================================

-- キャッシュ統計情報を取得
-- @return table キャッシュ統計
function M.get_stats()
  if not M.cache then
    return {
      initialized = false,
      error = "キャッシュが初期化されていません"
    }
  end
  
  -- lua-resty-lrucacheは統計情報を提供しないため、基本情報のみ返す
  return {
    initialized = true,
    max_items = 1000,
    note = "LRUキャッシュは詳細な統計情報を提供しません"
  }
end

return M
