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
DEFAULT_GITHUB_AGENTS_PATH="agents"
LOCAL_AGENTS_ROOT="${REPO_ROOT}/agents"
TARGET_ROOT="${HOME}/.codex"
TARGET_AGENT_FILE="AGENTS.md"
PROJECT_TARGET_FILE="$(pwd)/AGENTS.md"

SOURCE_MODE=""
SOURCE_INPUT=""
GITHUB_REPO=""
GITHUB_REF="${DEFAULT_GITHUB_REF}"
GITHUB_FILE=""
GITHUB_AGENTS_PATH="${DEFAULT_GITHUB_AGENTS_PATH}"
AUTO_YES="false"

TMP_FILES=()

new_tmp_file() {
  local p
  p="$(mktemp)"
  TMP_FILES+=("${p}")
  printf "%s\n" "${p}"
}

cleanup() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "${f}" && -f "${f}" ]] && rm -f "${f}" || true
  done
}

trap cleanup EXIT

declare -a AGENT_NAMES=()
declare -a AGENT_DESCS=()
declare -a AGENT_PATHS=()
declare -a AGENT_GROUPS=()
declare -a SELECTED=()
declare -A SEEN_PATHS=()

usage() {
  cat <<'USAGE'
用法:
  ./shell/codex/install_agents.sh
  ./shell/codex/install_agents.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--agents-path <path_in_repo>]
  ./shell/codex/install_agents.sh [--source <path_or_url>]
  ./shell/codex/install_agents.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--file <path_in_repo>]
  ./shell/codex/install_agents.sh [--yes]

说明:
  1) 本地执行优先扫描本地 agents 目录
  2) 网络请求执行时，先读取远程 agents/README.md 展示可选 agent 文件列表
  3) 只能单选一个 agent 文件，安装时同时覆盖 ~/.codex/AGENTS.md 与当前项目目录 AGENTS.md
  4) 可通过 --github / --ref / --agents-path 指定远程来源
  5) 若本地存在同名文件，提示是否覆盖（--yes 自动覆盖）
  6) 兼容单文件安装：可使用 --source 或 --file 直接安装单个文件

参数:
  --source       单个 agent 文件源地址，可为本地路径或 http(s) URL
  --github       GitHub 仓库地址（owner/repo 或完整 URL）
  --ref          GitHub 分支或标签，默认 master
  --agents-path  仓库内 agents 目录路径，默认 agents
  --file         仓库内单个 agent 文件路径（与 --github 搭配）
  --yes          无交互模式，默认选择列表第 1 项并自动覆盖同名文件
USAGE
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
  printf "%s\n" "${repo}"
}

fetch_raw_from_github() {
  local repo="$1"
  local ref="$2"
  local path="$3"
  local out_file="$4"
  local raw_url

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 需要 curl 来拉取 GitHub 源。" >&2
    exit 1
  fi

  raw_url="https://raw.githubusercontent.com/${repo}/${ref}/${path}"
  curl -fsSL "${raw_url}" -o "${out_file}"
}

