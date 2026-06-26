FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONUTF8=1
ENV PYTHONIOENCODING=UTF-8

ARG GO_VERSION=1.26.4
ARG GO_SHA256=1153d3d50e0ac764b447adfe05c2bcf08e889d42a02e0fe0259bd47f6733ad7f

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 最小依赖集：Node 官方 bookworm-slim 已提供 node/npm；Docker CLI 通过宿主机 socket 执行宿主机 Docker。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        curl \
        docker.io \
        docker-compose \
        git \
        procps \
        python3 \
        vim \
        zsh \
    && rm -rf /var/lib/apt/lists/*

# 安装官方 Go 二进制包；固定 checksum，避免 apt golang-go 拉入更大的依赖树。
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum -c - \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm -f /tmp/go.tar.gz \
    && ln -sf /usr/local/go/bin/go /usr/local/bin/go \
    && ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
    && go version

# 安装 uv/uvx 与 mcp-proxy，并把 uv tool 目录纳入全局 PATH。
RUN curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv-install.sh \
    && sh /tmp/uv-install.sh \
    && rm -f /tmp/uv-install.sh \
    && /root/.local/bin/uv tool install git+https://github.com/sparfenyuk/mcp-proxy \
    && rm -rf /root/.cache \
    && ln -sf /root/.local/bin/uv /usr/local/bin/uv \
    && ln -sf /root/.local/bin/uvx /usr/local/bin/uvx \
    && ln -sf /root/.local/bin/mcp-proxy /usr/local/bin/mcp-proxy \
    && node -v \
    && npm -v \
    && npx -v \
    && uv --version \
    && uvx --version \
    && mcp-proxy --version \
    && docker --version \
    && docker-compose --version \
    && git --version \
    && python3 --version

# 安装最新 npm 版 Codex CLI 与 Claude Code CLI，复用 Node 22 全局工具链。
RUN npm install -g @openai/codex @anthropic-ai/claude-code \
    && npm cache clean --force \
    && rm -rf /root/.npm /root/.cache \
    && codex --version \
    && claude --version

# 安装 Oh My Zsh 与插件；.zshrc 由 docker-compose 从项目目录挂载。
RUN RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

WORKDIR /workspace

CMD ["zsh"]
