#!/bin/bash

# ========================================
# 性能ベンチマークスクリプト
# WordPress vs LuaAIDiary 性能比較テスト
# ========================================

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# デフォルト設定
PLATFORM="${1:-luaaidiary}"  # luaaidiary or wordpress
DURATION="${2:-60}"          # テスト時間（秒）
WARMUP_DURATION=30           # ウォームアップ時間（秒）

# URL設定
if [ "$PLATFORM" = "wordpress" ]; then
    BASE_URL="http://localhost:8081"
    RESULTS_DIR="tests/performance/results/wordpress"
elif [ "$PLATFORM" = "luaaidiary" ]; then
    BASE_URL="http://localhost:8080"
    RESULTS_DIR="tests/performance/results/luaaidiary"
else
    echo -e "${RED}エラー: 不明なプラットフォーム: $PLATFORM${NC}"
    echo "使用方法: $0 [luaaidiary|wordpress] [duration_seconds]"
    exit 1
fi

# 結果ディレクトリ作成
mkdir -p "$RESULTS_DIR"

# タイムスタンプ
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ログファイル
LOG_FILE="$RESULTS_DIR/benchmark_${TIMESTAMP}.log"

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# wrkコマンドの確認
check_wrk() {
    if ! command -v wrk &> /dev/null; then
        log_error "wrk がインストールされていません"
        log_info "インストール方法:"
        log_info "  Ubuntu/Debian: sudo apt-get install wrk"
        log_info "  または: git clone https://github.com/wg/wrk.git && cd wrk && make && sudo cp wrk /usr/local/bin/"
        exit 1
    fi
    log_success "wrk が見つかりました: $(wrk --version 2>&1 | head -1)"
}

# サービスの確認
check_service() {
    log_info "サービスの疎通確認: $BASE_URL"
    
    if curl -s -f "${BASE_URL}/health" > /dev/null 2>&1 || curl -s -f "${BASE_URL}/" > /dev/null 2>&1; then
        log_success "サービスが応答しました"
        return 0
    else
        log_error "サービスが応答しません: $BASE_URL"
        log_info "サービスが起動していることを確認してください"
        if [ "$PLATFORM" = "luaaidiary" ]; then
            log_info "  起動: cd /home/yagi/github/LuaAIDiary && make up"
        else
            log_info "  起動: cd /home/yagi/wordpress_test && docker compose up -d"
        fi
        exit 1
    fi
}

# ウォームアップ
warmup() {
    log_info "ウォームアップを開始します (${WARMUP_DURATION}秒)..."
    wrk -t2 -c10 -d${WARMUP_DURATION}s "$BASE_URL/" > /dev/null 2>&1
    log_success "ウォームアップが完了しました"
    sleep 5
}

# ベンチマーク実行
run_benchmark() {
    local scenario=$1
    local threads=$2
    local connections=$3
    local url=$4
    local script=${5:-}
    
    local output_file="$RESULTS_DIR/${scenario}_t${threads}_c${connections}_${TIMESTAMP}.txt"
    
    log_info "シナリオ: $scenario (スレッド:$threads, 接続:$connections, 時間:${DURATION}秒)"
    
    if [ -n "$script" ]; then
        wrk -t$threads -c$connections -d${DURATION}s --latency -s "$script" "$url" > "$output_file" 2>&1
    else
        wrk -t$threads -c$connections -d${DURATION}s --latency "$url" > "$output_file" 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_success "完了: $output_file"
        # 結果のサマリーを表示
        echo ""
        grep -E "(Requests/sec|Latency|Transfer/sec)" "$output_file" | tee -a "$LOG_FILE"
        echo ""
    else
        log_error "ベンチマーク実行に失敗しました"
    fi
    
    # クールダウン
    sleep 10
}

# メイン処理
main() {
    echo "========================================"
    echo "  性能ベンチマーク実行"
    echo "========================================"
    echo "プラットフォーム: $PLATFORM"
    echo "URL: $BASE_URL"
    echo "テスト時間: ${DURATION}秒"
    echo "結果保存先: $RESULTS_DIR"
    echo "========================================"
    echo ""
    
    # 事前チェック
    check_wrk
    check_service
    
    # ウォームアップ
    warmup
    
    log_info "ベンチマークを開始します..."
    echo ""
    
    # シナリオ1: トップページ（段階的負荷）
    log_info "=== シナリオ1: トップページ ==="
    run_benchmark "scenario1_home" 4 100 "$BASE_URL/"
    run_benchmark "scenario1_home" 8 200 "$BASE_URL/"
    run_benchmark "scenario1_home" 12 400 "$BASE_URL/"
    
    # シナリオ2: 単一記事表示（ランダムアクセス）
    if [ -f "tests/performance/wrk_scripts/random_post.lua" ]; then
        log_info "=== シナリオ2: ランダム記事アクセス ==="
        run_benchmark "scenario2_random_posts" 8 200 "$BASE_URL/" "tests/performance/wrk_scripts/random_post.lua"
    else
        log_warning "random_post.lua が見つかりません。シナリオ2をスキップします"
    fi
    
    # シナリオ3: ヘルスチェックエンドポイント（最小レイテンシ測定）
    if [ "$PLATFORM" = "luaaidiary" ]; then
        log_info "=== シナリオ3: ヘルスチェック（最小レイテンシ） ==="
        run_benchmark "scenario3_health" 8 200 "${BASE_URL}/health"
    fi
    
    # 完了
    echo ""
    log_success "すべてのベンチマークが完了しました"
    log_info "結果は以下のディレクトリに保存されています:"
    log_info "  $RESULTS_DIR"
    echo ""
    
    # サマリーファイル生成
    SUMMARY_FILE="$RESULTS_DIR/summary_${TIMESTAMP}.txt"
    {
        echo "========================================"
        echo "ベンチマーク結果サマリー"
        echo "========================================"
        echo "プラットフォーム: $PLATFORM"
        echo "実行日時: $(date)"
        echo "テスト時間: ${DURATION}秒/シナリオ"
        echo "========================================"
        echo ""
        
        for result_file in "$RESULTS_DIR"/*_${TIMESTAMP}.txt; do
            if [ -f "$result_file" ]; then
                echo "--- $(basename "$result_file") ---"
                grep -E "(Requests/sec|Latency|Transfer/sec)" "$result_file" || echo "データなし"
                echo ""
            fi
        done
    } > "$SUMMARY_FILE"
    
    log_info "サマリー: $SUMMARY_FILE"
    cat "$SUMMARY_FILE"
}

# スクリプト実行
main
