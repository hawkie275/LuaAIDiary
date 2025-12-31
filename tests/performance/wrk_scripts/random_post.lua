-- ========================================
-- wrk Luaスクリプト: ランダム記事アクセス
-- ========================================
-- このスクリプトは、1-100の記事IDからランダムに選択して
-- アクセスすることで、実際のユーザー行動をシミュレートします

-- 乱数シードの初期化（スレッドごとに異なるシードを使用）
math.randomseed(os.time() + id)

-- 記事IDの範囲
local min_post_id = 1
local max_post_id = 100

-- グローバル変数（統計用）
local stats = {
    total_requests = 0,
    errors = 0,
    status_codes = {}
}

-- スレッド初期化時に実行
function setup(thread)
    thread:set("id", id)
    -- 各スレッドで異なる乱数シードを使用
    math.randomseed(os.time() + id)
end

-- リクエスト生成
request = function()
    -- ランダムな記事IDを生成
    local post_id = math.random(min_post_id, max_post_id)
    
    -- URLパスを構築（プラットフォームに応じて調整）
    -- LuaAIDiary: /posts/{id} または slug形式
    -- WordPress: /?p={id}
    local path = string.format("/posts/%d", post_id)
    
    -- リクエスト統計をカウント
    stats.total_requests = stats.total_requests + 1
    
    -- GETリクエストを生成
    return wrk.format("GET", path)
end

-- レスポンス処理（オプション）
response = function(status, headers, body)
    -- ステータスコードを記録
    if stats.status_codes[status] == nil then
        stats.status_codes[status] = 0
    end
    stats.status_codes[status] = stats.status_codes[status] + 1
    
    -- エラーレスポンスをカウント
    if status >= 400 then
        stats.errors = stats.errors + 1
    end
end

-- テスト完了時に実行
done = function(summary, latency, requests)
    -- 統計情報を出力
    io.write("\n")
    io.write("========================================\n")
    io.write("ランダム記事アクセス統計\n")
    io.write("========================================\n")
    io.write(string.format("総リクエスト数: %d\n", stats.total_requests))
    io.write(string.format("エラー数: %d\n", stats.errors))
    io.write(string.format("エラー率: %.2f%%\n", (stats.errors / stats.total_requests) * 100))
    io.write("\nステータスコード分布:\n")
    
    for status, count in pairs(stats.status_codes) do
        io.write(string.format("  %d: %d (%.2f%%)\n", 
            status, count, (count / stats.total_requests) * 100))
    end
    
    io.write("========================================\n")
    
    -- レイテンシ統計（wrkの組み込みデータ）
    io.write("\nレイテンシ統計:\n")
    io.write(string.format("  最小: %.2fms\n", latency.min / 1000))
    io.write(string.format("  最大: %.2fms\n", latency.max / 1000))
    io.write(string.format("  平均: %.2fms\n", latency.mean / 1000))
    io.write(string.format("  標準偏差: %.2fms\n", latency.stdev / 1000))
    
    io.write("\nパーセンタイル:\n")
    for _, p in pairs({50, 75, 90, 95, 99, 99.9}) do
        local n = latency:percentile(p)
        io.write(string.format("  %g%%: %.2fms\n", p, n / 1000))
    end
    
    io.write("========================================\n")
end
