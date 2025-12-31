#!/bin/bash

# ========================================
# リソース監視スクリプト
# Docker Stats を使用したリソース監視
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
DURATION="${2:-300}"         # 監視時間（秒）デフォルト5分
INTERVAL="${3:-5}"           # サンプリング間隔（秒）

# 結果ディレクトリ
RESULTS_DIR="tests/performance/results"
mkdir -p "$RESULTS_DIR"

# タイムスタンプ
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 出力ファイル
CSV_FILE="$RESULTS_DIR/${PLATFORM}_resources_${TIMESTAMP}.csv"
LOG_FILE="$RESULTS_DIR/${PLATFORM}_monitor_${TIMESTAMP}.log"

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

# コンテナ名のパターン設定
if [ "$PLATFORM" = "wordpress" ]; then
    CONTAINER_PATTERN="wordpress"
elif [ "$PLATFORM" = "luaaidiary" ]; then
    CONTAINER_PATTERN="luaaidiary"
else
    log_error "不明なプラットフォーム: $PLATFORM"
    echo "使用方法: $0 [luaaidiary|wordpress] [duration_seconds] [interval_seconds]"
    exit 1
fi

# Docker コマンド確認
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker がインストールされていません"
        exit 1
    fi
    log_success "Docker が見つかりました: $(docker --version)"
}

