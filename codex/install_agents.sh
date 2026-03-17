#!/usr/bin/env bash
set -euo pipefail

# 兼容通过 stdin 执行（如: curl ... | bash）时 BASH_SOURCE 可能未定义的场景。
SCRIPT_PATH="${0:-}"
if [[ -n "${BASH_SOURCE:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR=""
if [[ -n "${SCRIPT_PATH}" ]] && [[ "${SCRIPT_PATH}" == */* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
fi
DEFAULT_SOURCE_FILE=""
if [[ -n "${SCRIPT_DIR}" ]]; then
  DEFAULT_SOURCE_FILE="${SCRIPT_DIR}/AGENTS.md"
fi
DEFAULT_REMOTE_SOURCE="https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md"
TARGET_USER_FILE="${HOME}/.codex/AGENTS.md"

SOURCE_MODE=""
SOURCE_INPUT=""
GITHUB_REPO=""
GITHUB_REF="main"
GITHUB_FILE="AGENTS.md"
AUTO_YES="false"

usage() {
  cat <<'EOF'
用法:
  ./install_agents.sh [--source <path_or_url>]
  ./install_agents.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--file <path_in_repo>]
  ./install_agents.sh [--yes]

说明:
  --source   AGENTS.md 源地址，可为本地路径或 http(s) URL
  --github   GitHub 仓库地址（owner/repo 或完整 URL）
  --ref      GitHub 分支或标签，默认 main
  --file     仓库内文件路径，默认 AGENTS.md
  --yes      无交互模式，遇到可替换文件时自动替换
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

  if exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  if [[ "${default}" == "Y" ]]; then
    if [[ "${tty_opened}" == "true" ]]; then
      printf "%s [Y/n]: " "${prompt}" >&9
      IFS= read -r answer <&9 || true
    fi
    answer="${answer:-Y}"
  else
    if [[ "${tty_opened}" == "true" ]]; then
      printf "%s [y/N]: " "${prompt}" >&9
      IFS= read -r answer <&9 || true
    fi
    answer="${answer:-N}"
  fi

  if [[ "${tty_opened}" == "true" ]]; then
    exec 9<&-
  fi

  [[ "${answer}" =~ ^[Yy]$ ]]
}

preview_file() {
  local file="$1"
  local lines="${2:-20}"
  local title="${3:-文件内容预览}"
  local total_lines
  total_lines="$(wc -l < "${file}" | tr -d ' ')"

  echo "----- ${title}（前 ${lines} 行）: ${file} -----"
  sed -n "1,${lines}p" "${file}"
  if (( total_lines > lines )); then
    echo "......(共 ${total_lines} 行，仅预览前 ${lines} 行)"
  fi
  echo "-------------------------------------------"
}


normalize_github_repo() {
  local repo="$1"
  repo="${repo#https://github.com/}"
  repo="${repo#http://github.com/}"
  repo="${repo%.git}"
  echo "${repo}"
}

fetch_source_to_tmp() {
  local out_file="$1"

  if [[ "${SOURCE_MODE}" == "source" ]]; then
    if [[ "${SOURCE_INPUT}" =~ ^https?:// ]]; then
      curl -fsSL "${SOURCE_INPUT}" -o "${out_file}"
    else
      if [[ ! -f "${SOURCE_INPUT}" ]]; then
        echo "错误: 源文件不存在: ${SOURCE_INPUT}" >&2
        exit 1
      fi
      cp "${SOURCE_INPUT}" "${out_file}"
    fi
    return
  fi

  if [[ "${SOURCE_MODE}" == "github" ]]; then
    local repo
    repo="$(normalize_github_repo "${GITHUB_REPO}")"
    local raw_url="https://raw.githubusercontent.com/${repo}/${GITHUB_REF}/${GITHUB_FILE}"
    curl -fsSL "${raw_url}" -o "${out_file}"
    return
  fi

  # 无参数时优先使用仓库远程源；失败后回退到本地同目录 AGENTS.md。
  if curl -fsSL "${DEFAULT_REMOTE_SOURCE}" -o "${out_file}"; then
    return
  fi

  if [[ -n "${DEFAULT_SOURCE_FILE}" && -f "${DEFAULT_SOURCE_FILE}" ]]; then
    cp "${DEFAULT_SOURCE_FILE}" "${out_file}"
    return
  fi

  echo "错误: 默认远程源与本地源都不可用。" >&2
  echo "远程: ${DEFAULT_REMOTE_SOURCE}" >&2
  echo "本地: ${DEFAULT_SOURCE_FILE:-<不可用>}" >&2
  exit 1
}

install_with_prompt() {
  local target_file="$1"
  local tmp_source_file="$2"
  local label="$3"

  mkdir -p "$(dirname "${target_file}")"

  if [[ -f "${target_file}" ]]; then
    echo "${label} 已存在: ${target_file}"
    if cmp -s "${target_file}" "${tmp_source_file}"; then
      echo "原文件与新文件无差异，已跳过替换 ${label}"
      return 0
    fi
    preview_file "${target_file}" 20 "旧文件内容预览"
    preview_file "${tmp_source_file}" 20 "新文件内容预览"
    if confirm "是否替换 ${label}?" "N"; then
      cp "${tmp_source_file}" "${target_file}"
      echo "已替换 ${label}: ${target_file}"
    else
      echo "已跳过替换 ${label}"
    fi
  else
    cp "${tmp_source_file}" "${target_file}"
    echo "已创建 ${label}: ${target_file}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_MODE="source"
      SOURCE_INPUT="${2:-}"
      shift 2
      ;;
    --github)
      SOURCE_MODE="github"
      GITHUB_REPO="${2:-}"
      shift 2
      ;;
    --ref)
      GITHUB_REF="${2:-}"
      shift 2
      ;;
    --file)
      GITHUB_FILE="${2:-}"
      shift 2
      ;;
    --yes)
      AUTO_YES="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${SOURCE_MODE}" == "source" && -z "${SOURCE_INPUT}" ]]; then
  echo "错误: --source 不能为空" >&2
  exit 1
fi

if [[ "${SOURCE_MODE}" == "github" && -z "${GITHUB_REPO}" ]]; then
  echo "错误: --github 不能为空" >&2
  exit 1
fi

# 未传参数时直接使用默认源文件，不再额外询问来源。
if [[ -z "${SOURCE_MODE}" ]]; then
  echo "未指定来源，默认使用仓库源: ${DEFAULT_REMOTE_SOURCE}"
fi

TMP_SOURCE="$(mktemp)"
trap 'rm -f "${TMP_SOURCE}"' EXIT

fetch_source_to_tmp "${TMP_SOURCE}"

if [[ ! -s "${TMP_SOURCE}" ]]; then
  echo "错误: 获取到的 AGENTS.md 为空" >&2
  exit 1
fi

echo "准备安装 AGENTS.md ..."
install_with_prompt "${TARGET_USER_FILE}" "${TMP_SOURCE}" "~/.codex/AGENTS.md"

CURRENT_DIR_FILE="$(pwd)/AGENTS.md"
if confirm "是否在当前目录生成或更新 AGENTS.md?" "N"; then
  install_with_prompt "${CURRENT_DIR_FILE}" "${TMP_SOURCE}" "当前目录 AGENTS.md"
else
  echo "已跳过当前目录 AGENTS.md"
fi

echo "完成。"
