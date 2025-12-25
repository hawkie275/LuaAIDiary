# LuaベースのWordPressライクなブログシステム - アーキテクチャ設計書

## 概要

本ドキュメントは、Docker Composeを使用してLuaベースのWordPressライクなブログシステムとMySQLデータベースを構成するための設計書です。

## システム構成図

```mermaid
graph TB
    Client[クライアント<br/>ブラウザ]
    subgraph Docker環境
        Web[Webサーバー<br/>OpenResty]
        DB[(MySQL<br/>データベース)]
        WebVol[/app ボリューム/]
        DBVol[/mysql-data ボリューム/]
    end
    
    Client -->|HTTP:8080| Web
    Web -->|SQL| DB
    Web ---|マウント| WebVol
    DB ---|永続化| DBVol
```

## 1. Docker Compose全体構成

### サービス構成

- **web**: OpenRestyベースのWebサーバー (Lua実行環境)
- **db**: MySQL 8.0データベースサーバー

### ネットワーク

- カスタムブリッジネットワーク `LuaAIDiary-network` を使用
- サービス間通信はDockerの内部DNSで名前解決

### ボリューム

- `mysql-data`: MySQLデータの永続化用
- `./app`: アプリケーションコード (ホストとコンテナ間で共有)
- `./nginx`: Nginx設定ファイル
- `./logs`: アプリケーションログ

## 2. docker-compose.yml 構造

```yaml
version: '3.8'

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: LuaAIDiary-web
    ports:
      - "8080:80"
    volumes:
      - ./app:/app
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf
      - ./logs:/var/log/nginx
    environment:
      - MYSQL_HOST=db
      - MYSQL_PORT=3306
      - MYSQL_DATABASE=LuaAIDiary
      - MYSQL_USER=LuaAIDiary_user
      - MYSQL_PASSWORD=LuaAIDiary_pass
    depends_on:
      - db
    networks:
      - LuaAIDiary-network
    restart: unless-stopped

  db:
    image: mysql:8.0
    container_name: LuaAIDiary-db
    environment:
      - MYSQL_ROOT_PASSWORD=root_password
      - MYSQL_DATABASE=LuaAIDiary
      - MYSQL_USER=LuaAIDiary_user
      - MYSQL_PASSWORD=LuaAIDiary_pass
      - MYSQL_CHARACTER_SET_SERVER=utf8mb4
      - MYSQL_COLLATION_SERVER=utf8mb4_unicode_ci
    volumes:
      - mysql-data:/var/lib/mysql
      - ./mysql/init:/docker-entrypoint-initdb.d
    ports:
      - "3306:3306"
    networks:
      - LuaAIDiary-network
    restart: unless-stopped
    command: --default-authentication-plugin=mysql_native_password

networks:
  LuaAIDiary-network:
    driver: bridge

volumes:
  mysql-data:
    driver: local
```

## 3. Dockerfile (Webサーバー用)

### ベースイメージ

- `openresty/openresty:alpine`: 軽量で高性能なOpenRestyイメージ

### 必要なパッケージ

```dockerfile
FROM openresty/openresty:alpine

# 必要なパッケージのインストール
RUN apk add --no-cache \
    git \
    gcc \
    musl-dev \
    openssl-dev \
    mysql-client

# LuaRocksのインストール (Luaパッケージマネージャー)
RUN apk add --no-cache luarocks

# 必要なLuaモジュールのインストール
RUN luarocks install lua-resty-mysql \
    && luarocks install lua-resty-template \
    && luarocks install lua-resty-session \
    && luarocks install lua-cjson \
    && luarocks install luasocket \
    && luarocks install bcrypt

# アプリケーションディレクトリの作成
RUN mkdir -p /app

# 作業ディレクトリの設定
WORKDIR /app

# ポート80を公開
EXPOSE 80

# OpenRestyの起動
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
```

## 4. ディレクトリ構造

