# 性能テスト

このディレクトリには、WordPress と LuaAIDiary の性能を比較するためのベンチマークツールとスクリプトが含まれています。

## 📋 目次

- [前提条件](#前提条件)
- [ディレクトリ構造](#ディレクトリ構造)
- [クイックスタート](#クイックスタート)
- [詳細な使用方法](#詳細な使用方法)
- [結果の見方](#結果の見方)
- [トラブルシューティング](#トラブルシューティング)

## 前提条件

### 必須ツール

1. **wrk** - HTTPベンチマークツール

```bash
# Ubuntu/Debianの場合
sudo apt-get update
sudo apt-get install wrk

# またはソースからビルド
git clone https://github.com/wg/wrk.git
cd wrk
make
sudo cp wrk /usr/local/bin/
```

2. **Docker & Docker Compose** - コンテナ実行環境

```bash
docker --version
docker compose version
```

### テスト対象システム

- **LuaAIDiary**: `http://localhost:8080`
- **WordPress**: `http://localhost:8081` (別途セットアップが必要)

## ディレクトリ構造

```
tests/performance/
├── README.md                      # このファイル
├── run_benchmark.sh               # メインベンチマークスクリプト
├── monitor_resources.sh           # リソース監視スクリプト
├── wrk_scripts/                   # wrk用Luaスクリプト
│   └── random_post.lua           # ランダム記事アクセス
└── results/                       # 結果保存ディレクトリ
    ├── wordpress/                # WordPress結果
    └── luaaidiary/               # LuaAIDiary結果
```

## クイックスタート

### 1. LuaAIDiary システムの起動

```bash
cd /home/yagi/github/LuaAIDiary
make up
make health  # 起動確認
```

### 2. ベンチマークの実行

```bash
# LuaAIDiary のベンチマーク（デフォルト: 60秒/シナリオ）
./tests/performance/run_benchmark.sh luaaidiary

# テスト時間を指定（例: 120秒）
./tests/performance/run_benchmark.sh luaaidiary 120

# WordPressのベンチマーク（WordPress環境が起動している必要があります）
./tests/performance/run_benchmark.sh wordpress 60
```

### 3. リソース監視（別ターミナル）

ベンチマークと同時にリソース使用状況を監視する場合:

```bash
# LuaAIDiary のリソース監視（300秒 = 5分間）
./tests/performance/monitor_resources.sh luaaidiary 300 5

# WordPress のリソース監視
./tests/performance/monitor_resources.sh wordpress 300 5
```

## 詳細な使用方法

### run_benchmark.sh

メインのベンチマークスクリプトです。wrkを使用して複数のシナリオを実行します。

**使用方法:**
```bash
./tests/performance/run_benchmark.sh <platform> [duration]
```

**パラメータ:**
- `platform`: `luaaidiary` または `wordpress`
- `duration`: 各シナリオのテスト時間（秒）。デフォルト: 60

**実行されるシナリオ:**

1. **シナリオ1: トップページ（段階的負荷）**
   - 100並行接続 (4スレッド)
   - 200並行接続 (8スレッド)
   - 400並行接続 (12スレッド)

2. **シナリオ2: ランダム記事アクセス**
   - 200並行接続でランダムな記事にアクセス
   - 実際のユーザー行動をシミュレート

3. **シナリオ3: ヘルスチェック（LuaAIDiaryのみ）**
   - 最小レイテンシを測定

**例:**
```bash
# LuaAIDiary を180秒間テスト
./tests/performance/run_benchmark.sh luaaidiary 180

# WordPress を60秒間テスト
./tests/performance/run_benchmark.sh wordpress 60
```

### monitor_resources.sh

Docker Statsを使用してコンテナのリソース使用状況を継続的に監視します。

**使用方法:**
```bash
./tests/performance/monitor_resources.sh <platform> [duration] [interval]
```

**パラメータ:**
- `platform`: `luaaidiary` または `wordpress`
- `duration`: 監視時間（秒）。デフォルト: 300
- `interval`: サンプリング間隔（秒）。デフォルト: 5

**出力:**
- CSVファイル: `results/<platform>_resources_<timestamp>.csv`
- サマリーレポート: `results/<platform>_summary_<timestamp>.txt`

**例:**
```bash
# LuaAIDiary を600秒間、10秒間隔で監視
./tests/performance/monitor_resources.sh luaaidiary 600 10

# バックグラウンドで実行
./tests/performance/monitor_resources.sh wordpress 300 5 &
```

### wrk_scripts/random_post.lua

ランダムな記事にアクセスするwrk用Luaスクリプトです。

**機能:**
- 記事ID 1-100 からランダムに選択
- ステータスコード分布の記録
- レイテンシ統計の出力
- エラー率の計算

**カスタマイズ:**
スクリプト内の変数を編集して動作を変更できます:

```lua
local min_post_id = 1
local max_post_id = 100
```

## 結果の見方

### ベンチマーク結果ファイル

各シナリオの結果は以下の形式で保存されます:
```
results/<platform>/<scenario>_t<threads>_c<connections>_<timestamp>.txt
```

**主要メトリクス:**

1. **Latency（レイテンシ）**
   ```
   Latency     23.45ms   12.34ms   89.12ms   78.90%
   ```
   - 平均、標準偏差、最大値、分散

2. **Requests/sec（スループット）**
   ```
   Req/Sec     4.32k     1.23k    6.54k    89.12%
   ```
   - リクエスト/秒の統計

3. **パーセンタイル分布**
   ```
   50.000%    21.50ms
   90.000%    35.60ms
   99.000%    58.90ms
   ```
   - 50%, 90%, 99%のリクエストが完了した時間

### リソース監視結果

**CSVファイル形式:**
```csv
timestamp,container,cpu_percent,memory_usage,memory_limit,memory_percent,net_input,net_output,block_input,block_output
1704067200,luaaidiary-web,28.5%,280.1MiB,2GiB,14.0%,1.2MB,3.4MB,0B,0B
```

**サマリーレポート:**
- コンテナごとのCPU/メモリ使用率の平均、最小、最大値
- 監視期間とサンプル数

## ベストプラクティス

### 1. テスト前の準備

```bash
# LuaAIDiary環境の準備
cd /home/yagi/github/LuaAIDiary
make up
sleep 10  # データベース起動待機
make health

# ウォームアップ（スクリプトが自動実行）
# または手動で:
wrk -t2 -c10 -d30s http://localhost:8080/
```

### 2. 公平な比較のために

- 同時に複数のコンテナを起動しない
- テスト間に十分なクールダウン時間を設ける
- 同じデータ量でテストする
- システムリソースが安定している時間帯に実施

### 3. 複数回実行

信頼性の高い結果を得るため、各テストを3回以上実行:

```bash
for i in {1..3}; do
    echo "実行 $i/3"
    ./tests/performance/run_benchmark.sh luaaidiary 60
    sleep 60  # クールダウン
done
```

### 4. リソース監視との併用

```bash
# ターミナル1: リソース監視開始
./tests/performance/monitor_resources.sh luaaidiary 600 5 &
MONITOR_PID=$!

# ターミナル1: ベンチマーク実行
./tests/performance/run_benchmark.sh luaaidiary 180

# 監視完了を待つ
wait $MONITOR_PID
```

## トラブルシューティング

### wrk がインストールされていない

```bash
# エラーメッセージ例
[ERROR] wrk がインストールされていません

# 解決方法
sudo apt-get update && sudo apt-get install wrk
```

### サービスが応答しない

```bash
# エラーメッセージ例
[ERROR] サービスが応答しません: http://localhost:8080

# 確認方法
docker ps  # コンテナの状態確認
make status  # LuaAIDiaryの場合
make logs  # ログ確認

# 解決方法
make down && make up  # 再起動
```

### コンテナが見つからない

```bash
# エラーメッセージ例
[ERROR] 監視対象のコンテナが見つかりません: luaaidiary

# 確認方法
docker ps --filter "name=luaaidiary"

# 解決方法
cd /home/yagi/github/LuaAIDiary
make up
```

### メモリ不足

```bash
# システムメモリ確認
free -h

# Docker のメモリ使用量確認
docker stats --no-stream

# 不要なコンテナ/イメージ削除
docker system prune -a
```

### ポート競合

```bash
# ポート使用状況確認
sudo netstat -tlnp | grep -E '(8080|8081)'

# 競合するプロセスを停止
sudo kill <PID>

# または Docker Compose でポートを変更
# docker-compose.yml の ports セクションを編集
```

## 高度な使用例

### カスタムシナリオの追加

`run_benchmark.sh` を編集してシナリオを追加:

```bash
# シナリオ4: API エンドポイント
log_info "=== シナリオ4: API エンドポイント ==="
run_benchmark "scenario4_api" 8 200 "${BASE_URL}/api/posts"
```

### カスタムwrkスクリプトの作成

`wrk_scripts/` に新しいLuaスクリプトを追加:

```lua
-- wrk_scripts/custom_scenario.lua
request = function()
    local paths = {"/", "/about", "/contact"}
    local path = paths[math.random(#paths)]
    return wrk.format("GET", path)
end
```

使用方法:
```bash
wrk -t8 -c200 -d60s -s tests/performance/wrk_scripts/custom_scenario.lua http://localhost:8080/
```

## 参考資料

- [wrk GitHub](https://github.com/wg/wrk)
- [wrk Lua Scripting](https://github.com/wg/wrk/blob/master/SCRIPTING)
- [Docker Stats Documentation](https://docs.docker.com/engine/reference/commandline/stats/)
- [性能比較計画書](../../docs/performance_comparison_plan.md)

## サポート

問題が発生した場合は、以下を確認してください:

1. このREADMEのトラブルシューティングセクション
2. `make logs` でコンテナログを確認
3. `docker ps` でコンテナの状態を確認
4. GitHubのIssuesセクション

---

**最終更新**: 2025-12-31  
**バージョン**: 1.0.0
