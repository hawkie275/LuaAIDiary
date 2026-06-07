.PHONY: help dev build up down restart logs logs-web logs-db logs-redis shell shell-lua shell-db psql redis-cli migrate test test-file test-integration test-e2e test-all db-reset lint clean setup-env setup setup-build sync-app-version health status

# Docker Composeコマンド
DOCKER_COMPOSE := docker compose

# デフォルトターゲット
help:
	@echo "LuaAIDiary 開発環境 Makefile"
	@echo ""
	@echo "利用可能なコマンド:"
	@echo "  make dev        - 開発サーバーを起動（ホットリロード有効）"
	@echo "  make build      - Dockerイメージをビルド"
	@echo "  make up         - サービスを起動"
	@echo "  make down       - サービスを停止"
	@echo "  make restart    - サービスを再起動"
	@echo "  make logs       - すべてのサービスのログを表示"
	@echo "  make logs-web   - Webサーバーのログを表示"
	@echo "  make logs-db    - データベースのログを表示"
	@echo "  make logs-redis - Redisのログを表示"
	@echo "  make shell      - Webコンテナのシェルに入る"
	@echo "  make shell-lua  - Webコンテナ内でLuaシェルを起動"
	@echo "  make shell-db   - DBコンテナのシェルに入る"
	@echo "  make psql       - PostgreSQLクライアントに接続"
	@echo "  make redis-cli  - Redisクライアントに接続"
	@echo "  make migrate    - 既存DBへ未適用マイグレーションを適用"
	@echo "  make test           - E2Eテストを実行（HTTP経由）"
	@echo "  make test-integration - 統合テストを実行（実際のDB使用）"
	@echo "  make test-e2e       - E2Eテストを実行（HTTP経由）"
	@echo "  make test-all       - すべてのテストを実行"
	@echo "  make lint       - Luacheckで静的解析を実行"
	@echo "  make db-reset   - データベースをリセット"
	@echo "  make clean      - すべてのコンテナとボリュームを削除"
	@echo "  make setup      - 初期セットアップを実行（GHCRのlatestイメージをpullして起動）"
	@echo "  make setup-build - 初期セットアップを実行（ローカルでbuildして起動）"
	@echo "  make sync-app-version - pull済みイメージからAPP_VERSIONを抽出して.envを更新"
	@echo "  make health     - ヘルスチェックを実行"
	@echo "  make status     - サービス状態を確認"

# 開発サーバー起動
dev:
	@echo "🚀 開発サーバーを起動中..."
	$(DOCKER_COMPOSE) up

# Dockerイメージをビルド
build:
	@echo "🔨 Dockerイメージをビルド中..."
	$(DOCKER_COMPOSE) build --no-cache

# サービスを起動（バックグラウンド）
up:
	@echo "⬆️  サービスを起動中..."
	$(DOCKER_COMPOSE) up -d
	@echo "✅ サービスが起動しました"
	@echo "   Web: http://localhost:8080"
	@echo "   PostgreSQL: localhost:5432"
	@echo "   Valkey: localhost:6379"

# サービスを停止
down:
	@echo "⬇️  サービスを停止中..."
	$(DOCKER_COMPOSE) down

# サービスを再起動
restart:
	@echo "🔄 サービスを再起動中..."
	$(DOCKER_COMPOSE) restart

# すべてのログを表示
logs:
	$(DOCKER_COMPOSE) logs -f

# Webサーバーのログを表示
logs-web:
	$(DOCKER_COMPOSE) logs -f web

# データベースのログを表示
logs-db:
	$(DOCKER_COMPOSE) logs -f db

# Redisのログを表示
logs-redis:
	$(DOCKER_COMPOSE) logs -f redis

# Webコンテナのシェルに入る
shell:
	@echo "🐚 Webコンテナのシェルに接続中..."
	$(DOCKER_COMPOSE) exec web /bin/sh

# WebコンテナでLuaシェルを起動
shell-lua:
	@echo "🌙 Luaシェルを起動中..."
	$(DOCKER_COMPOSE) exec web lua

# DBコンテナのシェルに入る
shell-db:
	@echo "🐚 DBコンテナのシェルに接続中..."
	$(DOCKER_COMPOSE) exec db /bin/bash

# PostgreSQLクライアントに接続
psql:
	@echo "🗄️  PostgreSQLクライアントに接続中..."
	$(DOCKER_COMPOSE) exec db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d $(shell grep POSTGRES_DB .env | cut -d '=' -f2)

# Redisクライアントに接続
redis-cli:
	@echo "📦 Redisクライアントに接続中..."
	$(DOCKER_COMPOSE) exec redis redis-cli

# 既存DBへ未適用マイグレーションを適用
migrate:
	@echo "🗄️  データベースマイグレーションを実行中..."
	$(DOCKER_COMPOSE) exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"' < postgresql/migrations/001_add_media_tables.sql
	@echo "✅ データベースマイグレーションが完了しました"

# E2Eテストを実行（HTTP経由）
test:
	@echo "🌐 E2Eテストを実行中（HTTP経由）..."
	@make test-e2e

# 統合テストを実行（実際のDB使用）
test-integration:
	@echo "🔗 統合テストを実行中（実際のDBを使用）..."
	@echo "⚠️  注意: このテストは実際のデータベースに接続します"
	$(DOCKER_COMPOSE) exec -w /app web sh -c "LUA_PATH='/app/?.lua;/app/?/init.lua;;' busted /tests/integration/"

