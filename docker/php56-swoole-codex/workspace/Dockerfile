FROM php:5.6-cli-alpine AS php-runtime

LABEL maintainer="zhiliao Developers <zengsp.mail@qq.com>" \
    app.name="ZhiliaoWorkspace" \
    app.runtime="php5.6"

ARG TZ=Asia/Shanghai

ENV TZ=${TZ} \
    GO_VERSION=1.26.4 \
    GO_SHA256=1153d3d50e0ac764b447adfe05c2bcf08e889d42a02e0fe0259bd47f6733ad7f

COPY swoole-src-1.9.16.tar.gz /tmp/swoole-src-1.9.16.tar.gz

# PHP 5.6 阶段保留原业务运行能力：内置扩展、PECL 旧扩展、本地 Swoole 1.9.16。
RUN set -eux; \
    apk add --no-cache \
        freetype-dev \
        hiredis-dev \
        libjpeg-turbo-dev \
        libmemcached-dev \
        libmcrypt-dev \
        libpng-dev \
        libxml2-dev \
        openssl-dev \
        zlib-dev; \
    apk add --no-cache --virtual .build-deps ${PHPIZE_DEPS} linux-headers; \
    docker-php-source extract; \
    docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/; \
    docker-php-ext-install -j"$(nproc)" bcmath gd mcrypt pdo_mysql sockets; \
    pecl install \
        igbinary-2.0.8 \
        redis-4.3.0 \
        mongodb-1.6.1 \
        memcached-2.2.0; \
    pecl download memcache-3.0.8; \
    mkdir -p /tmp/memcache; \
    tar -xzf memcache-3.0.8.tgz -C /tmp/memcache --strip-components=1; \
    ( \
        cd /tmp/memcache; \
        sed -i 's/^inline //' memcache_pool.h memcache_pool.c; \
        sed -i 's/^#define MMC_QUEUE_INLINE inline/#define MMC_QUEUE_INLINE/' memcache_queue.h; \
        phpize --clean; \
        phpize; \
        ./configure; \
        make clean; \
        make -j1; \
        make install; \
    ); \
    docker-php-ext-enable igbinary redis memcache mongodb memcached; \
    mkdir -p /tmp/swoole-src; \
    tar -xzf /tmp/swoole-src-1.9.16.tar.gz -C /tmp/swoole-src --strip-components=1; \
    ( \
        cd /tmp/swoole-src; \
        phpize --clean; \
        phpize; \
        CFLAGS="${CFLAGS:-} -DHAVE_SOCKETS=1" ./configure --enable-openssl --enable-sockets --enable-async-redis; \
        make clean; \
        make -j"$(nproc)"; \
        make install; \
    ); \
    echo "extension=swoole.so" > /usr/local/etc/php/conf.d/docker-php-ext-swoole.ini; \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime; \
    echo "${TZ}" > /etc/timezone; \
    php -m | grep -E '^(bcmath|gd|igbinary|mcrypt|memcache|memcached|mongodb|pdo_mysql|redis|sockets|swoole)$'; \
    docker-php-source delete; \
    apk del .build-deps; \
    rm -rf /tmp/*

FROM node:22-bookworm-slim

LABEL maintainer="zhiliao Developers <zengsp.mail@qq.com>" \
    app.name="ZhiliaoWorkspace" \
    app.runtime="php5.6"

ARG TZ=Asia/Shanghai

ENV TZ=${TZ} \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUTF8=1 \
    PYTHONIOENCODING=UTF-8 \
    GO_VERSION=1.26.4 \
    GO_SHA256=1153d3d50e0ac764b447adfe05c2bcf08e889d42a02e0fe0259bd47f6733ad7f

# 运行期使用 Debian 12 + Node 22，保留 bash/apt；PHP 5.6 和旧扩展由 Alpine 阶段提供。
COPY --from=php-runtime /usr/local/bin/php /usr/local/bin/php-real
COPY --from=php-runtime /usr/local/lib/php /usr/local/lib/php
COPY --from=php-runtime /usr/local/etc/php /usr/local/etc/php
COPY --from=php-runtime /usr/local/include/php /usr/local/include/php
COPY --from=php-runtime /usr/lib/ /opt/php-legacy/usr/lib/
COPY --from=php-runtime /lib/ /opt/php-legacy/lib/

# 安装 Codex / Claude / Docker 辅助工具链：Docker CLI 通过 Compose 挂载的宿主机 socket 执行宿主机 Docker。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        curl \
        docker.io \
        git \
        procps \
        python3 \
        tzdata \
        vim \
        zsh; \
    rm -rf /var/lib/apt/lists/*; \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime; \
    echo "${TZ}" > /etc/timezone; \
    ln -sf /opt/php-legacy/lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1; \
    # 让 musl 版 php-real 裸执行时也能找到从 Alpine 阶段复制来的旧运行库。 \
    printf '%s\n' '/opt/php-legacy/lib:/opt/php-legacy/usr/lib:/lib:/usr/local/lib:/usr/lib' > /etc/ld-musl-x86_64.path; \
    { \
        echo '#!/bin/bash'; \
        echo 'export LD_LIBRARY_PATH="/opt/php-legacy/usr/lib:/opt/php-legacy/lib:${LD_LIBRARY_PATH:-}"'; \
        echo 'export OPENSSL_CONF=/dev/null'; \
        echo 'exec /usr/local/bin/php-real "$@"'; \
    } > /usr/local/bin/php; \
    chmod +x /usr/local/bin/php; \
    \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz; \
    echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum -c -; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm -f /tmp/go.tar.gz; \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
    \
    npm install -g @openai/codex @anthropic-ai/claude-code; \
    npm cache clean --force; \
    rm -rf /root/.npm /root/.cache; \
    CODEX_VENDOR_DIR="$(find /usr/local/lib/node_modules/@openai/codex \( -path '*/x86_64-unknown-linux-gnu' -o -path '*/x86_64-unknown-linux-musl' \) -type d | head -n 1)"; \
    ln -sf "${CODEX_VENDOR_DIR}/codex-path/rg" /usr/local/bin/rg; \
    \
    curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv-install.sh; \
    sh /tmp/uv-install.sh; \
    rm -f /tmp/uv-install.sh; \
    /root/.local/bin/uv tool install git+https://github.com/sparfenyuk/mcp-proxy; \
    rm -rf /root/.cache; \
    ln -sf /root/.local/bin/uv /usr/local/bin/uv; \
    ln -sf /root/.local/bin/uvx /usr/local/bin/uvx; \
    ln -sf /root/.local/bin/mcp-proxy /usr/local/bin/mcp-proxy; \
    \
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended; \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions; \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting; \
    node --version; \
    npm --version; \
    codex --version; \
    claude --version; \
    docker --version; \
    php-real -v; \
    php-real -m | grep -E '^(bcmath|gd|igbinary|mcrypt|memcache|memcached|mongodb|pdo_mysql|redis|sockets|swoole)$'; \
    go version; \
    python3 --version; \
    vim --version | head -n 1; \
    bwrap --version; \
    uv --version; \
    uvx --version; \
    mcp-proxy --version; \
    zsh --version

CMD ["php", "-a"]
