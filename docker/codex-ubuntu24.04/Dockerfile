FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONUTF8=1
ENV PYTHONIOENCODING=UTF-8
ENV PATH="/root/.local/bin:/usr/local/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 最小依赖集：Ubuntu 基础镜像已带 bash，Codex standalone 自带 bwrap/rg。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        nodejs \
        npm \
        python3 \
        vim \
    && rm -rf /var/lib/apt/lists/*

# 安装 uv/uvx 与 mcp-proxy，并把 uv tool 目录纳入全局 PATH。
RUN curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv-install.sh \
    && sh /tmp/uv-install.sh \
    && rm -f /tmp/uv-install.sh \
    && /root/.local/bin/uv tool install git+https://github.com/sparfenyuk/mcp-proxy \
    && ln -sf /root/.local/bin/uv /usr/local/bin/uv \
    && ln -sf /root/.local/bin/uvx /usr/local/bin/uvx \
    && ln -sf /root/.local/bin/mcp-proxy /usr/local/bin/mcp-proxy \
    && node -v \
    && npm -v \
    && npx -v \
    && uv --version \
    && uvx --version \
    && mcp-proxy --version \
    && git --version \
    && python3 --version

# 使用 Codex 官方安装脚本安装 CLI，构建阶段立刻校验版本可执行。
RUN curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/codex-install.sh \
    && CODEX_NON_INTERACTIVE=1 sh /tmp/codex-install.sh \
    && rm -f /tmp/codex-install.sh \
    && codex --version

# 预创建 hook 插件目录，避免 COPY 目标路径不存在。
RUN mkdir -p \
        /root/.codex/codex_hook/plugins/agents_guard \
        /root/.codex/codex_hook/plugins/feishu \
        /root/.codex/codex_hook/plugins/session_title \
        /root/.codex/codex_hook/plugins/session_title_v2

# 安装本仓库 Codex hook 框架到容器 root 用户的 Codex 配置目录。
COPY shell/codex_hook/codex_hook.sh /root/.codex/codex_hook/codex_hook.sh
COPY shell/codex_hook/codex_hook.ps1 /root/.codex/codex_hook/codex_hook.ps1
COPY shell/codex_hook/hook.py /root/.codex/codex_hook/hook.py
COPY shell/codex_hook/README.md /root/.codex/codex_hook/README.md
COPY shell/codex_hook/.env.example /root/.codex/codex_hook/.env.example
COPY shell/codex_hook/plugins/__init__.py /root/.codex/codex_hook/plugins/__init__.py
COPY shell/codex_hook/plugins/agents_guard/__init__.py /root/.codex/codex_hook/plugins/agents_guard/__init__.py
COPY shell/codex_hook/plugins/agents_guard/hook.py /root/.codex/codex_hook/plugins/agents_guard/hook.py
COPY shell/codex_hook/plugins/feishu/__init__.py /root/.codex/codex_hook/plugins/feishu/__init__.py
COPY shell/codex_hook/plugins/feishu/hook.py /root/.codex/codex_hook/plugins/feishu/hook.py
COPY shell/codex_hook/plugins/feishu/.env.example /root/.codex/codex_hook/plugins/feishu/.env.example
COPY shell/codex_hook/plugins/session_title/__init__.py /root/.codex/codex_hook/plugins/session_title/__init__.py
COPY shell/codex_hook/plugins/session_title/hook.py /root/.codex/codex_hook/plugins/session_title/hook.py
COPY shell/codex_hook/plugins/session_title_v2/__init__.py /root/.codex/codex_hook/plugins/session_title_v2/__init__.py
COPY shell/codex_hook/plugins/session_title_v2/hook.py /root/.codex/codex_hook/plugins/session_title_v2/hook.py
COPY shell/codex_hook/plugins/session_title_v2/.env.example /root/.codex/codex_hook/plugins/session_title_v2/.env.example

# 安装 hook 版全局 AGENTS 规则到 Codex 默认读取位置。
COPY agents/AGENTS_SDP_AI_LOCALBASE_hook_v8.md /root/.codex/AGENTS.md

# 生成 Linux hooks.json，并在构建阶段校验 Python hook 代码可编译。
RUN chmod +x /root/.codex/codex_hook/codex_hook.sh \
    && cp /root/.codex/codex_hook/.env.example /root/.codex/codex_hook/.env \
    && cp /root/.codex/codex_hook/plugins/feishu/.env.example /root/.codex/codex_hook/plugins/feishu/.env \
    && cp /root/.codex/codex_hook/plugins/session_title_v2/.env.example /root/.codex/codex_hook/plugins/session_title_v2/.env \
    && /root/.codex/codex_hook/codex_hook.sh create linux \
    && python3 -m py_compile \
        /root/.codex/codex_hook/hook.py \
        /root/.codex/codex_hook/plugins/agents_guard/hook.py \
        /root/.codex/codex_hook/plugins/feishu/hook.py \
        /root/.codex/codex_hook/plugins/session_title/hook.py \
        /root/.codex/codex_hook/plugins/session_title_v2/hook.py \
    && test -f /root/.codex/AGENTS.md \
    && test -f /root/.codex/hooks.json \
    && mkdir -p /opt/codex-home \
    && cp -a /root/.codex/. /opt/codex-home/

WORKDIR /workspace

CMD ["codex"]