# コンテナの確認
check_containers() {
    log_info "監視対象のコンテナを確認中..."
    
    local containers=$(docker ps --filter "name=${CONTAINER_PATTERN}" --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        log_error "監視対象のコンテナが見つかりません: ${CONTAINER_PATTERN}"
        log_info "起動しているコンテナ:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        exit 1
    fi
    
    log_success "監視対象のコンテナ:"
    echo "$containers" | while read -r container; do
        log_info "  - $container"
    done
    echo "$containers" | tee -a "$LOG_FILE"
}

# CSVヘッダー作成
create_csv_header() {
    echo "timestamp,container,cpu_percent,memory_usage,memory_limit,memory_percent,net_input,net_output,block_input,block_output" > "$CSV_FILE"
    log_success "CSVファイルを作成しました: $CSV_FILE"
}

# リソース監視
monitor_resources() {
    local end_time=$((SECONDS + DURATION))
    local sample_count=0
    
    log_info "リソース監視を開始します"
    log_info "  プラットフォーム: $PLATFORM"
    log_info "  監視時間: ${DURATION}秒"
    log_info "  サンプリング間隔: ${INTERVAL}秒"
    log_info "  出力: $CSV_FILE"
    echo ""
    
    # プログレスバー用の合計サンプル数
    local total_samples=$((DURATION / INTERVAL))
    
    while [ $SECONDS -lt $end_time ]; do
        sample_count=$((sample_count + 1))
        local timestamp=$(date +%s)
        local current_time=$(date "+%Y-%m-%d %H:%M:%S")
        
        # Docker stats を取得してCSVに追記
        docker stats --no-stream --filter "name=${CONTAINER_PATTERN}" \
            --format "{{.Container}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}" | \
        while IFS=',' read -r container cpu mem_usage mem_percent net_io block_io; do
            # メモリ使用量を分解（例: "123.4MiB / 2GiB" -> "123.4MiB", "2GiB"）
            mem_used=$(echo "$mem_usage" | awk '{print $1}')
            mem_limit=$(echo "$mem_usage" | awk '{print $3}')
            
            # ネットワークI/Oを分解（例: "1.2MB / 3.4MB" -> "1.2MB", "3.4MB"）
            net_input=$(echo "$net_io" | awk '{print $1}')
            net_output=$(echo "$net_io" | awk '{print $3}')
            
            # ブロックI/Oを分解
            block_input=$(echo "$block_io" | awk '{print $1}')
            block_output=$(echo "$block_io" | awk '{print $3}')
            
            # CSVに出力
            echo "${timestamp},${container},${cpu},${mem_used},${mem_limit},${mem_percent},${net_input},${net_output},${block_input},${block_output}" >> "$CSV_FILE"
        done
        
        # プログレス表示
        local progress=$((sample_count * 100 / total_samples))
        local remaining=$((end_time - SECONDS))
        printf "\r${BLUE}[INFO]${NC} サンプル: %d/%d (進捗: %d%%) 残り: %ds   " "$sample_count" "$total_samples" "$progress" "$remaining"
        
        # 次のサンプリングまで待機
        sleep "$INTERVAL"
    done
    
    echo "" # 改行
    log_success "リソース監視が完了しました"
    log_info "  合計サンプル数: $sample_count"
    log_info "  CSV: $CSV_FILE"
}

# サマリーレポート生成
generate_summary() {
    log_info "サマリーレポートを生成中..."
    
    local summary_file="$RESULTS_DIR/${PLATFORM}_summary_${TIMESTAMP}.txt"
    
    {
        echo "========================================"
        echo "リソース監視サマリー"
        echo "========================================"
        echo "プラットフォーム: $PLATFORM"
        echo "監視開始: $(date -d "@$(head -2 "$CSV_FILE" | tail -1 | cut -d',' -f1)" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")"
        echo "監視終了: $(date -d "@$(tail -1 "$CSV_FILE" | cut -d',' -f1)" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")"
        echo "サンプル数: $(wc -l < "$CSV_FILE")"
        echo "========================================"
        echo ""
        
        # コンテナごとの統計（awkで計算）
        awk -F',' 'NR>1 {
            container=$2
            cpu=$3
            mem_pct=$6
            
            # パーセント記号を削除
            gsub(/%/, "", cpu)
            gsub(/%/, "", mem_pct)
            
            # 数値として処理
            if (cpu ~ /^[0-9.]+$/) {
                cpu_sum[container] += cpu
                cpu_count[container]++
                if (cpu > cpu_max[container] || cpu_max[container] == "") cpu_max[container] = cpu
                if (cpu < cpu_min[container] || cpu_min[container] == "") cpu_min[container] = cpu
            }
            
            if (mem_pct ~ /^[0-9.]+$/) {
                mem_sum[container] += mem_pct
                mem_count[container]++
                if (mem_pct > mem_max[container] || mem_max[container] == "") mem_max[container] = mem_pct
                if (mem_pct < mem_min[container] || mem_min[container] == "") mem_min[container] = mem_pct
            }
        }
        END {
            for (c in cpu_sum) {
                printf "コンテナ: %s\n", c
                printf "  CPU使用率:\n"
                printf "    平均: %.2f%%\n", cpu_sum[c]/cpu_count[c]
                printf "    最小: %.2f%%\n", cpu_min[c]
                printf "    最大: %.2f%%\n", cpu_max[c]
                printf "  メモリ使用率:\n"
                printf "    平均: %.2f%%\n", mem_sum[c]/mem_count[c]
                printf "    最小: %.2f%%\n", mem_min[c]
                printf "    最大: %.2f%%\n", mem_max[c]
                printf "\n"
            }
        }' "$CSV_FILE"
        
    } > "$summary_file"
    
    log_success "サマリーレポートを生成しました: $summary_file"
    echo ""
    cat "$summary_file"
}

# シグナルハンドラ（Ctrl+Cで中断時）
cleanup() {
    echo ""
    log_warning "監視を中断しました"
    if [ -f "$CSV_FILE" ]; then
        generate_summary
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM

# メイン処理
main() {
    echo "========================================"
    echo "  リソース監視"
    echo "========================================"
    echo "プラットフォーム: $PLATFORM"
    echo "監視時間: ${DURATION}秒"
    echo "サンプリング間隔: ${INTERVAL}秒"
    echo "========================================"
    echo ""
    
    # 事前チェック
    check_docker
    check_containers
    
    # CSV作成
    create_csv_header
    
    # 監視開始
    monitor_resources
    
    # サマリー生成
    generate_summary
    
    log_success "すべての処理が完了しました"
}

# スクリプト実行
main
