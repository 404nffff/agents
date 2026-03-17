#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SOURCE_FILE="${SCRIPT_DIR}/AGENTS.md"
TARGET_USER_FILE="${HOME}/.codex/AGENTS.md"

SOURCE_MODE=""
SOURCE_INPUT=""
GITHUB_REPO=""
GITHUB_REF="main"
GITHUB_FILE="AGENTS.md"

COLOR_RED=""
COLOR_GREEN=""
COLOR_CYAN=""
COLOR_GRAY=""
COLOR_RESET=""

init_colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_CYAN=$'\033[36m'
    COLOR_GRAY=$'\033[90m'
    COLOR_RESET=$'\033[0m'
  fi
}

usage() {
  cat <<'EOF'
用法:
  ./install_agents.sh [--source <path_or_url>]
  ./install_agents.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--file <path_in_repo>]

说明:
  --source   AGENTS.md 源地址，可为本地路径或 http(s) URL
  --github   GitHub 仓库地址（owner/repo 或完整 URL）
  --ref      GitHub 分支或标签，默认 main
  --file     仓库内文件路径，默认 AGENTS.md
EOF
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer=""

  if [[ "${default}" == "Y" ]]; then
    read -r -p "${prompt} [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "${prompt} [y/N]: " answer
    answer="${answer:-N}"
  fi

  [[ "${answer}" =~ ^[Yy]$ ]]
}

preview_file() {
  local file="$1"
  local lines="${2:-20}"
  local total_lines
  total_lines="$(wc -l < "${file}" | tr -d ' ')"

  echo "----- 原文件前 ${lines} 行预览: ${file} -----"
  sed -n "1,${lines}p" "${file}"
  if (( total_lines > lines )); then
    echo "......(共 ${total_lines} 行，仅预览前 ${lines} 行)"
  fi
  echo "-------------------------------------------"
}

show_diff_preview() {
  local old_file="$1"
  local new_file="$2"
  local max_lines="${3:-120}"
  local tmp_diff
  tmp_diff="$(mktemp)"

  if diff -u "${old_file}" "${new_file}" > "${tmp_diff}"; then
    echo "原文件与新文件无差异。"
    rm -f "${tmp_diff}"
    return 0
  fi

  local tmp_fmt
  tmp_fmt="$(mktemp)"
  awk '
    BEGIN {
      print "----- 变更预览（[- 删除] [+ 新增] [= 上下文]）-----"
    }
    /^--- / { next }
    /^\+\+\+ / { next }
    /^@@/ {
      print $0
      next
    }
    /^-/ {
      print "[- 删除] " substr($0, 2)
      next
    }
    /^\+/ {
      print "[+ 新增] " substr($0, 2)
      next
    }
    /^ / {
      print "[= 上下文] " substr($0, 2)
      next
    }
  ' "${tmp_diff}" > "${tmp_fmt}"

  local total_lines
  total_lines="$(wc -l < "${tmp_fmt}" | tr -d ' ')"
  awk -v max="${max_lines}" \
      -v red="${COLOR_RED}" \
      -v green="${COLOR_GREEN}" \
      -v cyan="${COLOR_CYAN}" \
      -v gray="${COLOR_GRAY}" \
      -v reset="${COLOR_RESET}" '
    NR > max { exit }
    /^\[- 删除\]/ { print red $0 reset; next }
    /^\[\+ 新增\]/ { print green $0 reset; next }
    /^\[= 上下文\]/ { print gray $0 reset; next }
    /^@@/ { print cyan $0 reset; next }
    { print }
  ' "${tmp_fmt}"
  if (( total_lines > max_lines )); then
    echo "......(变更预览共 ${total_lines} 行，仅显示前 ${max_lines} 行)"
  fi
  echo "-----------------------------------------------"
  rm -f "${tmp_diff}"
  rm -f "${tmp_fmt}"
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

  if [[ -f "${DEFAULT_SOURCE_FILE}" ]]; then
    cp "${DEFAULT_SOURCE_FILE}" "${out_file}"
    return
  fi

  echo "错误: 未找到默认源文件 ${DEFAULT_SOURCE_FILE}" >&2
  exit 1
}

install_with_prompt() {
  local target_file="$1"
  local tmp_source_file="$2"
  local label="$3"

  mkdir -p "$(dirname "${target_file}")"

  if [[ -f "${target_file}" ]]; then
    echo "${label} 已存在: ${target_file}"
    show_diff_preview "${target_file}" "${tmp_source_file}" 120
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

init_colors

# 未传参数时直接使用默认源文件，不再额外询问来源。
if [[ -z "${SOURCE_MODE}" ]]; then
  echo "未指定来源，使用默认源: ${DEFAULT_SOURCE_FILE}"
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
