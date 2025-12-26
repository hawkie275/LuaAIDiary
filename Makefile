.PHONY: help dev build up down restart logs logs-web logs-db logs-redis shell shell-web shell-db test db-reset clean

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
	@echo "  make shell-db   - DBコンテナのシェルに入る"
	@echo "  make test       - テストを実行"
	@echo "  make db-reset   - データベースをリセット"
	@echo "  make clean      - すべてのコンテナとボリュームを削除"

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
	@echo "   MySQL: localhost:3306"
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

# MySQLクライアントに接続
mysql:
	@echo "🗄️  MySQLクライアントに接続中..."
	$(DOCKER_COMPOSE) exec db mysql -u$(shell grep MYSQL_USER .env | cut -d '=' -f2) -p$(shell grep MYSQL_PASSWORD .env | cut -d '=' -f2) $(shell grep MYSQL_DATABASE .env | cut -d '=' -f2)

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
		$(DOCKER_COMPOSE) exec db mysql -uroot -p$(shell grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2) -e "DROP DATABASE IF EXISTS $(shell grep MYSQL_DATABASE .env | cut -d '=' -f2); CREATE DATABASE $(shell grep MYSQL_DATABASE .env | cut -d '=' -f2) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; \
		$(DOCKER_COMPOSE) exec db mysql -uroot -p$(shell grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2) $(shell grep MYSQL_DATABASE .env | cut -d '=' -f2) < mysql/init/01_create_tables.sql; \
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
