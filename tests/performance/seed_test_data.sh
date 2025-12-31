#!/bin/bash

# 性能テスト用テストデータ投入スクリプト
# LuaAIDiaryとWordPressの両システムに100件の記事を投入

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# カラー出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数（標準エラー出力に出力）
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# LuaAIDiaryの記事数を確認
check_luaaidiary_posts() {
    log_info "LuaAIDiaryの記事数を確認中..."
    local count=$(docker exec luaaidiary-db psql -U luaaidiary -d luaaidiary -t -c "SELECT COUNT(*) FROM posts;" 2>/dev/null | tr -d ' ')
    echo "$count"
}

# WordPressの記事数を確認（REST API使用）
check_wordpress_posts() {
    log_info "WordPressの記事数を確認中..."
    local count=$(curl -s "http://localhost:8081/wp-json/wp/v2/posts?per_page=1" -I 2>/dev/null | grep -i "X-WP-Total:" | awk '{print $2}' | tr -d '\r' || echo "0")
    
    # countが空の場合は0を返す
    if [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    
    echo "$count"
}

# LuaAIDiaryにテストデータを投入
seed_luaaidiary() {
    local target_count=$1
    local current_count=$2
    
    if [ "$current_count" -ge "$target_count" ]; then
        log_success "LuaAIDiaryには既に${current_count}件の記事があります（目標: ${target_count}件）"
        return 0
    fi
    
    local posts_to_add=$((target_count - current_count))
    log_info "LuaAIDiaryに${posts_to_add}件の記事を追加します..."
    
    # SQLスクリプトを生成
    local sql_file="/tmp/luaaidiary_seed_$(date +%s).sql"
    
    cat > "$sql_file" << 'EOF'
-- 性能テスト用記事データ
BEGIN;

DO $$
DECLARE
    i INTEGER;
    post_title TEXT;
    post_slug TEXT;
    post_content TEXT;
    post_excerpt TEXT;
    days_ago INTEGER;
    category_ids INTEGER[];
BEGIN
    -- カテゴリーIDを取得
    SELECT ARRAY_AGG(id) INTO category_ids FROM categories LIMIT 3;
    
    FOR i IN 6..100 LOOP
        post_title := 'パフォーマンステスト記事 #' || i;
        post_slug := 'performance-test-post-' || i;
        days_ago := (i - 5);
        
        post_content := E'# ' || post_title || E'\n\n' ||
            E'これは性能テスト用に自動生成された記事です。\n\n' ||
            E'## 記事の内容\n\n' ||
            E'この記事は、LuaAIDiaryとWordPressの性能比較テストのために作成されました。' ||
            E'両システムで同等のデータ量を用意することで、公平な比較を実現します。\n\n' ||
            E'### テスト内容\n\n' ||
            E'- 記事の読み込み速度\n' ||
            E'- データベースクエリの効率性\n' ||
            E'- 同時アクセス時の応答性\n' ||
            E'- リソース消費量\n\n' ||
            E'## OpenRestyとLuaJITの利点\n\n' ||
            E'LuaAIDiaryは、OpenRestyとLuaJITを使用した高性能ブログシステムです。' ||
            E'以下のような特徴があります：\n\n' ||
            E'1. **高速な処理**: LuaJITによるネイティブコード実行\n' ||
            E'2. **低メモリ消費**: 効率的なリソース管理\n' ||
            E'3. **高い同時接続数**: 非同期I/Oによる効率的な処理\n' ||
            E'4. **スケーラビリティ**: 負荷に応じた柔軟な拡張性\n\n' ||
            E'## ベンチマーク結果\n\n' ||
            E'詳細な性能テスト結果は、tests/performance/results/ ディレクトリに保存されます。' ||
            E'wrkツールを使用した負荷テストにより、実際のアクセスパターンを再現します。\n\n' ||
            E'### 測定項目\n\n' ||
            E'- リクエスト/秒 (RPS)\n' ||
            E'- 平均レイテンシ\n' ||
            E'- 99パーセンタイルレイテンシ\n' ||
            E'- CPU使用率\n' ||
            E'- メモリ使用量\n\n' ||
            E'記事番号: ' || i || E'\n' ||
            E'作成日: ' || (CURRENT_TIMESTAMP - (days_ago || ' days')::INTERVAL) || E'\n';
        
        post_excerpt := 'パフォーマンステスト記事 #' || i || ' - LuaAIDiaryとWordPressの性能比較テスト用の自動生成記事です。';
        
        -- 記事を挿入
        INSERT INTO posts (title, slug, content, excerpt, author_id, status, published_at, created_at, updated_at)
        VALUES (
            post_title,
            post_slug,
            post_content,
            post_excerpt,
            1,
            'published',
            CURRENT_TIMESTAMP - (days_ago || ' days')::INTERVAL,
            CURRENT_TIMESTAMP - (days_ago || ' days')::INTERVAL,
            CURRENT_TIMESTAMP - (days_ago || ' days')::INTERVAL
        );
        
        -- カテゴリーを関連付け（ランダムに1つ選択）
        IF array_length(category_ids, 1) > 0 THEN
            INSERT INTO post_categories (post_id, category_id)
            SELECT currval('posts_id_seq'), category_ids[(i % array_length(category_ids, 1)) + 1];
        END IF;
        
    END LOOP;
    
    RAISE NOTICE '95件の記事を追加しました';
END $$;

COMMIT;
EOF
    
    # SQLを実行
    if docker exec -i luaaidiary-db psql -U luaaidiary -d luaaidiary < "$sql_file" > /dev/null 2>&1; then
        log_success "LuaAIDiaryにテストデータを投入しました"
        rm -f "$sql_file"
        return 0
    else
        log_error "LuaAIDiaryへのデータ投入に失敗しました"
        rm -f "$sql_file"
        return 1
    fi
}

# WordPressにテストデータを投入（MySQL直接投入）
seed_wordpress() {
    local target_count=$1
    local current_count=$2
    
    if [ "$current_count" -ge "$target_count" ]; then
        log_success "WordPressには既に${current_count}件の記事があります（目標: ${target_count}件）"
        return 0
    fi
    
    local posts_to_add=$((target_count - current_count))
    log_info "WordPressに${posts_to_add}件の記事を追加します..."
    log_info "MySQL経由でデータを投入します..."
    
    # SQLスクリプトを生成（エラーを無視してすべての認証方法を試す）
    local sql_file="/tmp/wordpress_seed_$$.sql"
    
    # 完全なINSERTスクリプトを生成（全必須フィールドを含む）
    cat > "$sql_file" << 'EOSQL'
SET @num_posts = 100;
SET @current_count = (SELECT COUNT(*) FROM wp_posts WHERE post_type = 'post' AND post_status = 'publish');
SET @posts_to_create = @num_posts - @current_count;

-- 記事を追加（100件になるまで）
INSERT INTO wp_posts (
    post_author,
    post_date,
    post_date_gmt,
    post_content,
    post_title,
    post_excerpt,
    post_status,
    comment_status,
    ping_status,
    post_password,
    post_name,
    to_ping,
    pinged,
    post_modified,
    post_modified_gmt,
    post_content_filtered,
    post_parent,
    guid,
    menu_order,
    post_type,
    post_mime_type,
    comment_count
)
SELECT
    1 AS post_author,
    DATE_SUB(NOW(), INTERVAL n DAY) AS post_date,
    DATE_SUB(UTC_TIMESTAMP(), INTERVAL n DAY) AS post_date_gmt,
    CONCAT('<h1>パフォーマンステスト記事 #', @current_count + n, '</h1>

<p>これは性能テスト用に自動生成された記事です。</p>

<h2>記事の内容</h2>

<p>この記事は、LuaAIDiaryとWordPressの性能比較テストのために作成されました。両システムで同等のデータ量を用意することで、公平な比較を実現します。</p>

<h3>テスト内容</h3>
<ul>
<li>記事の読み込み速度</li>
<li>データベースクエリの効率性</li>
<li>同時アクセス時の応答性</li>
<li>リソース消費量</li>
</ul>

<h2>WordPressの特徴</h2>
<p>WordPressは、世界中で最も広く使用されているCMSです。</p>

<p>記事番号: ', @current_count + n, '</p>') AS post_content,
    CONCAT('パフォーマンステスト記事 #', @current_count + n) AS post_title,
    CONCAT('パフォーマンステスト記事 #', @current_count + n, ' - LuaAIDiaryとWordPressの性能比較テスト用の自動生成記事です。') AS post_excerpt,
    'publish' AS post_status,
    'open' AS comment_status,
    'open' AS ping_status,
    '' AS post_password,
    CONCAT('performance-test-post-', @current_count + n) AS post_name,
    '' AS to_ping,
    '' AS pinged,
    DATE_SUB(NOW(), INTERVAL n DAY) AS post_modified,
    DATE_SUB(UTC_TIMESTAMP(), INTERVAL n DAY) AS post_modified_gmt,
    '' AS post_content_filtered,
    0 AS post_parent,
    '' AS guid,
    0 AS menu_order,
    'post' AS post_type,
    '' AS post_mime_type,
    0 AS comment_count
FROM (
    SELECT @rownum := @rownum + 1 AS n
    FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 0) t1,
         (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 0) t2,
         (SELECT @rownum := 0) t3
    LIMIT 100
) numbers
WHERE n <= @posts_to_create AND @posts_to_create > 0;
EOSQL
    
    # MySQL接続パラメータ
    local db_user="wordpress"
    local db_pass="wordpress1234"
    local db_name="wordpress"
    local success=0
    
    # MySQLに接続してデータを投入
    if docker exec -i wordpress-db mysql -u"$db_user" -p"$db_pass" "$db_name" < "$sql_file" > /dev/null 2>&1; then
        log_success "WordPress に MySQL 経由でデータを投入しました"
        success=1
    elif docker exec -i wordpress-db mysql -uroot -p"$db_pass" "$db_name" < "$sql_file" > /dev/null 2>&1; then
        log_success "WordPress に MySQL 経由でデータを投入しました (root user)"
        success=1
    fi
    
    rm -f "$sql_file"
    
    if [ $success -eq 1 ]; then
        return 0
    else
        log_error "WordPressデータベースへの接続に失敗しました"
        log_warning "WordPressのデータベース認証情報を確認してください"
        log_info "手動でMySQLコンテナに接続して記事を追加することができます"
        return 1
    fi
}

# メイン処理
main() {
    local target_posts=100
    
    echo "=========================================="
    echo "  性能テスト用データ投入スクリプト"
    echo "=========================================="
    echo ""
    
    log_info "目標記事数: ${target_posts}件"
    echo ""
    
    # LuaAIDiary
    log_info "=== LuaAIDiary ==="
    local luaaidiary_count=$(check_luaaidiary_posts)
    log_info "現在の記事数: ${luaaidiary_count}件"
    
    if seed_luaaidiary "$target_posts" "$luaaidiary_count"; then
        local new_count=$(check_luaaidiary_posts)
        log_success "LuaAIDiary: 投入後の記事数 = ${new_count}件"
    else
        log_error "LuaAIDiaryへのデータ投入に失敗しました"
    fi
    
    echo ""
    
    # WordPress
    log_info "=== WordPress ==="
    local wordpress_count=$(check_wordpress_posts)
    log_info "現在の記事数: ${wordpress_count}件"
    
    if seed_wordpress "$target_posts" "$wordpress_count"; then
        local new_count=$(check_wordpress_posts)
        log_success "WordPress: 投入後の記事数 = ${new_count}件"
    else
        log_warning "WordPressへのデータ投入に失敗しました。手動で投入が必要です"
    fi
    
    echo ""
    echo "=========================================="
    log_success "テストデータの投入が完了しました"
    echo "=========================================="
    echo ""
    
    # 最終確認
    log_info "=== 最終確認 ==="
    local final_luaaidiary=$(check_luaaidiary_posts)
    local final_wordpress=$(check_wordpress_posts)
    
    echo "  LuaAIDiary: ${final_luaaidiary}件"
    echo "  WordPress:  ${final_wordpress}件"
    echo ""
    
    if [ "$final_luaaidiary" -ge "$target_posts" ] && [ "$final_wordpress" -ge "$target_posts" ]; then
        log_success "両システムとも${target_posts}件以上の記事が準備できました"
        log_info "性能テストを実行する準備が整いました"
        echo ""
        log_info "次のコマンドでベンチマークを実行できます:"
        echo "  cd tests/performance && ./run_benchmark.sh"
        return 0
    else
        log_warning "一部のシステムで目標記事数に達していません"
        return 1
    fi
}

# スクリプト実行
main "$@"