# E2Eテストを実行（HTTP経由）
test-e2e:
	@echo "🌐 E2Eテストを実行中（HTTP経由）..."
	@echo "⚠️  注意: サービスが起動している必要があります"
	@bash tests/e2e/test_post_api.sh

# すべてのテストを実行
test-all:
	@echo "🧪 E2Eテストのみを実行中..."
	@echo ""
	@echo "=== E2Eテスト ==="
	@make test-e2e
	@echo ""
	@echo "✅ E2Eテストが完了しました"

# 特定のテストファイルを実行
test-file:
	@echo "🧪 テストファイルを実行中: $(FILE)"
	$(DOCKER_COMPOSE) exec web busted $(FILE)

# データベースをリセット
db-reset:
	@echo "🔄 データベースをリセット中..."
	@echo "⚠️  警告: すべてのデータが削除されます。続行しますか? [y/N]"
	@read -r response; \
	if [ "$$response" = "y" ] || [ "$$response" = "Y" ]; then \
		$(DOCKER_COMPOSE) exec db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d postgres -c "DROP DATABASE IF EXISTS $(shell grep POSTGRES_DB .env | cut -d '=' -f2);"; \
		$(DOCKER_COMPOSE) exec db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d postgres -c "CREATE DATABASE $(shell grep POSTGRES_DB .env | cut -d '=' -f2) WITH ENCODING 'UTF8';"; \
		$(DOCKER_COMPOSE) exec -T db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d $(shell grep POSTGRES_DB .env | cut -d '=' -f2) < postgresql/init/01_create_tables.sql; \
		echo "✅ データベースをリセットしました"; \
	else \
		echo "❌ キャンセルされました"; \
	fi

# Luacheck（静的解析）を実行
lint:
	@echo "🔍 Luacheckを実行中..."
	$(DOCKER_COMPOSE) exec web luacheck app/ tests/

# すべてのコンテナとボリュームを削除
clean:
	@echo "🧹 コンテナとボリュームを削除中..."
	@echo "⚠️  警告: すべてのデータが削除されます。続行しますか? [y/N]"
	@read -r response; \
	if [ "$$response" = "y" ] || [ "$$response" = "Y" ]; then \
		$(DOCKER_COMPOSE) down -v; \
		echo "✅ クリーンアップが完了しました"; \
	else \
		echo "❌ キャンセルされました"; \
	fi

# .envファイルを作成
setup-env:
	@if [ ! -f .env ]; then \
		echo "📝 .envファイルを作成中..."; \
		cp .env.example .env; \
		echo "✅ .envファイルを作成しました。必要に応じて編集してください。"; \
	else \
		echo "ℹ️  .envファイルは既に存在します"; \
	fi

# pull済みイメージから APP_VERSION を抽出して .env に反映
sync-app-version: setup-env
	@echo "🔄 APP_VERSION をイメージタグから同期中..."
	@IMAGE_TAG_VAL=$${IMAGE_TAG:-$$(grep '^IMAGE_TAG=' .env | cut -d '=' -f2)}; \
	if [ -z "$$IMAGE_TAG_VAL" ]; then IMAGE_TAG_VAL=latest; fi; \
	IMAGE_REF="ghcr.io/hawkie275/luaaidiary:$$IMAGE_TAG_VAL"; \
	APP_VER=$$(docker image inspect $$IMAGE_REF --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep '^APP_VERSION=' | head -n1 | cut -d '=' -f2); \
	if [ -z "$$APP_VER" ]; then \
		echo "❌ APP_VERSION 抽出に失敗: $$IMAGE_REF (先に 'docker compose pull web' を実行し、APP_VERSION入りイメージを利用してください)"; \
		exit 1; \
	fi; \
	if grep -q '^APP_VERSION=' .env; then \
		sed -i "s/^APP_VERSION=.*/APP_VERSION=$$APP_VER/" .env; \
	else \
		echo "APP_VERSION=$$APP_VER" >> .env; \
	fi; \
	echo "✅ .env を更新しました: APP_VERSION=$$APP_VER"

# 初期セットアップ
setup: setup-env
	@echo "🎉 初期セットアップを開始..."
	@echo "📦 GHCRから最新のWebイメージを取得中..."
	$(DOCKER_COMPOSE) pull web
	@make sync-app-version
	@echo "ℹ️  ローカルビルドを行う場合は 'make setup-build' を使用してください"
	@make up
	@echo "⏳ データベースの起動を待機中..."
	@sleep 10
	@echo "✅ セットアップが完了しました！"
	@echo ""
	@echo "次のコマンドでアプリケーションにアクセスできます:"
	@echo "  http://localhost:8080"
	@echo ""
	@echo "ログを確認: make logs"
	@echo "テスト実行: make test"

# 初期セットアップ（ローカルビルド版）
setup-build: setup-env
	@echo "🎉 初期セットアップ（ローカルビルド）を開始..."
	@make build
	@make up
	@echo "⏳ データベースの起動を待機中..."
	@sleep 10
	@echo "✅ セットアップ（ローカルビルド）が完了しました！"
	@echo ""
	@echo "次のコマンドでアプリケーションにアクセスできます:"
	@echo "  http://localhost:8080"
	@echo ""
	@echo "ログを確認: make logs"
	@echo "テスト実行: make test"

# ヘルスチェック
health:
	@echo "🏥 ヘルスチェック中..."
	@curl -s http://localhost:8080/health && echo "" || echo "❌ サービスが応答しません"

# 開発環境の状態を確認
status:
	@echo "📊 サービス状態:"
	@$(DOCKER_COMPOSE) ps