copy_local_or_url_to_file() {
  local source="$1"
  local out_file="$2"

  if [[ "${source}" =~ ^https?:// ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "错误: 需要 curl 来拉取 URL 源。" >&2
      exit 1
    fi
    curl -fsSL "${source}" -o "${out_file}"
    return
  fi

  if [[ ! -f "${source}" ]]; then
    echo "错误: 源文件不存在: ${source}" >&2
    exit 1
  fi

  cp "${source}" "${out_file}"
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

    preview_file "${target_file}" 20 "旧文件内容预览"
    preview_file "${source_file}" 20 "新文件内容预览"

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

add_agent_entry() {
  local name="$1"
  local rel_path="$2"
  local desc="$3"
  local group="${4:-}"

  [[ -z "${name}" || -z "${rel_path}" ]] && return
  [[ -z "${desc}" ]] && desc="(无 description)"

  if [[ -n "${SEEN_PATHS[${rel_path}]+x}" ]]; then
    echo "警告: 发现重复 agent 文件路径 '${rel_path}'，已忽略重复项。" >&2
    return
  fi

  SEEN_PATHS["${rel_path}"]=1
  AGENT_NAMES+=("${name}")
  AGENT_DESCS+=("${desc}")
  AGENT_PATHS+=("${rel_path}")
  AGENT_GROUPS+=("${group}")
  SELECTED+=(0)
}

parse_agents_catalog_from_readme() {
  local readme_file="$1"
  local local_root="${2:-}"
  local name rel_path desc group

  while IFS=$'\t' read -r name rel_path desc group; do
    [[ -z "${name}" || -z "${rel_path}" ]] && continue
    [[ -z "${desc}" ]] && desc="(无 description)"

    if [[ -n "${local_root}" && ! -f "${local_root}/${rel_path}" ]]; then
      echo "警告: README 中声明的 agent 文件不存在，已忽略: ${rel_path}" >&2
      continue
    fi

    add_agent_entry "${name}" "${rel_path}" "${desc}" "${group}"
  done < <(
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
  )
}

select_agents_interactively() {
  local cmd idx tty_opened selected_count group current_group

  if [[ "${AUTO_YES}" == "true" ]]; then
    for idx in "${!SELECTED[@]}"; do
      SELECTED[idx]=0
    done
    if [[ ${#SELECTED[@]} -gt 0 ]]; then
      SELECTED[0]=1
    fi
    return 0
  fi

  tty_opened="false"
  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  while true; do
    echo
    echo "可安装的 agent 文件（来源: ${SOURCE_LABEL}）"
    current_group=""
    for idx in "${!AGENT_NAMES[@]}"; do
      group="${AGENT_GROUPS[idx]:-}"
      if [[ -n "${group}" && "${group}" != "${current_group}" ]]; then
        echo
        printf "【%s】\n" "${group}"
        current_group="${group}"
      fi
      if [[ "${SELECTED[idx]}" -eq 1 ]]; then
        printf "%2d. [x] %s (%s)\n" "$((idx + 1))" "${AGENT_NAMES[idx]}" "${AGENT_PATHS[idx]}"
      else
        printf "%2d. [ ] %s (%s)\n" "$((idx + 1))" "${AGENT_NAMES[idx]}" "${AGENT_PATHS[idx]}"
      fi
      printf "    %s\n" "${AGENT_DESCS[idx]}"
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
        for idx in "${!SELECTED[@]}"; do
          [[ "${SELECTED[idx]}" -eq 1 ]] && ((selected_count += 1))
        done
        if (( selected_count != 1 )); then
          echo "请先且仅选择一个 agent 文件。"
        else
          break
        fi
        ;;
      q|Q)
        if [[ "${tty_opened}" == "true" ]]; then
          exec 9<&-
        fi
        echo "已取消安装。"
        exit 0
        ;;
      "")
        ;;
      *)
        if [[ "${cmd}" =~ ^[0-9]+$ ]]; then
          if (( cmd >= 1 && cmd <= ${#AGENT_NAMES[@]} )); then
            for idx in "${!SELECTED[@]}"; do
              SELECTED[idx]=0
            done
            idx=$((cmd - 1))
            SELECTED[idx]=1
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
}

SOURCE_LABEL=""
REMOTE_REPO=""
REMOTE_PATH=""
LOCAL_SOURCE_ROOT=""

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
      SOURCE_MODE="github"
      GITHUB_REF="${2:-}"
      shift 2
      ;;
    --file)
      SOURCE_MODE="github"
      GITHUB_FILE="${2:-}"
      shift 2
      ;;
    --agents-path)
      SOURCE_MODE="github"
      GITHUB_AGENTS_PATH="${2:-}"
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
  GITHUB_REPO="${DEFAULT_GITHUB_REPO}"
fi

if [[ "${SOURCE_MODE}" == "source" ]]; then
  tmp_source="$(new_tmp_file)"
  tmp_template="$(new_tmp_file)"
  copy_local_or_url_to_file "${SOURCE_INPUT}" "${tmp_source}"

  if [[ ! -s "${tmp_source}" ]]; then
    echo "错误: 获取到的 agent 文件为空" >&2
    exit 1
  fi

  file_name="$(basename "${SOURCE_INPUT%%\?*}")"
  [[ -z "${file_name}" ]] && file_name="AGENTS.md"
  install_file_with_prompt "${TARGET_ROOT}/${TARGET_AGENT_FILE}" "${tmp_source}" "~/.codex/${TARGET_AGENT_FILE}"
  install_file_with_prompt "${PROJECT_TARGET_FILE}" "${tmp_source}" "当前项目 AGENTS.md"
  if prepare_agents_v2_template_payload "${file_name}" "source" "${SOURCE_INPUT}" "" "" "" "" "${tmp_template}"; then
    install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
  fi
  echo "完成。"
  exit 0
fi

if [[ "${SOURCE_MODE}" == "github" && -n "${GITHUB_FILE}" ]]; then
  REMOTE_REPO="$(normalize_github_repo "${GITHUB_REPO}")"
  tmp_source="$(new_tmp_file)"
  tmp_template="$(new_tmp_file)"
  fetch_raw_from_github "${REMOTE_REPO}" "${GITHUB_REF}" "${GITHUB_FILE}" "${tmp_source}"

  if [[ ! -s "${tmp_source}" ]]; then
    echo "错误: 获取到的 agent 文件为空: ${GITHUB_FILE}" >&2
    exit 1
  fi

  file_name="$(basename "${GITHUB_FILE}")"
  install_file_with_prompt "${TARGET_ROOT}/${TARGET_AGENT_FILE}" "${tmp_source}" "~/.codex/${TARGET_AGENT_FILE}"
  install_file_with_prompt "${PROJECT_TARGET_FILE}" "${tmp_source}" "当前项目 AGENTS.md"
  if prepare_agents_v2_template_payload "${file_name}" "github_file" "${GITHUB_FILE}" "${REMOTE_REPO}" "${GITHUB_REF}" "" "" "${tmp_template}"; then
    install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
  fi
  echo "完成。"
  exit 0
fi

if [[ "${SOURCE_MODE}" != "github" && "${IS_NETWORK_REQUEST_EXECUTION}" != "true" && -d "${LOCAL_AGENTS_ROOT}" ]]; then
  LOCAL_SOURCE_ROOT="${LOCAL_AGENTS_ROOT}"
  SOURCE_LABEL="本地目录 ${LOCAL_SOURCE_ROOT}"

  if [[ -f "${LOCAL_SOURCE_ROOT}/README.md" ]]; then
    parse_agents_catalog_from_readme "${LOCAL_SOURCE_ROOT}/README.md" "${LOCAL_SOURCE_ROOT}"
  fi

  if [[ ${#AGENT_NAMES[@]} -eq 0 ]]; then
    while IFS= read -r src; do
      rel_path="$(basename "${src}")"
      name="${rel_path%.md}"
      add_agent_entry "${name}" "${rel_path}" "(无 description)"
    done < <(find "${LOCAL_SOURCE_ROOT}" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort)
  fi

  if [[ ${#AGENT_NAMES[@]} -eq 0 ]]; then
    echo "错误: 未在 ${LOCAL_SOURCE_ROOT} 下找到可安装的 agent 文件" >&2
    exit 1
  fi
else
  REMOTE_REPO="$(normalize_github_repo "${GITHUB_REPO:-${DEFAULT_GITHUB_REPO}}")"
  REMOTE_PATH="${GITHUB_AGENTS_PATH}"
  tmp_catalog_file="$(new_tmp_file)"

  if ! fetch_raw_from_github "${REMOTE_REPO}" "${GITHUB_REF}" "${REMOTE_PATH}/README.md" "${tmp_catalog_file}" >/dev/null 2>&1; then
    echo "错误: 无法读取远程 agents 目录清单 README.md" >&2
    echo "地址: https://raw.githubusercontent.com/${REMOTE_REPO}/${GITHUB_REF}/${REMOTE_PATH}/README.md" >&2
    exit 1
  fi

  parse_agents_catalog_from_readme "${tmp_catalog_file}"
  if [[ ${#AGENT_NAMES[@]} -eq 0 ]]; then
    echo "错误: 远程 agents README.md 未包含可解析目录（缺少 AGENT_CATALOG 标记或内容为空）" >&2
    exit 1
  fi
  SOURCE_LABEL="远程目录 ${REMOTE_REPO}@${GITHUB_REF}:${REMOTE_PATH}（先读取 README 列表）"
fi

select_agents_interactively

selected_count=0
for idx in "${!SELECTED[@]}"; do
  [[ "${SELECTED[idx]}" -eq 1 ]] && ((selected_count += 1))
done
if (( selected_count != 1 )); then
  echo "请选择且仅选择一个 agent 文件，已取消安装。"
  exit 0
fi

echo
echo "开始安装到: ${TARGET_ROOT}"
for idx in "${!AGENT_NAMES[@]}"; do
  [[ "${SELECTED[idx]}" -ne 1 ]] && continue

  rel_path="${AGENT_PATHS[idx]}"
  file_name="$(basename "${rel_path}")"
  dest_file="${TARGET_ROOT}/${TARGET_AGENT_FILE}"
  tmp_template="$(new_tmp_file)"

  if [[ -n "${REMOTE_REPO}" ]]; then
    tmp_source="$(new_tmp_file)"
    if ! fetch_raw_from_github "${REMOTE_REPO}" "${GITHUB_REF}" "${REMOTE_PATH}/${rel_path}" "${tmp_source}" >/dev/null 2>&1; then
      echo "错误: 无法获取远程 agent 文件: ${REMOTE_PATH}/${rel_path}" >&2
      exit 1
    fi
    install_file_with_prompt "${dest_file}" "${tmp_source}" "~/.codex/${TARGET_AGENT_FILE}"
    install_file_with_prompt "${PROJECT_TARGET_FILE}" "${tmp_source}" "当前项目 AGENTS.md"
    if prepare_agents_v2_template_payload "${file_name}" "catalog_remote" "" "${REMOTE_REPO}" "${GITHUB_REF}" "${REMOTE_PATH}" "" "${tmp_template}"; then
      install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
    fi
  else
    src_file="${LOCAL_SOURCE_ROOT}/${rel_path}"
    if [[ ! -f "${src_file}" ]]; then
      echo "错误: 本地 agent 文件不存在: ${src_file}" >&2
      exit 1
    fi
    install_file_with_prompt "${dest_file}" "${src_file}" "~/.codex/${TARGET_AGENT_FILE}"
    install_file_with_prompt "${PROJECT_TARGET_FILE}" "${src_file}" "当前项目 AGENTS.md"
    if prepare_agents_v2_template_payload "${file_name}" "catalog_local" "" "" "" "" "${LOCAL_SOURCE_ROOT}" "${tmp_template}"; then
      install_agents_v2_template_for_project "${file_name}" "${tmp_template}"
    fi
  fi
done

echo "完成。"
