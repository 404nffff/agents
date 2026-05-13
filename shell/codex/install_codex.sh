#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${0:-}"
if [[ -n "${BASH_SOURCE:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
fi

SCRIPT_DIR=""
if [[ -n "${SCRIPT_PATH}" && "${SCRIPT_PATH}" == */* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

REPO_ROOT="${SCRIPT_DIR}"
if [[ "${SCRIPT_DIR}" == */shell/codex ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
elif [[ "${SCRIPT_DIR}" == */shell ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

IS_NETWORK_REQUEST_EXECUTION="false"
case "${SCRIPT_PATH}" in
  /dev/fd/*|/proc/self/fd/*|/dev/stdin|stdin|-)
    IS_NETWORK_REQUEST_EXECUTION="true"
    ;;
esac
if [[ "${IS_NETWORK_REQUEST_EXECUTION}" != "true" && ! -f "${SCRIPT_PATH}" ]]; then
  case "${SCRIPT_PATH}" in
    bash|-bash|sh|-sh)
      IS_NETWORK_REQUEST_EXECUTION="true"
      ;;
  esac
fi

DEFAULT_GITHUB_REPO="404nffff/agents"
DEFAULT_GITHUB_REF="master"
DB_QUERY_RELEASE_TAG="${DB_QUERY_RELEASE_TAG:-}"
DB_QUERY_RELEASE_REPO="${DB_QUERY_RELEASE_REPO:-}"
DB_QUERY_RELEASE_BASE_URL="${DB_QUERY_RELEASE_BASE_URL:-}"
DB_QUERY_REMOTE_DOWNLOAD="${DB_QUERY_REMOTE_DOWNLOAD:-}"
DB_QUERY_RELEASE_TAG_EXPLICIT="false"
if [[ -n "${DB_QUERY_RELEASE_TAG}" ]]; then
  DB_QUERY_RELEASE_TAG_EXPLICIT="true"
fi
DB_QUERY_REMOTE_DOWNLOAD_EXPLICIT="false"
if [[ -n "${DB_QUERY_REMOTE_DOWNLOAD}" ]]; then
  DB_QUERY_REMOTE_DOWNLOAD_EXPLICIT="true"
fi
AUTO_YES="false"
HELP_EXIT_CODE=100
CHOSEN_MODE=""

declare -a TMP_FILES=()
declare -a TMP_DIRS=()

new_tmp_file() {
  local p
  p="$(mktemp)"
  TMP_FILES+=("${p}")
  printf "%s\n" "${p}"
}

new_tmp_dir() {
  local p
  p="$(mktemp -d)"
  TMP_DIRS+=("${p}")
  printf "%s\n" "${p}"
}

cleanup() {
  local f d
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "${f}" && -f "${f}" ]] && rm -f "${f}" || true
  done
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "${d}" && -d "${d}" ]] && rm -rf "${d}" || true
  done
}

handle_interrupt() {
  echo
  echo "已取消安装（Ctrl+C）。"
  exit 130
}

trap cleanup EXIT
trap handle_interrupt INT

usage() {
  cat <<'EOF'
用法:
  ./shell/codex/install_codex.sh
  ./shell/codex/install_codex.sh <mcp|agents|skills|all> [目标参数...]
  ./shell/codex/install_codex.sh --target <mcp|agents|skills|all> [目标参数...]
  ./shell/codex/install_codex.sh --mcp|--agents|--skills|--all [目标参数...]

说明:
  1) 不带参数时，进入交互菜单选择安装目标
  2) 各目标参数与原脚本基本兼容，详情见:
     - ./shell/codex/install_codex.sh mcp --help
     - ./shell/codex/install_codex.sh agents --help
     - ./shell/codex/install_codex.sh skills --help
  3) mcp / agents / skills 都必须先列出可安装项，用户手动选择后输入 d 才开始安装
EOF
}

agents_usage() {
  cat <<'EOF'
用法:
  ./shell/codex/install_codex.sh agents
  ./shell/codex/install_codex.sh agents [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--agents-path <path_in_repo>]
  ./shell/codex/install_codex.sh agents [--source <path_or_url>]
  ./shell/codex/install_codex.sh agents [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--file <path_in_repo>]

说明:
  1) 本地执行优先扫描本地 agents 目录
  2) 网络请求执行时，先读取远程 agents/README.md 展示可选 agent 文件列表
  3) 只能单选一个 agent 文件；选择 README 入口或 *GLOBAL*.md 时写入 ~/.codex/AGENTS.md，选择其他 agent 文件时写入当前项目 AGENTS.md
  4) 可通过 --github / --ref / --agents-path 指定远程来源
  5) 若本地存在同名文件，提示是否覆盖
  6) 兼容单文件安装：可使用 --source 或 --file 直接安装单个文件
  7) 必须手动选择要安装的 agent 文件

  --source       单个 agent 文件源地址，可为本地路径或 http(s) URL
  --github   GitHub 仓库地址（owner/repo 或完整 URL）
  --ref      GitHub 分支或标签，默认 master
  --agents-path  仓库内 agents 目录路径，默认 agents
  --file     仓库内单个 agent 文件路径（与 --github 搭配）
EOF
}

skills_usage() {
  cat <<'EOF'
用法:
  ./shell/codex/install_codex.sh skills
  ./shell/codex/install_codex.sh skills [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--skills-path <path_in_repo>] [--db-query-tag <tag>] [--db-query-download <yes|no>]

说明:
  1) 本地执行优先扫描本地 skills 目录
  2) 网络请求执行时，先读取远程 skills/README.md 展示可选 skill 列表
  3) 必须手动勾选要安装的 skill
  4) 可通过 --github / --ref / --skills-path 指定远程来源
  5) 安装到 ~/.codex/skills/
  6) 若本地存在同名 skill，提示是否覆盖

db-query 二进制发布地址可通过以下环境变量覆盖：
  DB_QUERY_RELEASE_BASE_URL  例如: https://github.com/owner/repo/releases/download/v0.1.0
  DB_QUERY_RELEASE_REPO      例如: owner/repo（默认 404nffff/agents）
  DB_QUERY_RELEASE_TAG       例如: v0.1.0（默认自动探测最近 tag）
  DB_QUERY_REMOTE_DOWNLOAD   yes|no（默认交互询问，--yes 下默认 yes）
EOF
}

mcp_usage() {
  cat <<'EOF'
用法:
  ./shell/codex/install_codex.sh mcp
  ./shell/codex/install_codex.sh mcp [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--mcp-path <path_in_repo>]
  ./shell/codex/install_codex.sh mcp [--source <path_or_url>] [--config <config_path>]

说明:
  1) 默认来源会自动判断：本地执行优先本地 mcp/*.md，网络请求执行优先远程仓库（404nffff/agents@master:mcp）
  2) 读取 ~/.codex/config.toml 的 mcp_servers 相关配置并对比
  3) 必须手动勾选要安装/更新的 mcp server
  4) 若目标已存在且配置不同，会逐项询问是否覆盖
  5) 仅修改 mcp_servers 段落，不改动 config.toml 其他内容
  6) 若选中配置包含空 token 或占位 token，会在写入前交互输入
EOF
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer=""
  local tty_opened="false"

  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi

  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  if [[ "${default}" == "Y" ]]; then
    if [[ "${tty_opened}" == "true" ]]; then
      printf "%s [Y/n]: " "${prompt}" >&9
      IFS= read -r answer <&9 || true
    else
      printf "%s [Y/n]: " "${prompt}"
      IFS= read -r answer || true
    fi
    answer="${answer:-Y}"
  else
    if [[ "${tty_opened}" == "true" ]]; then
      printf "%s [y/N]: " "${prompt}" >&9
      IFS= read -r answer <&9 || true
    else
      printf "%s [y/N]: " "${prompt}"
      IFS= read -r answer || true
    fi
    answer="${answer:-N}"
  fi

  if [[ "${tty_opened}" == "true" ]]; then
    exec 9<&-
  fi

  [[ "${answer}" =~ ^[Yy]$ ]]
}

normalize_github_repo() {
  local repo="$1"
  repo="${repo#https://github.com/}"
  repo="${repo#http://github.com/}"
  repo="${repo%.git}"
  printf "%s\n" "${repo}"
}

# 统一远程下载超时与重试，避免 GitHub 单次网络抖动让交互式安装看起来“卡死”。
curl_download_with_retry() {
  local url="$1"
  local out_file="$2"
  local max_attempts="${3:-2}"
  local connect_timeout="${4:-5}"
  local max_time="${5:-20}"
  local timeout_window="$((max_time + 5))"
  local attempt=1
  local -a curl_cmd=(
    curl -fsSL
    --connect-timeout "${connect_timeout}"
    --max-time "${max_time}"
    "${url}"
    -o "${out_file}"
  )

  while (( attempt <= max_attempts )); do
    if command -v timeout >/dev/null 2>&1; then
      if timeout "${timeout_window}s" "${curl_cmd[@]}" >/dev/null 2>&1; then
        return 0
      fi
    else
      if "${curl_cmd[@]}" >/dev/null 2>&1; then
        return 0
      fi
    fi
    attempt=$((attempt + 1))
  done

  return 1
}

run_with_timeout_if_available() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}s" "$@" >/dev/null 2>&1
  else
    "$@" >/dev/null 2>&1
  fi
}

git_sparse_checkout_repo_path() {
  local repo="$1"
  local ref="$2"
  local root_path="$3"
  local clone_dir="$4"
  shift 4
  local -a sparse_paths=("$@")
  local repo_url="https://github.com/${repo}.git"

  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  if [[ ${#sparse_paths[@]} -eq 0 ]]; then
    sparse_paths=("${root_path}")
  fi

  if ! run_with_timeout_if_available 90 git clone --depth 1 --branch "${ref}" --filter=blob:none --sparse "${repo_url}" "${clone_dir}"; then
    return 1
  fi

  if ! (
    cd "${clone_dir}" &&
    run_with_timeout_if_available 20 git sparse-checkout set "${sparse_paths[@]}"
  ); then
    if ! (
      cd "${clone_dir}" &&
      run_with_timeout_if_available 20 git sparse-checkout set "${sparse_paths[0]}" &&
      for ((i = 1; i < ${#sparse_paths[@]}; i++)); do
        run_with_timeout_if_available 20 git sparse-checkout add "${sparse_paths[i]}" || exit 1
      done
    ); then
      return 1
    fi
  fi

  if [[ ! -d "${clone_dir}/${root_path}" ]]; then
    return 1
  fi

  printf "%s\n" "${clone_dir}/${root_path}"
}

preview_file_head() {
  local file="$1"
  local lines="${2:-20}"
  local title="${3:-文件预览}"
  local total_lines
  total_lines="$(wc -l < "${file}" | tr -d ' ')"

  echo "----- ${title}（前 ${lines} 行）: ${file} -----"
  sed -n "1,${lines}p" "${file}"
  if (( total_lines > lines )); then
    echo "......(共 ${total_lines} 行，仅预览前 ${lines} 行)"
  fi
  echo "-------------------------------------------"
}

copy_local_or_url_to_file() {
  local source="$1"
  local out_file="$2"

  if [[ "${source}" =~ ^https?:// ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "错误: 需要 curl 来拉取 URL 源。" >&2
      exit 1
    fi
    if ! curl_download_with_retry "${source}" "${out_file}"; then
      echo "错误: 无法拉取 URL 源: ${source}" >&2
      exit 1
    fi
    return
  fi

  if [[ ! -f "${source}" ]]; then
    echo "错误: 源文件不存在: ${source}" >&2
    exit 1
  fi
  cp "${source}" "${out_file}"
}

fetch_raw_from_github() {
  local repo="$1"
  local ref="$2"
  local path="$3"
  local out_file="$4"
  local raw_url root_path clone_dir checkout_root file_name

  raw_url="https://raw.githubusercontent.com/${repo}/${ref}/${path}"
  if command -v curl >/dev/null 2>&1; then
    if curl_download_with_retry "${raw_url}" "${out_file}" 1 5 8; then
      return 0
    fi
    echo "警告: GitHub Raw 拉取失败，尝试 git sparse-checkout 回退: ${raw_url}" >&2
  fi

  if command -v git >/dev/null 2>&1; then
    root_path="$(dirname "${path}")"
    file_name="$(basename "${path}")"
    clone_dir="$(new_tmp_dir)/raw-sparse"
    checkout_root="$(git_sparse_checkout_repo_path "${repo}" "${ref}" "${root_path}" "${clone_dir}" "${root_path}" 2>/dev/null || true)"
    if [[ -n "${checkout_root}" && -f "${checkout_root}/${file_name}" ]]; then
      cp "${checkout_root}/${file_name}" "${out_file}"
      return 0
    fi
  fi

  echo "错误: 无法拉取 GitHub 源: ${raw_url}" >&2
  return 1
}

resolve_db_query_release_base_url_for_skills_install() {
  local source_mode="$1"
  local github_repo="$2"
  local resolved_tag
  local repo

  repo="$(resolve_db_query_release_repo_for_skills_install "${source_mode}" "${github_repo}")"

  if [[ -z "${DB_QUERY_RELEASE_TAG}" ]]; then
    resolved_tag="latest"
  else
    resolved_tag="${DB_QUERY_RELEASE_TAG}"
  fi

  if [[ "${resolved_tag}" == "latest" ]]; then
    printf "https://github.com/%s/releases/latest/download\n" "${repo}"
  else
    printf "https://github.com/%s/releases/download/%s\n" "${repo}" "${resolved_tag}"
  fi
}

resolve_db_query_release_repo_for_skills_install() {
  local source_mode="$1"
  local github_repo="$2"
  local repo=""

  if [[ -n "${DB_QUERY_RELEASE_REPO}" ]]; then
    repo="$(normalize_github_repo "${DB_QUERY_RELEASE_REPO}")"
  elif [[ "${source_mode}" == "github" && -n "${github_repo}" ]]; then
    repo="$(normalize_github_repo "${github_repo}")"
  else
    repo="${DEFAULT_GITHUB_REPO}"
  fi

  printf "%s\n" "${repo}"
}

resolve_db_query_release_page_url_for_skills_install() {
  local source_mode="$1"
  local github_repo="$2"
  local repo resolved_tag

  repo="$(resolve_db_query_release_repo_for_skills_install "${source_mode}" "${github_repo}")"
  resolved_tag="${DB_QUERY_RELEASE_TAG:-latest}"

  if [[ "${resolved_tag}" == "latest" ]]; then
    printf "https://github.com/%s/releases/latest\n" "${repo}"
  else
    printf "https://github.com/%s/releases/tag/%s\n" "${repo}" "${resolved_tag}"
  fi
}

resolve_db_query_release_asset_for_current_platform() {
  local os arch
  os="$(uname -s 2>/dev/null || printf "unknown")"
  arch="$(uname -m 2>/dev/null || printf "unknown")"

  case "${arch}" in
    x86_64|amd64)
      ;;
    *)
      echo "错误: 当前架构 ${arch} 暂不支持自动下载 db-query 二进制（仅支持 amd64）。" >&2
      return 1
      ;;
  esac

  case "${os}" in
    Linux*)
      printf "db-query-linux-amd64\n"
      return 0
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT*)
      printf "db-query-windows-amd64.exe\n"
      return 0
      ;;
    Darwin*)
      echo "错误: 当前平台 Darwin 暂无预编译 db-query 二进制，请改为手动下载。" >&2
      return 1
      ;;
    *)
      case "${OSTYPE:-}" in
        msys*|cygwin*|win32*)
          printf "db-query-windows-amd64.exe\n"
          return 0
          ;;
      esac
      echo "错误: 无法识别平台 ${os}/${arch}，请改为手动下载 db-query 二进制。" >&2
      return 1
      ;;
  esac
}

fetch_latest_tag_from_github_repo() {
  local repo="$1"
  local json latest_tag

  if ! command -v curl >/dev/null 2>&1; then
    printf "latest\n"
    return 0
  fi

  json="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || true)"
  latest_tag="$(printf "%s\n" "${json}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [[ -n "${latest_tag}" ]]; then
    printf "%s\n" "${latest_tag}"
    return 0
  fi

  json="$(curl -fsSL "https://api.github.com/repos/${repo}/tags?per_page=1" 2>/dev/null || true)"
  latest_tag="$(printf "%s\n" "${json}" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [[ -n "${latest_tag}" ]]; then
    printf "%s\n" "${latest_tag}"
    return 0
  fi

  printf "latest\n"
}

prompt_db_query_remote_download_if_needed() {
  local has_db_query_selected="$1"
  local input=""
  local tty_opened="false"

  if [[ "${has_db_query_selected}" != "true" ]]; then
    return 0
  fi

  if [[ "${DB_QUERY_REMOTE_DOWNLOAD_EXPLICIT}" == "true" ]]; then
    case "${DB_QUERY_REMOTE_DOWNLOAD}" in
      yes|YES|Yes|y|Y|true|TRUE|1)
        DB_QUERY_REMOTE_DOWNLOAD="yes"
        return 0
        ;;
      no|NO|No|n|N|false|FALSE|0)
        DB_QUERY_REMOTE_DOWNLOAD="no"
        return 0
        ;;
      *)
        echo "错误: DB_QUERY_REMOTE_DOWNLOAD 仅支持 yes 或 no，当前值: ${DB_QUERY_REMOTE_DOWNLOAD}" >&2
        return 1
        ;;
    esac
  fi

  if [[ "${AUTO_YES}" == "true" ]]; then
    DB_QUERY_REMOTE_DOWNLOAD="yes"
    echo "已自动选择远程下载 db-query 二进制: yes"
    return 0
  fi

  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  if [[ "${tty_opened}" == "true" ]]; then
    printf "是否远程下载 db-query 二进制到 bin 目录? [Y/n]: " >&9
    IFS= read -r input <&9 || true
    exec 9<&-
  fi

  input="${input:-Y}"
  if [[ "${input}" =~ ^[Nn]$ ]]; then
    DB_QUERY_REMOTE_DOWNLOAD="no"
  else
    DB_QUERY_REMOTE_DOWNLOAD="yes"
  fi
  DB_QUERY_REMOTE_DOWNLOAD_EXPLICIT="true"
  echo "已选择远程下载 db-query 二进制: ${DB_QUERY_REMOTE_DOWNLOAD}"
}

prompt_db_query_release_tag_if_needed() {
  local has_db_query_selected="$1"
  local source_mode="$2"
  local github_repo="$3"
  local repo default_tag input
  local tty_opened="false"

  if [[ "${has_db_query_selected}" != "true" ]]; then
    return 0
  fi
  if [[ -n "${DB_QUERY_RELEASE_BASE_URL}" ]]; then
    return 0
  fi
  if [[ "${DB_QUERY_RELEASE_TAG_EXPLICIT}" == "true" && -n "${DB_QUERY_RELEASE_TAG}" ]]; then
    return 0
  fi

  repo="$(resolve_db_query_release_repo_for_skills_install "${source_mode}" "${github_repo}")"
  default_tag="$(fetch_latest_tag_from_github_repo "${repo}")"
  [[ -z "${default_tag}" ]] && default_tag="latest"

  if [[ "${AUTO_YES}" == "true" ]]; then
    DB_QUERY_RELEASE_TAG="${default_tag}"
    echo "已自动选择 db-query release tag: ${DB_QUERY_RELEASE_TAG}"
    return 0
  fi

  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  if [[ "${tty_opened}" == "true" ]]; then
    printf "请输入 db-query release tag（默认 %s，输入 latest 使用最新 release）: " "${default_tag}" >&9
    IFS= read -r input <&9 || true
    exec 9<&-
  else
    input=""
  fi

  input="${input:-${default_tag}}"
  DB_QUERY_RELEASE_TAG="${input}"
  DB_QUERY_RELEASE_TAG_EXPLICIT="true"
  echo "已选择 db-query release tag: ${DB_QUERY_RELEASE_TAG}"
}

print_db_query_manual_download_notice() {
  local dest="$1"
  local source_mode="$2"
  local github_repo="$3"
  local release_page platform_asset

  mkdir -p "${dest}/bin"
  release_page="$(resolve_db_query_release_page_url_for_skills_install "${source_mode}" "${github_repo}")"
  platform_asset="$(resolve_db_query_release_asset_for_current_platform 2>/dev/null || true)"

  echo "已选择不远程下载 db-query 二进制。"
  echo "请前往 release 页面手动下载并复制到以下目录："
  echo "  页面: ${release_page}"
  echo "  目标目录: ${dest}/bin"
  if [[ -n "${platform_asset}" ]]; then
    echo "  当前平台文件: ${platform_asset}"
  else
    echo "  文件1: db-query-linux-amd64"
    echo "  文件2: db-query-windows-amd64.exe"
  fi
}

resolve_db_query_release_base_url_for_skills_install_with_override() {
  local source_mode="$1"
  local github_repo="$2"
  if [[ -n "${DB_QUERY_RELEASE_BASE_URL}" ]]; then
    printf "%s\n" "${DB_QUERY_RELEASE_BASE_URL}"
    return
  fi
  resolve_db_query_release_base_url_for_skills_install "${source_mode}" "${github_repo}"
}

download_db_query_release_bins_for_skills_install() {
  local dest="$1"
  local source_mode="$2"
  local github_repo="$3"
  local base_url url tmp_file asset

  base_url="$(resolve_db_query_release_base_url_for_skills_install_with_override "${source_mode}" "${github_repo}")"
  asset="$(resolve_db_query_release_asset_for_current_platform)"

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 下载 db-query release 二进制需要 curl。" >&2
    return 1
  fi

  mkdir -p "${dest}/bin"
  url="${base_url}/${asset}"
  tmp_file="${dest}/bin/.tmp-${asset}"
  if ! curl -fsSL "${url}" -o "${tmp_file}" >/dev/null 2>&1; then
    rm -f "${tmp_file}"
    echo "错误: 下载 db-query release 文件失败: ${url}" >&2
    echo "可通过 DB_QUERY_RELEASE_BASE_URL 覆盖地址。" >&2
    return 1
  fi
  mv "${tmp_file}" "${dest}/bin/${asset}"

  if [[ "${asset}" == "db-query-linux-amd64" ]]; then
    chmod +x "${dest}/bin/db-query-linux-amd64" 2>/dev/null || true
  fi
  echo "已同步 db-query release 二进制: ${base_url} (${asset})"
  return 0
}

sync_db_query_release_bins_for_skills_install() {
  local dest="$1"
  local source_mode="$2"
  local github_repo="$3"
  local asset

  if download_db_query_release_bins_for_skills_install "${dest}" "${source_mode}" "${github_repo}"; then
    return 0
  fi

  asset="$(resolve_db_query_release_asset_for_current_platform 2>/dev/null || true)"
  if [[ -n "${asset}" && -s "${dest}/bin/${asset}" ]]; then
    echo "警告: release 下载失败，已保留本地现有 db-query 二进制 (${asset})。"
    return 0
  fi

  echo "错误: db-query 缺少可用平台二进制，请检查 release 地址或改为手动下载。" >&2
  return 1
}

copy_skill_payload_for_install() {
  local name="$1"
  local src="$2"
  local dest="$3"

  mkdir -p "${dest}"
  if [[ "${name}" == "db-query" ]]; then
    find "${src}" -mindepth 1 -maxdepth 1 ! -name 'scripts' -exec cp -R "{}" "${dest}/" \;
  else
    cp -R "${src}/." "${dest}/"
  fi
}

install_file_with_prompt() {
  local target_file="$1"
  local source_file="$2"
  local label="$3"

  mkdir -p "$(dirname "${target_file}")"

  if [[ -f "${target_file}" ]]; then
    echo "${label} 已存在: ${target_file}"
    if cmp -s "${target_file}" "${source_file}"; then
      echo "原文件与新文件无差异，已跳过替换 ${label}"
      return 0
    fi

    preview_file_head "${target_file}" 20 "旧文件内容预览"
    preview_file_head "${source_file}" 20 "新文件内容预览"

    if confirm "是否替换 ${label}?" "N"; then
      cp "${source_file}" "${target_file}"
      echo "已替换 ${label}: ${target_file}"
    else
      echo "已跳过替换 ${label}"
    fi
  else
    cp "${source_file}" "${target_file}"
    echo "已创建 ${label}: ${target_file}"
  fi
}

is_agents_v2_file() {
  local file_name="$1"
  [[ "${file_name}" == "AGENTS_v2.md" || "${file_name}" == "AGENTS_MEMORY_v2.md" ]]
}

prepare_agents_v2_template_payload() {
  local agent_file_name="$1"
  local source_mode="$2"
  local source_value="$3"
  local repo="$4"
  local ref="$5"
  local agents_path="$6"
  local local_root="$7"
  local output_file="$8"
  local template_path=""
  local template_url=""

  if ! is_agents_v2_file "${agent_file_name}"; then
    return 1
  fi

  case "${source_mode}" in
    source)
      if [[ "${source_value}" =~ ^https?:// ]]; then
        template_url="${source_value%/*}/construction_doc_template.md"
        copy_local_or_url_to_file "${template_url}" "${output_file}"
      else
        template_path="$(dirname "${source_value}")/construction_doc_template.md"
        [[ -f "${template_path}" ]] || return 1
        cp "${template_path}" "${output_file}"
      fi
      ;;
    github_file)
      template_path="$(dirname "${source_value}")/construction_doc_template.md"
      fetch_raw_from_github "${repo}" "${ref}" "${template_path}" "${output_file}"
      ;;
    catalog_remote)
      fetch_raw_from_github "${repo}" "${ref}" "${agents_path}/construction_doc_template.md" "${output_file}"
      ;;
    catalog_local)
      template_path="${local_root}/construction_doc_template.md"
      [[ -f "${template_path}" ]] || return 1
      cp "${template_path}" "${output_file}"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -s "${output_file}" ]]
}

install_agents_v2_template_for_project() {
  local agent_file_name="$1"
  local template_payload="$2"
  local project_template_file="$(pwd)/docs/construction_doc_template.md"

  if ! is_agents_v2_file "${agent_file_name}"; then
    return 0
  fi

  if [[ ! -s "${template_payload}" ]]; then
    echo "警告: 未找到 v2 agent 配套的 construction_doc_template.md，已跳过同步到当前项目 docs/。" >&2
    return 0
  fi

  install_file_with_prompt "${project_template_file}" "${template_payload}" "当前项目 docs/construction_doc_template.md"
}

is_agents_readme_entry() {
  local selected_path="$1"
  [[ "$(basename "${selected_path%%\?*}")" == "README.md" ]]
}

is_agents_global_install_entry() {
  local selected_path="$1"
  local base_name
  base_name="$(basename "${selected_path%%\?*}")"
  [[ "${base_name}" == "README.md" || "${base_name}" == *GLOBAL*.md ]]
}

find_local_global_agent_file() {
  local base_dir="$1"
  find "${base_dir}" -mindepth 1 -maxdepth 1 -type f -name '*GLOBAL*.md' | sort | head -n 1
}

resolve_github_global_agent_path() {
  local repo="$1"
  local ref="$2"
  local readme_path="$3"
  local base_dir api_url json global_path

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 解析 README 对应的 GLOBAL agent 需要 curl。" >&2
    return 1
  fi

  base_dir="$(dirname "${readme_path}")"
  api_url="https://api.github.com/repos/${repo}/contents/${base_dir}?ref=${ref}"
  json="$(curl -fsSL "${api_url}" 2>/dev/null || true)"
  global_path="$(
    printf "%s\n" "${json}" \
      | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*GLOBAL[^"]*\.md\)".*/\1/p' \
      | sort \
      | head -n 1
  )"

  if [[ -z "${global_path}" ]]; then
    echo "错误: 未在 ${repo}@${ref}:${base_dir} 下找到匹配 *GLOBAL*.md 的 agent 文件。" >&2
    return 1
  fi

  printf "%s\n" "${global_path}"
}

resolve_agents_install_target_path() {
  local selected_path="$1"
  local target_root="$2"
  local target_agent_file="$3"
  local project_target_file="$4"

  if is_agents_global_install_entry "${selected_path}"; then
    printf "%s\n" "${target_root}/${target_agent_file}"
  else
    printf "%s\n" "${project_target_file}"
  fi
}

resolve_agents_install_target_label() {
  local selected_path="$1"
  local target_agent_file="$2"

  if is_agents_global_install_entry "${selected_path}"; then
    printf "~/.codex/%s\n" "${target_agent_file}"
  else
    printf "当前项目 AGENTS.md\n"
  fi
}

parse_agent_catalog_entries() {
  local readme_file="$1"

  awk '
    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }

    function is_separator(s) {
      return s ~ /^:?-+:?$/
    }

    function clean_markdown_code(s) {
      gsub(/\r/, "", s)
      gsub(/`/, "", s)
      return trim(s)
    }

    BEGIN { in_catalog = 0 }

    /<!--[[:space:]]*AGENT_CATALOG_START[[:space:]]*-->/ { in_catalog = 1; next }
    /<!--[[:space:]]*AGENT_CATALOG_END[[:space:]]*-->/ { in_catalog = 0; next }

    {
      if (in_catalog == 0) {
        next
      }
      if ($0 ~ /^##[[:space:]]+/) {
        group = $0
        sub(/^##[[:space:]]+/, "", group)
        group = trim(group)
        next
      }
      if ($0 !~ /^\|/) {
        next
      }

      line = $0
      sub(/^\|/, "", line)
      sub(/\|[[:space:]]*$/, "", line)
      count = split(line, cols, "|")
      if (count < 2) {
        next
      }

      first = trim(cols[1])
      second = trim(cols[2])
      third = count >= 3 ? trim(cols[3]) : ""
      fourth = count >= 4 ? trim(cols[4]) : ""

      if (count == 2) {
        name = clean_markdown_code(first)
        path = clean_markdown_code(first)
        desc = second
        if (name ~ /\.md([?#].*)?$/) {
          sub(/\.md([?#].*)?$/, "", name)
        }
      } else if (count >= 4 && (tolower(second) == "name" || tolower(third) == "file" || third ~ /\.md([?#].*)?$/)) {
        name = second
        path = clean_markdown_code(third)
        desc = fourth
      } else {
        name = first
        path = clean_markdown_code(second)
        desc = third
      }

      lower_name = tolower(name)
      lower_path = tolower(path)

      if (lower_name == "name" || lower_path == "file" || lower_path == "文件名") {
        next
      }
      if (is_separator(name) || is_separator(path)) {
        next
      }

      gsub(/\r/, "", desc)
      print name "\t" path "\t" desc "\t" group
    }
  ' "${readme_file}"
}

read_frontmatter_field() {
  local file="$1"
  local field="$2"
  local value

  value="$(
    tr -d '\r' < "${file}" | sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' \
      | sed '1d;$d' \
      | grep -E "^[[:space:]]*${field}:[[:space:]]*" \
      | head -n 1 \
      | sed -E "s/^[[:space:]]*${field}:[[:space:]]*//"
  )"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf "%s\n" "${value}"
}

choose_target_interactive() {
  local input=""
  local tty_opened="false"

  CHOSEN_MODE=""

  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  while true; do
    echo
    echo "请选择要安装的内容："
    echo "  1) MCP Servers"
    echo "  2) Agents 文件"
    echo "  3) Skills"
    echo "  4) 全部安装（MCP + AGENTS + Skills）"
    echo "  q) 退出"

    if [[ "${tty_opened}" == "true" ]]; then
      printf "> " >&9
      IFS= read -r input <&9 || input="q"
    else
      read -r -p "> " input || input="q"
    fi

    case "${input}" in
      1)
        CHOSEN_MODE="mcp"
        break
        ;;
      2)
        CHOSEN_MODE="agents"
        break
        ;;
      3)
        CHOSEN_MODE="skills"
        break
        ;;
      4)
        CHOSEN_MODE="all"
        break
        ;;
      q|Q)
        CHOSEN_MODE="exit"
        break
        ;;
      *)
        echo "无效输入: ${input}"
        ;;
    esac
  done

  if [[ "${tty_opened}" == "true" ]]; then
    exec 9<&-
  fi
}

install_agents_main() {
  local source_mode=""
  local source_input=""
  local github_repo=""
  local github_ref="${DEFAULT_GITHUB_REF}"
  local github_file=""
  local github_agents_path="agents"
  local local_agents_root="${REPO_ROOT}/agents"
  local target_root="${HOME}/.codex"
  local target_agent_file="AGENTS.md"
  local project_target_file="$(pwd)/AGENTS.md"
  local tmp_template=""
  local agents_root=""
  local source_label=""
  local remote_repo=""
  local remote_path=""
  local tmp_catalog_file=""
  local tmp_source=""
  local file_name=""
  local src=""
  local dest=""
  local cmd=""
  local token=""
  local idx=0
  local tty_opened="false"
  local selected_count=0
  local name=""
  local desc=""
  local rel_path=""
  local group=""
  local current_group=""
  local global_source=""
  local target_label=""
  local -a agent_names=()
  local -a agent_descs=()
  local -a agent_paths=()
  local -a agent_groups=()
  local -a selected=()
  declare -A seen_paths=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        source_mode="source"
        source_input="${2:-}"
        shift 2
        ;;
      --github)
        source_mode="github"
        github_repo="${2:-}"
        shift 2
        ;;
      --ref)
        github_ref="${2:-}"
        shift 2
        ;;
      --file)
        source_mode="github"
        github_file="${2:-}"
        shift 2
        ;;
      --agents-path)
        source_mode="github"
        github_agents_path="${2:-}"
        shift 2
        ;;
      -h|--help)
        agents_usage
        return "${HELP_EXIT_CODE}"
        ;;
      *)
        echo "错误: agents 不支持参数: $1" >&2
        agents_usage
        return 1
        ;;
    esac
  done

  if [[ "${source_mode}" == "source" && -z "${source_input}" ]]; then
    echo "错误: --source 不能为空" >&2
    return 1
  fi

  if [[ "${source_mode}" == "github" && -z "${github_repo}" ]]; then
    github_repo="${DEFAULT_GITHUB_REPO}"
  fi

  if [[ "${source_mode}" == "source" ]]; then
    tmp_source="$(new_tmp_file)"
    if is_agents_readme_entry "${source_input}"; then
      if [[ "${source_input}" =~ ^https?:// ]]; then
        echo "错误: 通过 URL 选择 README 时，暂不支持自动定位同目录 *GLOBAL*.md，请改用本地 README 路径或直接指定 GLOBAL 文件。" >&2
        return 1
      fi
      global_source="$(find_local_global_agent_file "$(dirname "${source_input}")")"
      if [[ -z "${global_source}" ]]; then
        echo "错误: 未在 $(dirname "${source_input}") 下找到匹配 *GLOBAL*.md 的 agent 文件。" >&2
        return 1
      fi
      cp "${global_source}" "${tmp_source}"
    else
      copy_local_or_url_to_file "${source_input}" "${tmp_source}"
    fi
    if [[ ! -s "${tmp_source}" ]]; then
      echo "错误: 获取到的 agent 文件为空" >&2
      return 1
    fi

    file_name="$(basename "${source_input%%\?*}")"
    [[ -z "${file_name}" ]] && file_name="AGENTS.md"
    dest="$(resolve_agents_install_target_path "${source_input}" "${target_root}" "${target_agent_file}" "${project_target_file}")"
    target_label="$(resolve_agents_install_target_label "${source_input}" "${target_agent_file}")"
    echo "准备安装 ${file_name} -> ${target_label} ..."
    install_file_with_prompt "${dest}" "${tmp_source}" "${target_label}"
    tmp_template="$(new_tmp_file)"
    if prepare_agents_v2_template_payload "${file_name}" "source" "${source_input}" "" "" "" "" "${tmp_template}"; then
      install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
    fi
    echo "Agents 安装完成。"
    return 0
  fi

  if [[ "${source_mode}" == "github" && -n "${github_file}" ]]; then
    remote_repo="$(normalize_github_repo "${github_repo}")"
    tmp_source="$(new_tmp_file)"
    fetch_raw_from_github "${remote_repo}" "${github_ref}" "${github_file}" "${tmp_source}"
    if [[ ! -s "${tmp_source}" ]]; then
      echo "错误: 获取到的 agent 文件为空: ${github_file}" >&2
      return 1
    fi

    file_name="$(basename "${github_file}")"
    if is_agents_readme_entry "${github_file}"; then
      global_source="$(resolve_github_global_agent_path "${remote_repo}" "${github_ref}" "${github_file}")"
      fetch_raw_from_github "${remote_repo}" "${github_ref}" "${global_source}" "${tmp_source}"
      if [[ ! -s "${tmp_source}" ]]; then
        echo "错误: 获取 README 对应的 GLOBAL agent 文件失败: ${global_source}" >&2
        return 1
      fi
    fi
    dest="$(resolve_agents_install_target_path "${github_file}" "${target_root}" "${target_agent_file}" "${project_target_file}")"
    target_label="$(resolve_agents_install_target_label "${github_file}" "${target_agent_file}")"
    echo "准备安装 ${file_name} -> ${target_label} ..."
    install_file_with_prompt "${dest}" "${tmp_source}" "${target_label}"
    tmp_template="$(new_tmp_file)"
    if prepare_agents_v2_template_payload "${file_name}" "github_file" "${github_file}" "${remote_repo}" "${github_ref}" "" "" "${tmp_template}"; then
      install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
    fi
    echo "Agents 安装完成。"
    return 0
  fi

  if [[ "${source_mode}" != "github" && "${IS_NETWORK_REQUEST_EXECUTION}" != "true" && -d "${local_agents_root}" ]]; then
    agents_root="${local_agents_root}"
    source_label="本地目录 ${agents_root}"
  else
    remote_repo="$(normalize_github_repo "${github_repo:-${DEFAULT_GITHUB_REPO}}")"
    remote_path="${github_agents_path}"
    tmp_catalog_file="$(new_tmp_file)"
    if ! fetch_raw_from_github "${remote_repo}" "${github_ref}" "${remote_path}/README.md" "${tmp_catalog_file}"; then
      echo "错误: 无法读取远程 agents 目录清单 README.md" >&2
      echo "地址: https://raw.githubusercontent.com/${remote_repo}/${github_ref}/${remote_path}/README.md" >&2
      return 1
    fi

    while IFS=$'\t' read -r name rel_path desc group; do
      [[ -z "${name}" || -z "${rel_path}" ]] && continue
      [[ -z "${desc}" ]] && desc="(无 description)"
      if [[ -n "${seen_paths[${rel_path}]+x}" ]]; then
        echo "警告: 发现重复 agent 文件路径 '${rel_path}'，已忽略重复项。" >&2
        continue
      fi
      seen_paths["${rel_path}"]=1
      agent_names+=("${name}")
      agent_descs+=("${desc}")
      agent_paths+=("${rel_path}")
      agent_groups+=("${group}")
      selected+=(0)
    done < <(parse_agent_catalog_entries "${tmp_catalog_file}")

    if [[ ${#agent_names[@]} -eq 0 ]]; then
      echo "错误: 远程 agents README.md 未包含可解析目录（缺少 AGENT_CATALOG 标记或内容为空）" >&2
      return 1
    fi
    source_label="远程目录 ${remote_repo}@${github_ref}:${remote_path}（先读取 README 列表）"
  fi

  if [[ -n "${agents_root}" ]]; then
    tmp_catalog_file="${agents_root}/README.md"
    if [[ -f "${tmp_catalog_file}" ]]; then
      while IFS=$'\t' read -r name rel_path desc group; do
        [[ -z "${name}" || -z "${rel_path}" ]] && continue
        [[ -z "${desc}" ]] && desc="(无 description)"
        if [[ ! -f "${agents_root}/${rel_path}" ]]; then
          echo "警告: README 中声明的 agent 文件不存在，已忽略: ${rel_path}" >&2
          continue
        fi
        if [[ -n "${seen_paths[${rel_path}]+x}" ]]; then
          echo "警告: 发现重复 agent 文件路径 '${rel_path}'，已忽略重复项。" >&2
          continue
        fi
        seen_paths["${rel_path}"]=1
        agent_names+=("${name}")
        agent_descs+=("${desc}")
        agent_paths+=("${rel_path}")
        agent_groups+=("${group}")
        selected+=(0)
      done < <(parse_agent_catalog_entries "${tmp_catalog_file}")
    fi

    if [[ ${#agent_names[@]} -eq 0 ]]; then
      while IFS= read -r src; do
        rel_path="$(basename "${src}")"
        name="${rel_path%.md}"
        desc="(无 description)"
        if [[ -n "${seen_paths[${rel_path}]+x}" ]]; then
          continue
        fi
        seen_paths["${rel_path}"]=1
        agent_names+=("${name}")
        agent_descs+=("${desc}")
        agent_paths+=("${rel_path}")
        agent_groups+=("")
        selected+=(0)
      done < <(find "${agents_root}" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort)
    fi

    if [[ ${#agent_names[@]} -eq 0 ]]; then
      echo "错误: 未在 ${agents_root} 下找到可安装的 agent 文件" >&2
      return 1
    fi
  fi

  if [[ "${AUTO_YES}" == "true" ]]; then
    echo "错误: agents 安装不支持 --yes 模式，必须手动选择要安装的 agent 文件。" >&2
    return 1
  else
    tty_opened="false"
    if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
      tty_opened="true"
    fi

    while true; do
      echo
      echo "可安装的 agent 文件（来源: ${source_label}）"
      current_group=""
      for idx in "${!agent_names[@]}"; do
        group="${agent_groups[idx]:-}"
        if [[ -n "${group}" && "${group}" != "${current_group}" ]]; then
          echo
          printf "【%s】\n" "${group}"
          current_group="${group}"
        fi
        if [[ "${selected[idx]}" -eq 1 ]]; then
          printf "%2d. [x] %s (%s)\n" "$((idx + 1))" "${agent_names[idx]}" "${agent_paths[idx]}"
        else
          printf "%2d. [ ] %s (%s)\n" "$((idx + 1))" "${agent_names[idx]}" "${agent_paths[idx]}"
        fi
        printf "    %s\n" "${agent_descs[idx]}"
      done
      echo
      echo "操作: 输入单个编号进行选择，d=开始安装，q=退出"

      if [[ "${tty_opened}" == "true" ]]; then
        printf "> " >&9
        IFS= read -r cmd <&9 || cmd="q"
      else
        read -r -p "> " cmd || cmd="q"
      fi

      case "${cmd}" in
        d|D)
          selected_count=0
          for idx in "${!selected[@]}"; do
            if [[ "${selected[idx]}" -eq 1 ]]; then
              ((selected_count += 1))
            fi
          done
          if (( selected_count != 1 )); then
            echo "请先且仅选择一个 agent 文件。"
          else
            break
          fi
          ;;
        q|Q)
          echo "已取消安装。"
          return 0
          ;;
        "")
          ;;
        *)
          if [[ "${cmd}" =~ ^[0-9]+$ ]]; then
            if (( cmd >= 1 && cmd <= ${#agent_names[@]} )); then
              for idx in "${!selected[@]}"; do
                selected[idx]=0
              done
              idx=$((cmd - 1))
              selected[idx]=1
            else
              echo "无效编号: ${cmd}"
            fi
          else
            echo "无效输入: ${cmd}"
          fi
          ;;
      esac
    done

    if [[ "${tty_opened}" == "true" ]]; then
      exec 9<&-
    fi
  fi

  echo
  if (( selected_count != 1 )); then
    echo "请选择且仅选择一个 agent 文件，已取消安装。"
    return 0
  fi
  echo "开始安装 agents 文件..."
  for idx in "${!agent_names[@]}"; do
    [[ "${selected[idx]}" -ne 1 ]] && continue
    rel_path="${agent_paths[idx]}"
    file_name="$(basename "${rel_path}")"
    dest="$(resolve_agents_install_target_path "${rel_path}" "${target_root}" "${target_agent_file}" "${project_target_file}")"
    target_label="$(resolve_agents_install_target_label "${rel_path}" "${target_agent_file}")"

    if [[ -n "${remote_repo}" ]]; then
      tmp_source="$(new_tmp_file)"
      if is_agents_readme_entry "${rel_path}"; then
        global_source="$(resolve_github_global_agent_path "${remote_repo}" "${github_ref}" "${remote_path}/${rel_path}")"
        if ! fetch_raw_from_github "${remote_repo}" "${github_ref}" "${global_source}" "${tmp_source}" >/dev/null 2>&1; then
          echo "错误: 无法获取 README 对应的远程 GLOBAL agent 文件: ${global_source}" >&2
          return 1
        fi
      else
        if ! fetch_raw_from_github "${remote_repo}" "${github_ref}" "${remote_path}/${rel_path}" "${tmp_source}" >/dev/null 2>&1; then
          echo "错误: 无法获取远程 agent 文件: ${remote_path}/${rel_path}" >&2
          return 1
        fi
      fi
      src="${tmp_source}"
    else
      src="${agents_root}/${rel_path}"
      if is_agents_readme_entry "${rel_path}"; then
        global_source="$(find_local_global_agent_file "${agents_root}")"
        if [[ -z "${global_source}" ]]; then
          echo "错误: 未在 ${agents_root} 下找到匹配 *GLOBAL*.md 的 agent 文件。" >&2
          return 1
        fi
        src="${global_source}"
      elif [[ ! -f "${src}" ]]; then
        echo "错误: 本地 agent 文件不存在: ${src}" >&2
        return 1
      fi
    fi

    install_file_with_prompt "${dest}" "${src}" "${target_label}"
    tmp_template="$(new_tmp_file)"
    if [[ -n "${remote_repo}" ]]; then
      if prepare_agents_v2_template_payload "${file_name}" "catalog_remote" "" "${remote_repo}" "${github_ref}" "${remote_path}" "" "${tmp_template}"; then
        install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
      fi
    else
      if prepare_agents_v2_template_payload "${file_name}" "catalog_local" "" "" "" "" "${agents_root}" "${tmp_template}"; then
        install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
      fi
    fi
  done

  echo
  echo "Agents 安装完成。"
}

install_skills_main() {
  local source_mode=""
  local github_repo=""
  local github_ref="${DEFAULT_GITHUB_REF}"
  local github_skills_path="skills"
  local local_skills_root="${REPO_ROOT}/skills"
  local target_root="${HOME}/.codex/skills"
  local skills_root=""
  local source_label=""
  local remote_repo=""
  local remote_path=""
  local remote_skills_root=""
  local tmp_fetch_dir=""
  local tmp_catalog_file=""
  local archive_url archive_file extract_root candidate archive_extract_dir sparse_clone_dir
  local dir skill_file name desc rel_path
  local cmd token idx tty_opened
  local installed overwritten skipped selected_count
  local src dest preserve_dir cfg rel
  local release_source_mode=""
  local skills_menu_filter=""
  local skills_menu_selected_only="false"
  local skills_menu_page=0
  local skills_menu_page_size=12
  local -a skill_names=()
  local -a skill_descs=()
  local -a skill_paths=()
  local -a selected=()
  local -a selected_sparse_paths=()
  local -a visible_skill_indices=()
  declare -A seen_names=()
  declare -A seen_dirs=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --github)
        source_mode="github"
        github_repo="${2:-}"
        shift 2
        ;;
      --ref)
        source_mode="github"
        github_ref="${2:-}"
        shift 2
        ;;
      --skills-path)
        source_mode="github"
        github_skills_path="${2:-}"
        shift 2
        ;;
      --db-query-tag)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --db-query-tag 需要参数" >&2
          return 1
        fi
        DB_QUERY_RELEASE_TAG="${2:-}"
        DB_QUERY_RELEASE_TAG_EXPLICIT="true"
        shift 2
        ;;
      --db-query-download)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --db-query-download 需要参数 yes|no" >&2
          return 1
        fi
        DB_QUERY_REMOTE_DOWNLOAD="${2:-}"
        DB_QUERY_REMOTE_DOWNLOAD_EXPLICIT="true"
        shift 2
        ;;
      -h|--help)
        skills_usage
        return "${HELP_EXIT_CODE}"
        ;;
      *)
        echo "错误: skills 不支持参数: $1" >&2
        skills_usage
        return 1
        ;;
    esac
  done

  if [[ "${source_mode}" == "github" && -z "${github_repo}" ]]; then
    github_repo="${DEFAULT_GITHUB_REPO}"
  fi

  if [[ "${source_mode}" != "github" && "${IS_NETWORK_REQUEST_EXECUTION}" != "true" && -d "${local_skills_root}" ]]; then
    skills_root="${local_skills_root}"
    source_label="本地目录 ${skills_root}"
  fi

  if [[ -n "${skills_root}" ]]; then
    while IFS= read -r skill_file; do
      dir="$(dirname "${skill_file}")"
      if [[ -n "${seen_dirs[${dir}]+x}" ]]; then
        continue
      fi
      seen_dirs["${dir}"]=1

      name="$(read_frontmatter_field "${skill_file}" "name")"
      desc="$(read_frontmatter_field "${skill_file}" "description")"
      rel_path="${dir#${skills_root}/}"
      if [[ "${rel_path}" == "${dir}" ]]; then
        rel_path="$(basename "${dir}")"
      fi

      [[ -z "${name}" ]] && name="${rel_path}"
      [[ -z "${desc}" ]] && desc="(无 description)"

      if [[ -n "${seen_names[${name}]+x}" ]]; then
        echo "警告: 发现重复 skill 名称 '${name}'，已忽略目录: ${dir}" >&2
        continue
      fi
      seen_names["${name}"]=1

      skill_names+=("${name}")
      skill_descs+=("${desc}")
      skill_paths+=("${rel_path}")
      selected+=(0)
    done < <(find "${skills_root}" -type f \( -name 'SKILL.md' -o -name 'skill.md' \) | sort)

    if [[ ${#skill_names[@]} -eq 0 ]]; then
      echo "错误: 未在 ${skills_root} 下找到可安装的 skill" >&2
      return 1
    fi
  else
    remote_repo="$(normalize_github_repo "${github_repo:-${DEFAULT_GITHUB_REPO}}")"
    remote_path="${github_skills_path}"
    tmp_catalog_file="$(new_tmp_file)"
    if ! fetch_raw_from_github "${remote_repo}" "${github_ref}" "${remote_path}/README.md" "${tmp_catalog_file}" >/dev/null 2>&1; then
      echo "错误: 无法读取远程 skills 目录清单 README.md" >&2
      echo "地址: https://raw.githubusercontent.com/${remote_repo}/${github_ref}/${remote_path}/README.md" >&2
      return 1
    fi

    while IFS=$'\t' read -r name rel_path desc; do
      [[ -z "${name}" || -z "${rel_path}" ]] && continue
      [[ -z "${desc}" ]] && desc="(无 description)"

      if [[ -n "${seen_names[${name}]+x}" ]]; then
        echo "警告: 发现重复 skill 名称 '${name}'，已忽略目录: ${rel_path}" >&2
        continue
      fi
      seen_names["${name}"]=1

      skill_names+=("${name}")
      skill_descs+=("${desc}")
      skill_paths+=("${rel_path}")
      selected+=(0)
    done < <(
      awk '
        function trim(s) {
          gsub(/^[[:space:]]+/, "", s)
          gsub(/[[:space:]]+$/, "", s)
          return s
        }

        BEGIN { in_catalog = 0 }

        /<!--[[:space:]]*SKILL_CATALOG_START[[:space:]]*-->/ { in_catalog = 1; next }
        /<!--[[:space:]]*SKILL_CATALOG_END[[:space:]]*-->/ { in_catalog = 0; next }

        {
          if (in_catalog == 0) {
            next
          }
          if ($0 !~ /^\|/) {
            next
          }

          line = $0
          sub(/^\|/, "", line)
          sub(/\|[[:space:]]*$/, "", line)
          count = split(line, cols, "|")
          if (count < 3) {
            next
          }

          name = trim(cols[1])
          path = trim(cols[2])
          desc = trim(cols[3])

          lower_name = tolower(name)
          lower_path = tolower(path)
          if (lower_name == "name" || lower_path == "directory") {
            next
          }
          if (name ~ /^-+$/ || path ~ /^-+$/) {
            next
          }

          gsub(/\r/, "", desc)
          print name "\t" path "\t" desc
        }
      ' "${tmp_catalog_file}"
    )

    if [[ ${#skill_names[@]} -eq 0 ]]; then
      echo "错误: 远程 skills README.md 未包含可解析目录（缺少 SKILL_CATALOG 标记或内容为空）" >&2
      return 1
    fi
    source_label="远程目录 ${remote_repo}@${github_ref}:${remote_path}（先读取 README 列表）"
  fi

  skills_string_contains_ci() {
    local haystack="$1"
    local needle="$2"
    haystack="$(printf "%s" "${haystack}" | tr '[:upper:]' '[:lower:]')"
    needle="$(printf "%s" "${needle}" | tr '[:upper:]' '[:lower:]')"
    [[ "${haystack}" == *"${needle}"* ]]
  }

  skills_menu_is_visible() {
    local i="$1"
    local haystack

    if [[ "${skills_menu_selected_only}" == "true" && "${selected[i]}" -ne 1 ]]; then
      return 1
    fi

    if [[ -n "${skills_menu_filter}" ]]; then
      haystack="${skill_names[i]} ${skill_paths[i]} ${skill_descs[i]}"
      skills_string_contains_ci "${haystack}" "${skills_menu_filter}" || return 1
    fi

    return 0
  }

  skills_collect_visible_indices() {
    local i
    visible_skill_indices=()
    for i in "${!skill_names[@]}"; do
      if skills_menu_is_visible "${i}"; then
        visible_skill_indices+=("${i}")
      fi
    done
  }

  skills_apply_to_visible() {
    local action="$1"
    local i

    skills_collect_visible_indices
    for i in "${visible_skill_indices[@]}"; do
      case "${action}" in
        select)
          selected[i]=1
          ;;
        clear)
          selected[i]=0
          ;;
        invert)
          if [[ "${selected[i]}" -eq 1 ]]; then
            selected[i]=0
          else
            selected[i]=1
          fi
          ;;
      esac
    done
  }

  skills_render_menu() {
    local i mark total_visible selected_total total_pages start end pos

    skills_collect_visible_indices
    total_visible="${#visible_skill_indices[@]}"
    selected_total=0
    for i in "${!selected[@]}"; do
      [[ "${selected[i]}" -eq 1 ]] && ((selected_total += 1))
    done

    total_pages=$(( (total_visible + skills_menu_page_size - 1) / skills_menu_page_size ))
    (( total_pages < 1 )) && total_pages=1
    (( skills_menu_page >= total_pages )) && skills_menu_page=$((total_pages - 1))
    (( skills_menu_page < 0 )) && skills_menu_page=0
    start=$((skills_menu_page * skills_menu_page_size))
    end=$((start + skills_menu_page_size))
    (( end > total_visible )) && end="${total_visible}"

    echo
    echo "可安装的 skills（来源: ${source_label}）"
    printf "已选 %d/%d，当前显示 %d 项，页 %d/%d" "${selected_total}" "${#skill_names[@]}" "${total_visible}" "$((skills_menu_page + 1))" "${total_pages}"
    [[ -n "${skills_menu_filter}" ]] && printf "，搜索: %s" "${skills_menu_filter}"
    [[ "${skills_menu_selected_only}" == "true" ]] && printf "，仅看已选"
    printf "\n"

    if (( total_visible == 0 )); then
      echo "  当前筛选无匹配项。"
    else
      for ((pos = start; pos < end; pos++)); do
        i="${visible_skill_indices[pos]}"
        mark="[ ]"
        if [[ "${selected[i]}" -eq 1 ]]; then
          mark="[x]"
        fi
        printf "%2d. %s %s (%s)\n" "$((i + 1))" "${mark}" "${skill_names[i]}" "${skill_paths[i]}"
        printf "    %s\n" "${skill_descs[i]}"
      done
    fi

    echo
    echo "操作: 编号/范围(1-3)/名称切换，s 关键词=搜索，c=清搜索，l=仅看已选，</>=翻页，a/n/i=对当前筛选全选/全不选/反选，d=安装，q=退出"
  }

  skills_toggle_single_token() {
    local token="$1"
    local i matched_idx match_count haystack

    if [[ "${token}" =~ ^[0-9]+$ ]]; then
      if (( token >= 1 && token <= ${#skill_names[@]} )); then
        i=$((token - 1))
        if [[ "${selected[i]}" -eq 1 ]]; then
          selected[i]=0
        else
          selected[i]=1
        fi
      else
        echo "无效编号: ${token}"
      fi
      return
    fi

    matched_idx=-1
    match_count=0
    for i in "${!skill_names[@]}"; do
      haystack="${skill_names[i]} ${skill_paths[i]}"
      if skills_string_contains_ci "${haystack}" "${token}"; then
        matched_idx="${i}"
        ((match_count += 1))
      fi
    done

    if (( match_count == 1 )); then
      if [[ "${selected[matched_idx]}" -eq 1 ]]; then
        selected[matched_idx]=0
      else
        selected[matched_idx]=1
      fi
    elif (( match_count > 1 )); then
      echo "名称匹配不唯一: ${token}，请先用 s ${token} 搜索后再按编号选择。"
    else
      echo "无效输入: ${token}"
    fi
  }

  skills_toggle_input() {
    local input="$1"
    local token start end n

    input="${input//,/ }"
    for token in ${input}; do
      if [[ "${token}" =~ ^[0-9]+-[0-9]+$ ]]; then
        start="${token%-*}"
        end="${token#*-}"
        if (( start > end )); then
          n="${start}"
          start="${end}"
          end="${n}"
        fi
        for ((n = start; n <= end; n++)); do
          skills_toggle_single_token "${n}"
        done
      else
        skills_toggle_single_token "${token}"
      fi
    done
  }

  tty_opened="false"
  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  while true; do
    skills_render_menu

    if [[ "${tty_opened}" == "true" ]]; then
      printf "> " >&9
      IFS= read -r cmd <&9 || cmd="q"
    else
      read -r -p "> " cmd || cmd="q"
    fi
    case "${cmd}" in
      a|A)
        skills_apply_to_visible select
        ;;
      n|N)
        skills_apply_to_visible clear
        ;;
      i|I)
        skills_apply_to_visible invert
        ;;
      s\ *|S\ *)
        skills_menu_filter="${cmd#* }"
        skills_menu_page=0
        ;;
      /*)
        skills_menu_filter="${cmd#/}"
        skills_menu_page=0
        ;;
      c|C)
        skills_menu_filter=""
        skills_menu_selected_only="false"
        skills_menu_page=0
        ;;
      l|L)
        if [[ "${skills_menu_selected_only}" == "true" ]]; then
          skills_menu_selected_only="false"
        else
          skills_menu_selected_only="true"
        fi
        skills_menu_page=0
        ;;
      ">"|f|F)
        skills_menu_page=$((skills_menu_page + 1))
        ;;
      "<"|b|B)
        skills_menu_page=$((skills_menu_page - 1))
        ;;
      d|D)
        selected_count=0
        for idx in "${!selected[@]}"; do
          [[ "${selected[idx]}" -eq 1 ]] && ((selected_count += 1))
        done
        if (( selected_count == 0 )); then
          echo "未勾选任何 skill，请先勾选。"
        else
          break
        fi
        ;;
      q|Q)
        echo "已取消安装。"
        return 0
        ;;
      "")
        ;;
      *)
        skills_toggle_input "${cmd}"
        ;;
    esac
  done

  if [[ "${tty_opened}" == "true" ]]; then
    exec 9<&-
  fi

  local has_db_query_selected="false"
  for idx in "${!skill_names[@]}"; do
    if [[ "${selected[idx]}" -eq 1 && "${skill_names[idx]}" == "db-query" ]]; then
      has_db_query_selected="true"
      break
    fi
  done

  if ! prompt_db_query_remote_download_if_needed "${has_db_query_selected}"; then
    return 1
  fi

  if [[ "${has_db_query_selected}" == "true" && "${DB_QUERY_REMOTE_DOWNLOAD}" != "no" ]]; then
    if ! prompt_db_query_release_tag_if_needed "${has_db_query_selected}" "${source_mode}" "${remote_repo:-${github_repo}}"; then
      return 1
    fi
  fi

  if [[ "${has_db_query_selected}" == "true" && "${DB_QUERY_REMOTE_DOWNLOAD}" == "no" ]]; then
    echo "db-query 将跳过远程下载二进制，安装后会提示手动下载路径。"
  fi

  if [[ "${has_db_query_selected}" == "true" && "${DB_QUERY_REMOTE_DOWNLOAD}" != "yes" && "${DB_QUERY_REMOTE_DOWNLOAD}" != "no" ]]; then
    echo "错误: db-query 下载选项无效: ${DB_QUERY_REMOTE_DOWNLOAD}（仅支持 yes|no）" >&2
    return 1
  fi

  mkdir -p "${target_root}"
  installed=0
  overwritten=0
  skipped=0

  if [[ -n "${remote_repo}" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "错误: 需要 curl 来拉取远程仓库压缩包。" >&2
      return 1
    fi
    if ! command -v tar >/dev/null 2>&1; then
      echo "错误: 需要 tar 来解压远程仓库压缩包。" >&2
      return 1
    fi

    tmp_fetch_dir="$(new_tmp_dir)"
    archive_extract_dir="${tmp_fetch_dir}/archive"
    sparse_clone_dir="${tmp_fetch_dir}/sparse-repo"
    mkdir -p "${archive_extract_dir}"
    archive_url="https://codeload.github.com/${remote_repo}/tar.gz/${github_ref}"
    archive_file="${tmp_fetch_dir}/repo.tar.gz"
    echo "已选择 ${selected_count} 个 skill，开始拉取远程仓库: ${remote_repo}@${github_ref}"
    echo "提示: 若压缩包下载超过约 10 秒，将自动切换为按所选 skill 稀疏拉取。"

    candidate=""
    if curl_download_with_retry "${archive_url}" "${archive_file}" 1 5 10; then
      if run_with_timeout_if_available 20 tar -xzf "${archive_file}" -C "${archive_extract_dir}"; then
        extract_root="$(find "${archive_extract_dir}" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
        if [[ -n "${extract_root}" ]]; then
          candidate="${extract_root}/${remote_path}"
        fi
      fi
    fi

    if [[ -z "${candidate}" || ! -d "${candidate}" ]]; then
      selected_sparse_paths=()
      for idx in "${!skill_names[@]}"; do
        [[ "${selected[idx]}" -ne 1 ]] && continue
        selected_sparse_paths+=("${remote_path}/${skill_paths[idx]}")
      done
      echo "警告: 远程仓库压缩包下载较慢或失败，尝试按目录稀疏拉取: ${remote_repo}@${github_ref}:${remote_path}" >&2
      candidate="$(git_sparse_checkout_repo_path "${remote_repo}" "${github_ref}" "${remote_path}" "${sparse_clone_dir}" "${selected_sparse_paths[@]}" || true)"
    fi

    if [[ -z "${candidate}" || ! -d "${candidate}" ]]; then
      echo "错误: 无法获取远程 skills 目录 ${remote_repo}@${github_ref}:${remote_path}" >&2
      echo "已尝试: codeload 压缩包、git sparse-checkout" >&2
      return 1
    fi
    remote_skills_root="${candidate}"
  fi
  if [[ -n "${remote_repo}" ]]; then
    release_source_mode="github"
  else
    release_source_mode="${source_mode}"
  fi

  echo
  echo "开始安装到: ${target_root}"
  for idx in "${!skill_names[@]}"; do
    [[ "${selected[idx]}" -ne 1 ]] && continue

    name="${skill_names[idx]}"
    rel_path="${skill_paths[idx]}"
    if [[ -n "${remote_skills_root}" ]]; then
      src="${remote_skills_root}/${rel_path}"
    else
      src="${skills_root}/${rel_path}"
    fi
    if [[ ! -d "${src}" ]]; then
      echo "错误: skill 源目录不存在: ${src}" >&2
      return 1
    fi
    dest="${target_root}/${name}"

    if [[ -e "${dest}" ]]; then
      if confirm "技能 ${name} 已存在，是否覆盖?" "N"; then
        preserve_dir="$(new_tmp_dir)"
        while IFS= read -r cfg; do
          rel="${cfg#${dest}/}"
          mkdir -p "${preserve_dir}/$(dirname "${rel}")"
          cp "${cfg}" "${preserve_dir}/${rel}"
        done < <(find "${dest}" -type f -name 'config.env')

        mkdir -p "${dest}"
        copy_skill_payload_for_install "${name}" "${src}" "${dest}"

        while IFS= read -r cfg; do
          rel="${cfg#${preserve_dir}/}"
          mkdir -p "${dest}/$(dirname "${rel}")"
          cp "${cfg}" "${dest}/${rel}"
        done < <(find "${preserve_dir}" -type f -name 'config.env')

        if [[ "${name}" == "db-query" ]]; then
          if [[ "${DB_QUERY_REMOTE_DOWNLOAD}" == "no" ]]; then
            print_db_query_manual_download_notice "${dest}" "${release_source_mode}" "${remote_repo:-${github_repo}}"
          else
            if ! sync_db_query_release_bins_for_skills_install "${dest}" "${release_source_mode}" "${remote_repo:-${github_repo}}"; then
              return 1
            fi
          fi
        fi

        echo "已覆盖同名 skill: ${name} -> ${dest}（保留本地 config.env）"
        ((overwritten += 1))
      else
        echo "跳过: ${name}（本地已存在: ${dest}）"
        if [[ "${name}" == "db-query" ]]; then
          if [[ "${DB_QUERY_REMOTE_DOWNLOAD}" == "no" ]]; then
            print_db_query_manual_download_notice "${dest}" "${release_source_mode}" "${remote_repo:-${github_repo}}"
          else
            if ! sync_db_query_release_bins_for_skills_install "${dest}" "${release_source_mode}" "${remote_repo:-${github_repo}}"; then
              return 1
            fi
            echo "已同步 db-query release 二进制（未覆盖其他文件）: ${dest}/bin"
          fi
        fi
        ((skipped += 1))
      fi
      continue
    fi

    copy_skill_payload_for_install "${name}" "${src}" "${dest}"
    if [[ "${name}" == "db-query" ]]; then
      if [[ "${DB_QUERY_REMOTE_DOWNLOAD}" == "no" ]]; then
        print_db_query_manual_download_notice "${dest}" "${release_source_mode}" "${remote_repo:-${github_repo}}"
      else
        if ! sync_db_query_release_bins_for_skills_install "${dest}" "${release_source_mode}" "${remote_repo:-${github_repo}}"; then
          return 1
        fi
      fi
    fi
    echo "已安装: ${name} -> ${dest}"
    ((installed += 1))
  done

  echo
  echo "Skills 安装完成: 新增 ${installed} 个，覆盖 ${overwritten} 个，跳过 ${skipped} 个。"
}

install_mcp_main() {
  local source_mode=""
  local source_input=""
  local github_repo="${DEFAULT_GITHUB_REPO}"
  local github_ref="${DEFAULT_GITHUB_REF}"
  local github_mcp_path="mcp"
  local target_config="${HOME}/.codex/config.toml"
  local source_label=""
  local local_fallback_source="${REPO_ROOT}/mcp"
  local cwd_fallback_source_1="$(pwd)/mcp"
  local cwd_fallback_source_2="$(pwd)/mcp.md"
  local tmp_source_file=""
  local tmp_status_dir=""
  local tmp_parse_dir=""
  local row name title desc_encoded desc block
  local cmd i selected_count tty_opened done_select first_line rest_lines line src_block
  local -a server_names=()
  local -a server_titles=()
  local -a server_descs=()
  local -a selected=()
  local -a upsert=()
  local -a selected_names=()
  declare -A source_block_by_name=()

  mcp_append_source_file_to_bundle() {
    local file="$1"
    if [[ -s "${tmp_source_file}" ]]; then
      printf "\n\n" >> "${tmp_source_file}"
    fi
    cat "${file}" >> "${tmp_source_file}"
    printf "\n" >> "${tmp_source_file}"
  }

  mcp_bundle_local_directory() {
    local source_dir="$1"
    local file count=0

    : > "${tmp_source_file}"
    while IFS= read -r file; do
      mcp_append_source_file_to_bundle "${file}"
      count=$((count + 1))
    done < <(find "${source_dir}" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'mcp.md' | sort)

    if (( count == 0 )); then
      echo "错误: MCP 目录未包含可解析的单服务 Markdown 文件: ${source_dir}" >&2
      exit 1
    fi
  }

  mcp_use_local_fallback() {
    local candidate=""
    for candidate in "${local_fallback_source}" "${cwd_fallback_source_1}" "${cwd_fallback_source_2}"; do
      if [[ -n "${candidate}" && -d "${candidate}" ]]; then
        mcp_bundle_local_directory "${candidate}"
        source_label="本地回退目录 ${candidate}"
        return 0
      fi
      if [[ -n "${candidate}" && -f "${candidate}" ]]; then
        cp "${candidate}" "${tmp_source_file}"
        source_label="本地回退 ${candidate}"
        return 0
      fi
    done
    return 1
  }

  mcp_fetch_github_directory() {
    local repo="$1"
    local path="$2"
    local manifest_file download_url file tmp_file count=0

    manifest_file="$(new_tmp_file)"
    if ! curl_download_with_retry "https://api.github.com/repos/${repo}/contents/${path}?ref=${github_ref}" "${manifest_file}" 2 5 15; then
      return 1
    fi
    : > "${tmp_source_file}"

    while IFS= read -r download_url; do
      [[ -z "${download_url}" ]] && continue
      file="${download_url%%\?*}"
      file="$(basename "${file}")"
      [[ "${file}" == "README.md" || "${file}" == "mcp.md" ]] && continue

      tmp_file="$(new_tmp_file)"
      if ! curl_download_with_retry "${download_url}" "${tmp_file}" 2 5 15; then
        return 1
      fi
      mcp_append_source_file_to_bundle "${tmp_file}"
      count=$((count + 1))
    done < <(
      sed -n 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.md\)".*/\1/p' "${manifest_file}" | sort
    )

    if (( count == 0 )); then
      echo "错误: 远程 MCP 目录未包含可解析的单服务 Markdown 文件: ${repo}@${github_ref}:${path}" >&2
      return 1
    fi
  }

  mcp_fetch_source_file() {
    local repo raw_url bundle_path
    tmp_source_file="$(new_tmp_file)"

    if [[ "${source_mode}" == "source" ]]; then
      if [[ -d "${source_input}" ]]; then
        mcp_bundle_local_directory "${source_input}"
        source_label="本地目录 ${source_input}"
        return
      fi

      copy_local_or_url_to_file "${source_input}" "${tmp_source_file}"
      if [[ "${source_input}" =~ ^https?:// ]]; then
        source_label="URL ${source_input}"
      else
        source_label="本地文件 ${source_input}"
      fi
      return
    fi

    if [[ "${source_mode}" != "github" && "${IS_NETWORK_REQUEST_EXECUTION}" != "true" ]]; then
      if mcp_use_local_fallback; then
        return
      fi
    fi

    repo="$(normalize_github_repo "${github_repo}")"
    echo "正在拉取远程 MCP 清单: ${repo}@${github_ref}:${github_mcp_path}"

    if ! command -v curl >/dev/null 2>&1; then
      if mcp_use_local_fallback; then
        echo "警告: 未安装 curl，已回退到本地文件: ${source_label#本地回退 }" >&2
        return
      fi
      echo "错误: 未安装 curl，且未找到可用本地 MCP 目录或 Markdown 回退文件。" >&2
      echo "提示: 可使用 --source 指定本地目录或文件，例如: --source mcp" >&2
      exit 1
    fi

    if [[ "${github_mcp_path}" != *.md ]]; then
      bundle_path="${github_mcp_path%/}/mcp.md"
      raw_url="https://raw.githubusercontent.com/${repo}/${github_ref}/${bundle_path}"
      if curl_download_with_retry "${raw_url}" "${tmp_source_file}" 2 5 20; then
        source_label="远程聚合文件 ${raw_url}"
        return
      fi

      if mcp_fetch_github_directory "${repo}" "${github_mcp_path}"; then
        source_label="远程目录 ${repo}@${github_ref}:${github_mcp_path}"
        return
      fi

      raw_url="https://raw.githubusercontent.com/${repo}/${github_ref}/${bundle_path}"
    else
      raw_url="https://raw.githubusercontent.com/${repo}/${github_ref}/${github_mcp_path}"
    fi

    if curl_download_with_retry "${raw_url}" "${tmp_source_file}" 2 5 20; then
      source_label="远程文件 ${raw_url}"
      return
    fi

    if mcp_use_local_fallback; then
      echo "警告: 远程拉取失败，已回退到本地文件: ${source_label#本地回退 }" >&2
      return
    fi

    echo "错误: 无法拉取远程文件 ${raw_url}" >&2
    echo "提示: 可使用 --source 指定本地目录或文件，例如: --source mcp" >&2
    exit 1
  }

  mcp_discover_servers() {
    tmp_parse_dir="$(new_tmp_dir)"

    while IFS=$'\t' read -r name title desc_encoded block; do
      [[ -z "${name}" ]] && continue
      desc="$(printf '%s' "${desc_encoded}" | sed 's/\\n/\n/g')"

      server_names+=("${name}")
      server_titles+=("${title}")
      server_descs+=("${desc}")
      selected+=(0)
      source_block_by_name["${name}"]="${block}"
    done < <(
      awk -v out_dir="${tmp_parse_dir}" '
        function trim(s) {
          sub(/^[[:space:]]+/, "", s)
          sub(/[[:space:]]+$/, "", s)
          return s
        }
        function append_text(origin, line) {
          if (origin == "") {
            return line
          }
          return origin "\n" line
        }
        function flush_entry(    safe_title, safe_desc, block_file) {
          if (server == "") {
            return
          }

          title = trim(title)
          desc = trim(desc)
          code = trim(code)

          if (title == "") {
            title = server
          }
          if (desc == "") {
            desc = title
          }
          if (code == "") {
            print "警告: MCP Markdown 条目缺少配置代码块，已跳过: " server > "/dev/stderr"
            server = ""
            title = ""
            desc = ""
            code = ""
            section = ""
            in_code = 0
            return
          }

          block_idx++
          block_file = out_dir "/block-" block_idx ".toml"
          print code > block_file
          close(block_file)

          safe_title = title
          gsub(/\t/, "    ", safe_title)
          gsub(/\n/, " ", safe_title)

          safe_desc = desc
          gsub(/\t/, "    ", safe_desc)
          gsub(/\n/, "\\n", safe_desc)

          printf "%s\t%s\t%s\t%s\n", server, safe_title, safe_desc, block_file

          server = ""
          title = ""
          desc = ""
          code = ""
          section = ""
          in_code = 0
        }

        BEGIN {
          server = ""
          title = ""
          desc = ""
          code = ""
          section = ""
          in_code = 0
          block_idx = 0
        }

        {
          line = $0

          if (line ~ /^#[[:space:]]+mcp_servers\./) {
            flush_entry()

            header = line
            sub(/^#[[:space:]]+mcp_servers\./, "", header)
            server = header
            sub(/[[:space:]].*$/, "", server)

            title = header
            sub(/^[^[:space:]]+[[:space:]]*/, "", title)
            title = trim(title)
            next
          }

          if (server == "") {
            next
          }

          if (line ~ /^##[[:space:]]+标题[[:space:]]*$/) {
            section = "title"
            in_code = 0
            next
          }
          if (line ~ /^##[[:space:]]+说明[[:space:]]*$/) {
            section = "desc"
            in_code = 0
            next
          }
          if (line ~ /^##[[:space:]]+(安装命令|配置)[[:space:]]*$/) {
            section = "config"
            in_code = 0
            next
          }

          if (section == "config" && line ~ /^```/) {
            if (in_code == 0) {
              in_code = 1
            } else {
              in_code = 0
            }
            next
          }

          if (in_code == 1) {
            code = append_text(code, line)
            next
          }

          if (section == "title") {
            if (trim(line) != "") {
              title = append_text(title, trim(line))
            }
            next
          }
          if (section == "desc") {
            if (trim(line) == "" && desc == "") {
              next
            }
            desc = append_text(desc, line)
          }
        }

        END {
          flush_entry()
        }
      ' "${tmp_source_file}"
    )

    if [[ ${#server_names[@]} -eq 0 ]]; then
      echo "错误: 未在 MCP 来源中发现可安装的 mcp server" >&2
      exit 1
    fi
  }

  mcp_render_menu() {
    echo
    echo "可安装的 MCP servers（来源: ${source_label}）"
    for i in "${!server_names[@]}"; do
      if [[ "${selected[i]}" -eq 1 ]]; then
        printf "%2d. [x] %s : %s\n" "$((i + 1))" "${server_names[i]}" "${server_titles[i]}"
      else
        printf "%2d. [ ] %s : %s\n" "$((i + 1))" "${server_names[i]}" "${server_titles[i]}"
      fi
      first_line="$(printf "%s\n" "${server_descs[i]}" | sed -n '1p')"
      if [[ -n "${first_line}" ]]; then
        printf "    %s\n" "${first_line}"
      fi
      rest_lines="$(printf "%s\n" "${server_descs[i]}" | sed -n '2,$p')"
      if [[ -n "${rest_lines}" ]]; then
        while IFS= read -r line; do
          [[ -z "${line}" ]] && continue
          printf "    %s\n" "${line}"
        done < <(printf "%s\n" "${rest_lines}")
      fi
    done
    echo
    echo "操作: 输入名称或编号切换勾选（支持空格/逗号），a=全选，n=全不选，i=反选，v=预览已选内容，d=开始安装，q=退出"
  }

  mcp_toggle_by_indices() {
    local input="$1"
    local token idx matched

    input="${input//,/ }"
    for token in ${input}; do
      if [[ "${token}" =~ ^[0-9]+$ ]]; then
        if (( token >= 1 && token <= ${#server_names[@]} )); then
          idx=$((token - 1))
          if [[ "${selected[idx]}" -eq 1 ]]; then
            selected[idx]=0
          else
            selected[idx]=1
          fi
        else
          echo "无效编号: ${token}"
        fi
      else
        matched="false"
        for idx in "${!server_names[@]}"; do
          if [[ "${token}" == "${server_names[idx]}" ]]; then
            if [[ "${selected[idx]}" -eq 1 ]]; then
              selected[idx]=0
            else
              selected[idx]=1
            fi
            matched="true"
            break
          fi
        done
        if [[ "${matched}" != "true" ]]; then
          echo "无效输入: ${token}"
        fi
      fi
    done
  }

  mcp_preview_selected_items() {
    local preview_file
    selected_count=0
    for i in "${!selected[@]}"; do
      [[ "${selected[i]}" -eq 1 ]] && ((selected_count += 1))
    done

    if (( selected_count == 0 )); then
      echo "当前未勾选任何 MCP server。"
      return
    fi

    preview_file="$(new_tmp_file)"
    {
      echo "已选 MCP servers 预览（共 ${selected_count} 项）"
      echo "来源: ${source_label}"
      echo
      for i in "${!selected[@]}"; do
        [[ "${selected[i]}" -ne 1 ]] && continue

        echo "[$((i + 1))] ${server_names[i]} - ${server_titles[i]}"
        while IFS= read -r line; do
          [[ -z "${line}" ]] && continue
          echo "  ${line}"
        done < <(printf "%s\n" "${server_descs[i]}")
        echo "  配置:"
        src_block="${source_block_by_name[${server_names[i]}]:-}"
        if [[ -n "${src_block}" && -f "${src_block}" ]]; then
          while IFS= read -r line; do
            echo "    ${line}"
          done < "${src_block}"
        else
          echo "    (未找到配置代码块)"
        fi
        echo
      done
    } > "${preview_file}"

    if command -v less >/dev/null 2>&1 && [[ -t 1 ]]; then
      less "${preview_file}"
    else
      cat "${preview_file}"
    fi
  }

  mcp_interactive_select() {
    tty_opened="false"
    done_select="false"

    if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
      tty_opened="true"
    fi

    while true; do
      mcp_render_menu

      if [[ "${tty_opened}" == "true" ]]; then
        printf "> " >&9
        IFS= read -r cmd <&9 || cmd="q"
      else
        read -r -p "> " cmd || cmd="q"
      fi

      case "${cmd}" in
        a|A)
          for i in "${!selected[@]}"; do selected[i]=1; done
          ;;
        n|N)
          for i in "${!selected[@]}"; do selected[i]=0; done
          ;;
        i|I)
          for i in "${!selected[@]}"; do
            if [[ "${selected[i]}" -eq 1 ]]; then
              selected[i]=0
            else
              selected[i]=1
            fi
          done
          ;;
        v|V)
          mcp_preview_selected_items
          ;;
        d|D)
          selected_count=0
          for i in "${!selected[@]}"; do
            [[ "${selected[i]}" -eq 1 ]] && ((selected_count += 1))
          done
          if (( selected_count == 0 )); then
            echo "未勾选任何 MCP server，请先勾选。"
          else
            done_select="true"
            break
          fi
          ;;
        q|Q)
          echo "已取消安装。"
          done_select="false"
          break
          ;;
        "")
          ;;
        *)
          mcp_toggle_by_indices "${cmd}"
          ;;
      esac
    done

    if [[ "${tty_opened}" == "true" ]]; then
      exec 9<&-
    fi

    [[ "${done_select}" == "true" ]]
  }

  mcp_extract_server_block_to_file() {
    local file="$1"
    local server="$2"
    local out_file="$3"

    awk -v server="${server}" '
      function is_header(line) {
        return (line ~ /^\[[^]]+\][[:space:]]*$/)
      }
      function is_target_header(line) {
        return (line ~ ("^\\[mcp_servers\\." server "(\\.|\\])"))
      }
      {
        if (is_header($0)) {
          if (is_target_header($0)) {
            printing = 1
          } else if (printing == 1) {
            exit
          }
        }
        if (printing == 1) {
          print
        }
      }
    ' "${file}" > "${out_file}"
  }

  mcp_normalize_block_file() {
    local in_file="$1"
    local out_file="$2"
    awk '
      {
        line = $0
        sub(/[[:space:]]+$/, "", line)
        lines[NR] = line
        if (line != "") {
          last_non_empty = NR
        }
      }
      END {
        for (i = 1; i <= last_non_empty; i++) {
          print lines[i]
        }
      }
    ' "${in_file}" > "${out_file}"
  }

  mcp_is_secret_key() {
    local key="$1"
    [[ "${key}" =~ (TOKEN|API_KEY|AUTH|SECRET|PASSWORD|ACCESS_KEY|SESSION) ]]
  }

  mcp_is_secret_placeholder() {
    local value="$1"
    [[ -z "${value}" || "${value}" =~ ^[xX]{4,}$ || "${value}" =~ ^your[-_].* || "${value}" =~ ^YOUR[-_].* || "${value}" =~ ^\<.*\>$ ]]
  }

  mcp_escape_toml_string_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf "%s\n" "${value}"
  }

  mcp_prompt_config_value() {
    local server="$1"
    local label="$2"
    local env_name="${3:-}"
    local answer=""
    local env_value=""
    local tty_opened="false"
    mcp_prompt_value_result=""

    if [[ -n "${env_name}" ]]; then
      env_value="${!env_name:-}"
      if [[ -n "${env_value}" ]]; then
        mcp_prompt_value_result="${env_value}"
        echo "已使用环境变量 ${env_name} 填充 ${server} 的 ${label}。"
        return 0
      fi
    fi

    if [[ "${AUTO_YES}" == "true" ]]; then
      echo "提示: ${server} 的 ${label} 仍是占位值；--yes 模式不会交互输入，已保留原占位。"
      return 1
    fi

    if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
      tty_opened="true"
    fi

    if [[ "${tty_opened}" == "true" ]]; then
      printf "请输入 %s 的 %s（留空保留原占位）: " "${server}" "${label}" >&9
      IFS= read -r -s answer <&9 || true
      printf "\n" >&9
      exec 9<&-
    else
      printf "请输入 %s 的 %s（留空保留原占位）: " "${server}" "${label}"
      IFS= read -r answer || true
    fi

    if [[ -z "${answer}" ]]; then
      echo "已保留 ${server} 的 ${label} 占位值。"
      return 1
    fi

    mcp_prompt_value_result="${answer}"
    echo "已接收 ${server} 的 ${label}，将写入目标配置。"
    return 0
  }

  mcp_prepare_configurable_block() {
    local server="$1"
    local block_file="$2"
    local tmp_block line new_line key current escaped changed prefix assign_suffix line_suffix

    if [[ -z "${block_file}" || ! -s "${block_file}" ]]; then
      return 0
    fi

    tmp_block="$(new_tmp_file)"
    changed="false"

    while IFS= read -r line <&8 || [[ -n "${line}" ]]; do
      new_line="${line}"

      if [[ "${line}" =~ ^([[:space:]]*)([A-Za-z_][A-Za-z0-9_]*)([[:space:]]*=[[:space:]]*)\"([^\"]*)\"(.*)$ ]]; then
        # BASH_REMATCH 是全局状态，调用其他正则函数前必须先保存捕获值。
        prefix="${BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
        assign_suffix="${BASH_REMATCH[3]}"
        current="${BASH_REMATCH[4]}"
        line_suffix="${BASH_REMATCH[5]}"
        if mcp_is_secret_key "${key}" && mcp_is_secret_placeholder "${current}"; then
          if mcp_prompt_config_value "${server}" "${key}" "${key}"; then
            escaped="$(mcp_escape_toml_string_value "${mcp_prompt_value_result}")"
            new_line="${prefix}${key}${assign_suffix}\"${escaped}\"${line_suffix}"
            changed="true"
          fi
        fi
      elif [[ "${line}" == *"--api-key"* && "${line}" == *'""'* ]]; then
        if mcp_prompt_config_value "${server}" "--api-key" ""; then
          escaped="$(mcp_escape_toml_string_value "${mcp_prompt_value_result}")"
          new_line="${line/\"\"/\"${escaped}\"}"
          changed="true"
        fi
      elif [[ "${line}" =~ Authorization\"[[:space:]]*=[[:space:]]*\"Bearer[[:space:]]+([^\"]*)\" ]]; then
        current="${BASH_REMATCH[1]}"
        if mcp_is_secret_placeholder "${current}"; then
          if mcp_prompt_config_value "${server}" "Authorization Bearer token" ""; then
            escaped="$(mcp_escape_toml_string_value "${mcp_prompt_value_result}")"
            new_line="${line/Bearer ${current}/Bearer ${escaped}}"
            changed="true"
          fi
        fi
      fi

      printf "%s\n" "${new_line}" >> "${tmp_block}"
    done 8< "${block_file}"

    if [[ "${changed}" == "true" ]]; then
      cp "${tmp_block}" "${block_file}"
    fi
  }

  mcp_replace_server_block() {
    local target_file="$1"
    local server="$2"
    local source_block_file="$3"
    local tmp_out
    tmp_out="$(new_tmp_file)"

    awk -v server="${server}" -v block_file="${source_block_file}" '
      BEGIN {
        while ((getline line < block_file) > 0) {
          new_block = new_block line ORS
        }
        close(block_file)
      }
      function is_header(line) {
        return (line ~ /^\[[^]]+\][[:space:]]*$/)
      }
      function is_target_header(line) {
        return (line ~ ("^\\[mcp_servers\\." server "(\\.|\\])"))
      }
      {
        if (is_header($0)) {
          if (is_target_header($0)) {
            if (!replaced) {
              printf "%s", new_block
              replaced = 1
            }
            skipping = 1
            next
          }
          if (skipping) {
            skipping = 0
          }
        }
        if (!skipping) {
          print
        }
      }
    ' "${target_file}" > "${tmp_out}"

    cp "${tmp_out}" "${target_file}"
  }

  mcp_append_server_block() {
    local target_file="$1"
    local source_block_file="$2"
    local has_any_mcp="false"
    local has_root_mcp="false"

    if grep -Eq '^[[:space:]]*\[mcp_servers(\.|])' "${target_file}" 2>/dev/null; then
      has_any_mcp="true"
    fi
    if grep -Eq '^[[:space:]]*\[mcp_servers\][[:space:]]*$' "${target_file}" 2>/dev/null; then
      has_root_mcp="true"
    fi

    if [[ -s "${target_file}" ]]; then
      printf "\n" >> "${target_file}"
    fi

    if [[ "${has_any_mcp}" == "false" && "${has_root_mcp}" == "false" ]]; then
      printf "[mcp_servers]\n\n" >> "${target_file}"
    fi

    cat "${source_block_file}" >> "${target_file}"
  }

  mcp_collect_upsert_targets() {
    local status dst_block src_norm dst_norm
    tmp_status_dir="$(new_tmp_dir)"

    for i in "${!server_names[@]}"; do
      [[ "${selected[i]}" -eq 1 ]] && selected_names+=("${server_names[i]}")
    done

    if [[ ${#selected_names[@]} -eq 0 ]]; then
      echo "未选择任何 MCP server。"
      exit 0
    fi

    for name in "${selected_names[@]}"; do
      src_block="${source_block_by_name[$name]:-}"
      mcp_prepare_configurable_block "${name}" "${src_block}"
    done

    if [[ ! -f "${target_config}" ]]; then
      mkdir -p "$(dirname "${target_config}")"
      : > "${target_config}"
    fi

    for name in "${selected_names[@]}"; do
      src_block="${source_block_by_name[$name]:-}"
      dst_block="${tmp_status_dir}/dst-${name}.toml"
      src_norm="${tmp_status_dir}/src-${name}.norm"
      dst_norm="${tmp_status_dir}/dst-${name}.norm"

      if [[ -z "${src_block}" || ! -s "${src_block}" ]]; then
        echo "警告: MCP 来源中不存在 ${name} 的配置代码块，已跳过。"
        continue
      fi

      mcp_extract_server_block_to_file "${target_config}" "${name}" "${dst_block}"

      if [[ ! -s "${dst_block}" ]]; then
        status="missing"
      else
        mcp_normalize_block_file "${src_block}" "${src_norm}"
        mcp_normalize_block_file "${dst_block}" "${dst_norm}"
        if cmp -s "${src_norm}" "${dst_norm}"; then
          status="same"
        else
          status="different"
        fi
      fi

      case "${status}" in
        same)
          echo "已存在且一致，跳过: ${name}"
          ;;
        missing)
          upsert+=("${name}")
          echo "将新增: ${name}"
          ;;
        different)
          if confirm "配置 ${name} 已存在且不同，是否覆盖?" "N"; then
            upsert+=("${name}")
            echo "将覆盖: ${name}"
          else
            echo "跳过覆盖: ${name}"
          fi
          ;;
      esac
    done
  }

  mcp_apply_merge() {
    local dst_block
    if [[ ${#upsert[@]} -eq 0 ]]; then
      echo
      echo "无需更新，未对 ${target_config} 做任何修改。"
      return 0
    fi

    for name in "${upsert[@]}"; do
      src_block="${source_block_by_name[$name]:-}"
      dst_block="${tmp_status_dir}/dst-apply-${name}.toml"

      if [[ -z "${src_block}" || ! -s "${src_block}" ]]; then
        echo "警告: 跳过 ${name}（MCP 配置代码块不存在）"
        continue
      fi

      mcp_extract_server_block_to_file "${target_config}" "${name}" "${dst_block}"
      if [[ -s "${dst_block}" ]]; then
        mcp_replace_server_block "${target_config}" "${name}" "${src_block}"
      else
        mcp_append_server_block "${target_config}" "${src_block}"
      fi
    done
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --source 需要参数" >&2
          return 1
        fi
        source_mode="source"
        source_input="${2:-}"
        shift 2
        ;;
      --github)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --github 需要参数" >&2
          return 1
        fi
        source_mode="github"
        github_repo="${2:-}"
        shift 2
        ;;
      --ref)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --ref 需要参数" >&2
          return 1
        fi
        if [[ "${source_mode}" != "source" ]]; then
          source_mode="github"
        fi
        github_ref="${2:-}"
        shift 2
        ;;
      --mcp-path)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --mcp-path 需要参数" >&2
          return 1
        fi
        if [[ "${source_mode}" != "source" ]]; then
          source_mode="github"
        fi
        github_mcp_path="${2:-}"
        shift 2
        ;;
      --config)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --config 需要参数" >&2
          return 1
        fi
        target_config="${2:-}"
        shift 2
        ;;
      -h|--help)
        mcp_usage
        return "${HELP_EXIT_CODE}"
        ;;
      *)
        echo "错误: mcp 不支持参数: $1" >&2
        mcp_usage
        return 1
        ;;
    esac
  done

  mcp_fetch_source_file
  mcp_discover_servers
  if ! mcp_interactive_select; then
    return 0
  fi
  mcp_collect_upsert_targets
  mcp_apply_merge

  echo
  echo "MCP 处理完成，目标文件: ${target_config}"
}

