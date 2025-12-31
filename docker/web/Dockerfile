FROM openresty/openresty:alpine

# 必要なパッケージのインストール
RUN apk add --no-cache \
    git \
    gcc \
    g++ \
    make \
    musl-dev \
    openssl-dev \
    postgresql-dev \
    postgresql-client \
    lua5.1 \
    lua5.1-dev \
    luarocks5.1 \
    unzip

# 必要なLuaモジュールのインストール
RUN luarocks-5.1 install lapis \
    && luarocks-5.1 install lua-resty-redis \
    && luarocks-5.1 install lua-resty-http \
    && luarocks-5.1 install lua-cjson \
    && luarocks-5.1 install pgmoon \
    && luarocks-5.1 install bcrypt \
    && luarocks-5.1 install busted \
    && luarocks-5.1 install luacheck \
    && luarocks-5.1 install lua-resty-template \
    && luarocks-5.1 install lua-resty-session \
    && luarocks-5.1 install lua-resty-rsa

# 作業ディレクトリの設定
WORKDIR /app

# Nginxキャッシュディレクトリの作成
RUN mkdir -p /var/cache/nginx/luaaidiary \
    && chown -R nobody:nobody /var/cache/nginx/luaaidiary

# ポート80を公開
EXPOSE 80

# OpenRestyの起動
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
