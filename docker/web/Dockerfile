# ==========================================
# 1. ビルド用ステージ（OpenResty + LuaJIT Plus + C拡張のコンパイルを実行）
# ==========================================
FROM alpine:3.22 AS builder

# OPENRESTY_VERSION=latest の場合は公式ダウンロードページから最新安定版を解決する。
# 再現性を優先する場合は docker compose build --build-arg OPENRESTY_VERSION=1.31.1.1 のように固定できる。
ARG OPENRESTY_VERSION=latest
ARG LUAJIT_PLUS_REF=8cd19064101f46bf0ab713e5dab9d83a77e73909

# OpenResty/LuaJIT Plus と LuaRocks モジュールのビルドに必要なツールをインストール
RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    findutils \
    curl \
    git \
    gcc \
    g++ \
    linux-headers \
    lua5.1 \
    lua5.1-dev \
    make \
    musl-dev \
    openssl-dev \
    pcre-dev \
    pcre2-dev \
    perl \
    postgresql-dev \
    readline-dev \
    unzip \
    vips-dev \
    wget \
    zlib-dev

# OpenResty の bundled LuaJIT を LuaJIT Plus に置き換えてビルド
WORKDIR /tmp/build
RUN set -eux; \
    if [ "${OPENRESTY_VERSION}" = "latest" ]; then \
        resolved_version="$(wget -q -O - https://openresty.org/en/download.html \
            | grep -oE 'openresty-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
            | sed -E 's/openresty-([0-9.]+)\.tar\.gz/\1/' \
            | sort -Vr \
            | head -n 1)"; \
    else \
        resolved_version="${OPENRESTY_VERSION}"; \
    fi; \
    test -n "${resolved_version}"; \
    wget -q -O openresty.tar.gz "https://openresty.org/download/openresty-${resolved_version}.tar.gz"; \
    tar -xzf openresty.tar.gz; \
    git clone --depth 1 https://github.com/HenryMarkle/luajit-plus.git luajit-plus; \
    cd luajit-plus; \
    git fetch --depth 1 origin "${LUAJIT_PLUS_REF}"; \
    git checkout "${LUAJIT_PLUS_REF}"; \
    cd "/tmp/build/openresty-${resolved_version}/bundle"; \
    luajit_bundle_dir="$(find . -maxdepth 1 -type d -name 'LuaJIT-*' -printf '%f\n' | head -n 1)"; \
    test -n "${luajit_bundle_dir}"; \
    rm -rf "${luajit_bundle_dir}"; \
    cp -a /tmp/build/luajit-plus "${luajit_bundle_dir}"; \
    cd "/tmp/build/openresty-${resolved_version}"; \
    ./configure \
        --prefix=/usr/local/openresty \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-pcre-jit; \
    make -j"$(nproc)"; \
    make install; \
    /usr/local/openresty/luajit/bin/luajit -e 'print(_VERSION)'; \
    /usr/local/openresty/bin/openresty -V

# LuaRocks を LuaJIT Plus 向けにブートストラップ
RUN wget -q -O luarocks.tar.gz https://luarocks.org/releases/luarocks-3.12.2.tar.gz \
    && tar -xzf luarocks.tar.gz \
    && cd luarocks-3.12.2 \
    && ./configure \
        --prefix=/usr/local \
        --lua-version=5.1 \
        --with-lua=/usr \
        --with-lua-bin=/usr/bin \
        --with-lua-include=/usr/include \
    && make \
    && make install

# LuaRocks 本体は LuaJIT Plus の追加キーワードと衝突し得るため通常 Lua 5.1 で実行し、
# rocks の配置先と C 拡張のヘッダー/ライブラリだけ OpenResty/LuaJIT Plus に向ける。
RUN cat > /usr/local/etc/luarocks/config-5.1.lua <<'EOF'
lua_version = "5.1"
lua_interpreter = "lua5.1"
variables = {
   LUA = "/usr/bin/lua5.1",
   LUA_DIR = "/usr/local/openresty/luajit",
   LUA_BINDIR = "/usr/local/openresty/luajit/bin",
   LUA_INCDIR = "/usr/local/openresty/luajit/include/luajit-2.1",
   LUA_LIBDIR = "/usr/local/openresty/luajit/lib",
}
rocks_trees = {
   { name = "system", root = "/usr/local" },
}
EOF

# 必要な Lua モジュールを LuaJIT Plus と同じ ABI/ヘッダーでインストール
# luabitop は LuaJIT Plus VM が提供するため明示インストールしない。
RUN luarocks install lapis \
    && luarocks install lua-resty-redis \
    && luarocks install lua-resty-http \
    && luarocks install lua-cjson \
    && luarocks install pgmoon \
    && luarocks install bcrypt \
    && luarocks install busted \
    && luarocks install luacheck \
    && luarocks install lua-resty-template \
    && luarocks install lua-resty-session \
    && luarocks install lua-resty-rsa \
    && luarocks install lua-resty-upload

# ==========================================
# 2. 実行用ステージ（本番用の軽量イメージ）
# ==========================================
FROM alpine:3.22

ARG APP_VERSION=Unknown
ENV APP_VERSION=${APP_VERSION}

# OpenResty/LuaJIT Plus と LuaRocks ライブラリ群をコピー
COPY --from=builder /usr/local/openresty/ /usr/local/openresty/
COPY --from=builder /usr/local/bin/ /usr/local/bin/
COPY --from=builder /usr/local/share/lua/ /usr/local/share/lua/
COPY --from=builder /usr/local/lib/lua/ /usr/local/lib/lua/

# OpenResty と LuaRocks モジュールの実行時依存をインストール
RUN apk add --no-cache \
    libgcc \
    libstdc++ \
    openssl \
    pcre \
    pcre2 \
    postgresql-libs \
    readline \
    vips \
    zlib

ENV PATH="/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/luajit/bin:${PATH}"

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