install_all_main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cat <<'EOF'
用法:
  ./shell/codex/install_codex.sh all

说明:
  all 模式会按顺序执行 mcp -> agents -> skills。
  每一步都会先列出选项，用户必须手动选择并输入 d 后才安装。
EOF
        return "${HELP_EXIT_CODE}"
        ;;
      *)
        echo "错误: all 模式不支持参数: $1" >&2
        return 1
        ;;
    esac
  done

  echo ">>> 开始执行 MCP 安装"
  install_mcp_main

  echo
  echo ">>> 开始执行 AGENTS 安装"
  install_agents_main

  echo
  echo ">>> 开始执行 Skills 安装"
  install_skills_main
}

main() {
  local mode=""
  local rc=0

  if [[ $# -gt 0 ]]; then
    case "$1" in
      mcp|agents|skills|all)
        mode="$1"
        shift
        ;;
    esac
  fi

  while [[ -z "${mode}" && $# -gt 0 ]]; do
    case "$1" in
      --target)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --target 需要参数" >&2
          usage
          return 1
        fi
        mode="${2:-}"
        shift 2
        ;;
      --mcp)
        mode="mcp"
        shift
        ;;
      --agents)
        mode="agents"
        shift
        ;;
      --skills)
        mode="skills"
        shift
        ;;
      --all)
        mode="all"
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -z "${mode}" ]]; then
    choose_target_interactive
    mode="${CHOSEN_MODE}"
  fi

  case "${mode}" in
    mcp)
      install_mcp_main "$@" || rc=$?
      ;;
    agents)
      install_agents_main "$@" || rc=$?
      ;;
    skills)
      install_skills_main "$@" || rc=$?
      ;;
    all)
      install_all_main "$@" || rc=$?
      ;;
    exit)
      echo "已取消安装。"
      return 0
      ;;
    *)
      echo "错误: 不支持的目标类型: ${mode}" >&2
      usage
      return 1
      ;;
  esac

  if [[ "${rc}" -eq "${HELP_EXIT_CODE}" ]]; then
    return 0
  fi
  if [[ "${rc}" -ne 0 ]]; then
    return "${rc}"
  fi

  echo
  echo "全部操作完成。"
}

main "$@"
