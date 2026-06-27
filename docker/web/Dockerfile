# ==========================================
# 1. ビルド用ステージ（C拡張のコンパイルを実行）
# ==========================================
FROM openresty/openresty:alpine AS builder

# 必要なビルドツールのインストール
RUN apk add --no-cache \
    git \
    gcc \
    g++ \
    make \
    musl-dev \
    openssl-dev \
    postgresql-dev \
    lua5.1 \
    lua5.1-dev \
    luarocks5.1 \
    vips-dev \
    unzip

# 必要なLuaモジュールのインストール
# 基準の先頭に luabitop を戻しています
RUN luarocks-5.1 install luabitop \
    && luarocks-5.1 install lapis \
    && luarocks-5.1 install lua-resty-redis \
    && luarocks-5.1 install lua-resty-http \
    && luarocks-5.1 install lua-cjson \
    && luarocks-5.1 install pgmoon \
    && luarocks-5.1 install bcrypt \
    && luarocks-5.1 install busted \
    && luarocks-5.1 install luacheck \
    && luarocks-5.1 install lua-resty-template \
    && luarocks-5.1 install lua-resty-session \
    && luarocks-5.1 install lua-resty-rsa \
    && luarocks-5.1 install lua-resty-upload

# ==========================================
# 2. 実行用ステージ（本番用の軽量イメージ）
# ==========================================
FROM openresty/openresty:alpine

ARG APP_VERSION=Unknown
ENV APP_VERSION=${APP_VERSION}

# ビルダーステージから、コンパイル済みの LuaRocks ライブラリ群（luabitop含む）をコピー
COPY --from=builder /usr/local/share/lua/ /usr/local/share/lua/
COPY --from=builder /usr/local/lib/lua/ /usr/local/lib/lua/

# サムネイル生成に利用するlibvips CLIをインストール
RUN apk add --no-cache vips

# 作業ディレクトリの設定
WORKDIR /app

# アプリケーション本体・設定ファイルをイメージに同梱
COPY app/ /app/
COPY wp-content/ /app/wp-content/
COPY static/ /usr/local/openresty/nginx/html/static/
COPY docker/web/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Nginxキャッシュディレクトリの作成
RUN mkdir -p /var/cache/nginx/luaaidiary \
    && chown -R nobody:nobody /var/cache/nginx/luaaidiary

# ポート80を公開
EXPOSE 80

# アップロード用ボリュームをworkerプロセス(nobody)から書き込める状態にしてOpenRestyを起動
CMD ["/bin/sh", "-c", "mkdir -p /app/uploads && chown -R nobody:nobody /app/uploads && exec /usr/local/openresty/bin/openresty -g 'daemon off;'"]
