.PHONY: help dev build up down restart logs logs-web logs-db logs-redis shell shell-lua shell-db psql redis-cli test test-file db-reset lint clean setup-env setup health status

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
	@echo "  make test       - テストを実行"
	@echo "  make lint       - Luacheckで静的解析を実行"
	@echo "  make db-reset   - データベースをリセット"
	@echo "  make clean      - すべてのコンテナとボリュームを削除"
	@echo "  make setup      - 初期セットアップを実行"
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
	@echo "   Redis: localhost:6379"

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

# テストを実行
test:
	@echo "🧪 テストを実行中..."
	$(DOCKER_COMPOSE) exec -w /app web sh -c "LUA_PATH='/app/?.lua;/app/?/init.lua;;' busted /tests/"

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

# 初期セットアップ
setup: setup-env
	@echo "🎉 初期セットアップを開始..."
	@make build
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

# ヘルスチェック
health:
	@echo "🏥 ヘルスチェック中..."
	@curl -s http://localhost:8080/health && echo "" || echo "❌ サービスが応答しません"

# 開発環境の状態を確認
status:
	@echo "📊 サービス状態:"
	@$(DOCKER_COMPOSE) ps