```
LuaAIDiary/
├── docker-compose.yml          # Docker Compose設定ファイル
├── Dockerfile                  # Webサーバー用Dockerfile
├── ARCHITECTURE.md             # 本設計書
├── README.md                   # プロジェクト概要
│
├── app/                        # Luaアプリケーションコード
│   ├── init.lua               # アプリケーション初期化
│   ├── config.lua             # 設定ファイル
│   ├── routes.lua             # ルーティング定義
│   │
│   ├── controllers/           # コントローラー層
│   │   ├── post_controller.lua
│   │   ├── user_controller.lua
│   │   └── admin_controller.lua
│   │
│   ├── models/                # モデル層 (データベース操作)
│   │   ├── post.lua
│   │   ├── user.lua
│   │   └── comment.lua
│   │
│   ├── views/                 # ビュー層 (テンプレート)
│   │   ├── layout.html
│   │   ├── home.html
│   │   ├── post.html
│   │   └── admin/
│   │       ├── dashboard.html
│   │       └── edit_post.html
│   │
│   ├── middleware/            # ミドルウェア
│   │   ├── auth.lua
│   │   └── logger.lua
│   │
│   ├── utils/                 # ユーティリティ関数
│   │   ├── database.lua
│   │   ├── validator.lua
│   │   └── helpers.lua
│   │
│   └── static/                # 静的ファイル
│       ├── css/
│       ├── js/
│       └── images/
│
├── nginx/                     # Nginx設定ファイル
│   ├── nginx.conf             # メインのNginx設定
│   └── conf.d/
│       └── default.conf       # サイト設定
│
├── mysql/                     # MySQL関連
│   └── init/                  # 初期化SQLスクリプト
│       ├── 01_schema.sql      # テーブル定義
│       └── 02_seed.sql        # 初期データ
│
└── logs/                      # ログファイル
    ├── access.log
    └── error.log
```

## 5. Nginx設定ファイル

### nginx.conf (メイン設定)

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Lua共有辞書の設定
    lua_shared_dict sessions 10m;
    lua_shared_dict cache 10m;

    # Luaパッケージパスの設定
    lua_package_path "/app/?.lua;/app/?/init.lua;;";

    include /etc/nginx/conf.d/*.conf;
}
```

### conf.d/default.conf (サイト設定)

```nginx
server {
    listen 80;
    server_name localhost;

    root /app/static;
    index index.html;

    # 静的ファイルの配信
    location /static/ {
        alias /app/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Lua処理のエンドポイント
    location / {
        default_type 'text/html';
        content_by_lua_file /app/init.lua;
    }

    # APIエンドポイント
    location /api/ {
        default_type 'application/json';
        content_by_lua_file /app/routes.lua;
    }

    # 管理画面
    location /admin/ {
        default_type 'text/html';
        content_by_lua_file /app/controllers/admin_controller.lua;
    }

    # エラーページ
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
}
```

## 6. MySQL設定

### バージョン

- MySQL 8.0 (最新の安定版)

### 環境変数

| 変数名 | 値 | 説明 |
|--------|-----|------|
| MYSQL_ROOT_PASSWORD | root_password | rootユーザーのパスワード |
| MYSQL_DATABASE | LuaAIDiary | 初期データベース名 |
| MYSQL_USER | LuaAIDiary_user | アプリケーション用ユーザー |
| MYSQL_PASSWORD | LuaAIDiary_pass | アプリケーション用パスワード |
| MYSQL_CHARACTER_SET_SERVER | utf8mb4 | 文字セット |
| MYSQL_COLLATION_SERVER | utf8mb4_unicode_ci | 照合順序 |

### 初期化スクリプト (01_schema.sql)

```sql
-- ユーザーテーブル
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    role ENUM('admin', 'editor', 'author', 'subscriber') DEFAULT 'subscriber',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 投稿テーブル
CREATE TABLE IF NOT EXISTS posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    content TEXT,
    excerpt TEXT,
    author_id INT NOT NULL,
    status ENUM('draft', 'published', 'trash') DEFAULT 'draft',
    published_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_slug (slug),
    INDEX idx_status (status),
    INDEX idx_published_at (published_at),
    INDEX idx_author_id (author_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- コメントテーブル
CREATE TABLE IF NOT EXISTS comments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    author_name VARCHAR(100) NOT NULL,
    author_email VARCHAR(100) NOT NULL,
    content TEXT NOT NULL,
    status ENUM('pending', 'approved', 'spam', 'trash') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_post_id (post_id),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- カテゴリーテーブル
CREATE TABLE IF NOT EXISTS categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 投稿とカテゴリーの中間テーブル
CREATE TABLE IF NOT EXISTS post_categories (
    post_id INT NOT NULL,
    category_id INT NOT NULL,
    PRIMARY KEY (post_id, category_id),
    FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- タグテーブル
CREATE TABLE IF NOT EXISTS tags (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    slug VARCHAR(50) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 投稿とタグの中間テーブル
CREATE TABLE IF NOT EXISTS post_tags (
    post_id INT NOT NULL,
    tag_id INT NOT NULL,
    PRIMARY KEY (post_id, tag_id),
    FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

## 7. ポート設定とネットワーク構成

### ポートマッピング

| サービス | コンテナポート | ホストポート | 用途 |
|----------|----------------|--------------|------|
| web | 80 | 8080 | HTTP通信 |
| db | 3306 | 3306 | MySQL接続 (開発用) |

### ネットワーク構成

- **ネットワーク名**: `LuaAIDiary-network`
- **ドライバー**: bridge
- **サービス間通信**: 
  - Webコンテナからデータベースへの接続: `db:3306`
  - 内部DNS名でサービス名を使用

### セキュリティ考慮事項

- 本番環境ではMySQLの3306ポートを外部公開しない
- 環境変数は`.env`ファイルで管理し、`.gitignore`に追加
- パスワードは強固なものに変更

## 8. 必要な設定ファイル一覧

### 必須ファイル

1. `docker-compose.yml` - Docker Compose設定
2. `Dockerfile` - Webサーバー用コンテナイメージ
3. `nginx/nginx.conf` - Nginxメイン設定
4. `nginx/conf.d/default.conf` - サイト別設定
5. `mysql/init/01_schema.sql` - データベーススキーマ定義
6. `.env` - 環境変数設定 (任意)
7. `.gitignore` - Gitで管理しないファイルの指定

### アプリケーションファイル

1. `app/init.lua` - アプリケーションエントリーポイント
2. `app/config.lua` - アプリケーション設定
3. `app/routes.lua` - ルーティング定義
4. `app/utils/database.lua` - データベース接続ユーティリティ

## 9. 開発フロー

### 初期セットアップ

```bash
# プロジェクトのクローン
cd LuaAIDiary

# コンテナのビルドと起動
docker-compose up -d --build

# ログの確認
docker-compose logs -f

# ブラウザでアクセス
# http://localhost:8080
```

### 開発中の作業

```bash
# コンテナの停止
docker-compose stop

# コンテナの起動
docker-compose start

# コンテナの再起動
docker-compose restart web

# データベースへの接続
docker-compose exec db mysql -u LuaAIDiary_user -p LuaAIDiary

# Webコンテナへの接続
docker-compose exec web sh

# ログの確認
docker-compose logs -f web
```

### データベースのバックアップとリストア

```bash
# バックアップ
docker-compose exec db mysqldump -u root -p LuaAIDiary > backup.sql

# リストア
docker-compose exec -T db mysql -u root -p LuaAIDiary < backup.sql
```

## 10. 各サービス間の連携方法

### WebコンテナからMySQLへの接続

Luaコード内でのデータベース接続例:

```lua
local mysql = require "resty.mysql"

local db = mysql:new()
db:set_timeout(1000)

local ok, err, errcode, sqlstate = db:connect({
    host = os.getenv("MYSQL_HOST") or "db",
    port = tonumber(os.getenv("MYSQL_PORT")) or 3306,
    database = os.getenv("MYSQL_DATABASE") or "LuaAIDiary",
    user = os.getenv("MYSQL_USER") or "LuaAIDiary_user",
    password = os.getenv("MYSQL_PASSWORD") or "LuaAIDiary_pass",
    charset = "utf8mb4",
    max_packet_size = 1024 * 1024
})

if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
    return nil
end
```

### 環境変数の受け渡し

- `docker-compose.yml`の`environment`セクションでWebコンテナに環境変数を設定
- Luaコード内で`os.getenv()`を使用して取得

### ボリュームマウントによるコード共有

- `./app`ディレクトリをコンテナの`/app`にマウント
- ホスト側でコードを編集すると即座にコンテナに反映
- OpenRestyの設定変更時は`docker-compose restart web`で反映

## 11. パフォーマンスとスケーラビリティの考慮

### キャッシュ戦略

- Lua共有辞書を使用した簡易キャッシュ
- 将来的にRedisの追加を検討

### データベース最適化

- 適切なインデックスの設定
- クエリの最適化
- コネクションプーリングの活用

### 水平スケーリング

- 複数のWebコンテナを起動可能
- ロードバランサー (Nginx/HAProxy) の追加
- セッション管理の外部化 (Redis等)

## 12. 今後の拡張性

### 追加可能なサービス

- Redis: キャッシュ/セッションストア
- Elasticsearch: 全文検索
- MinIO/S3: メディアファイルストレージ
- phpMyAdmin: データベース管理UI

### 監視とロギング

- Prometheus + Grafana: メトリクス監視
- ELKスタック: ログ集約と分析

## まとめ

本設計書は、Docker Composeを使用してLuaベースのWordPressライクなブログシステムを構築するための包括的なアーキテクチャを提供します。OpenRestyとMySQLの組み合わせにより、高性能で拡張性のあるシステムを実現できます。