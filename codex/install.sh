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
  ./install.sh
  ./install.sh <mcp|agents|skills|all> [目标参数...]
  ./install.sh --target <mcp|agents|skills|all> [目标参数...]
  ./install.sh --mcp|--agents|--skills|--all [目标参数...]

说明:
  1) 不带参数时，进入交互菜单选择安装目标
  2) 各目标参数与原脚本基本兼容，详情见:
     - ./install.sh mcp --help
     - ./install.sh agents --help
     - ./install.sh skills --help
  3) all 模式会顺序执行: mcp -> agents -> skills
EOF
}

agents_usage() {
  cat <<'EOF'
用法:
  ./install.sh agents [--source <path_or_url>]
  ./install.sh agents [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--file <path_in_repo>]
  ./install.sh agents [--yes]

说明:
  --source   AGENTS.md 源地址，可为本地路径或 http(s) URL
  --github   GitHub 仓库地址（owner/repo 或完整 URL）
  --ref      GitHub 分支或标签，默认 main
  --file     仓库内文件路径，默认 AGENTS.md
  --yes      无交互模式，遇到可替换文件时自动替换
EOF
}

skills_usage() {
  cat <<'EOF'
用法:
  ./install.sh skills
  ./install.sh skills [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--skills-path <path_in_repo>]
  ./install.sh skills [--yes]

说明:
  1) 本地执行优先扫描本地 codex/skills 目录
  2) 网络请求执行默认从远程仓库读取（404nffff/agents@master:codex/skills）
  3) 可通过 --github / --ref / --skills-path 指定远程来源
  4) 交互勾选需要安装的 skills
  5) 安装到 ~/.codex/skills/
  6) 若本地存在同名 skill，提示是否覆盖（--yes 自动覆盖）
EOF
}

mcp_usage() {
  cat <<'EOF'
用法:
  ./install.sh mcp
  ./install.sh mcp [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--mcp-path <path_in_repo>]
  ./install.sh mcp [--source <path_or_url>] [--config <config_path>] [--yes]

说明:
  1) 默认来源会自动判断：本地执行优先本地文件，网络请求执行优先远程仓库（404nffff/agents@master:codex/mcp.md）
  2) 读取 ~/.codex/config.toml 的 mcp_servers 相关配置并对比
  3) 交互勾选要安装/更新的 mcp server
  4) 若目标已存在且配置不同，会逐项询问是否覆盖（--yes 自动覆盖）
  5) 仅修改 mcp_servers 段落，不改动 config.toml 其他内容
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
    curl -fsSL "${source}" -o "${out_file}"
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
  local raw_url

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 需要 curl 来拉取 GitHub 源。" >&2
    exit 1
  fi

  raw_url="https://raw.githubusercontent.com/${repo}/${ref}/${path}"
  curl -fsSL "${raw_url}" -o "${out_file}"
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
    echo "  2) AGENTS.md"
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
  local github_ref="main"
  local github_file="AGENTS.md"
  local default_source_file="${SCRIPT_DIR}/AGENTS.md"
  local target_user_file="${HOME}/.codex/AGENTS.md"
  local tmp_source current_dir_file repo

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
        github_file="${2:-}"
        shift 2
        ;;
      --yes)
        AUTO_YES="true"
        shift
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
    echo "错误: --github 不能为空" >&2
    return 1
  fi

  tmp_source="$(new_tmp_file)"

  if [[ "${source_mode}" == "source" ]]; then
    copy_local_or_url_to_file "${source_input}" "${tmp_source}"
  elif [[ "${source_mode}" == "github" ]]; then
    repo="$(normalize_github_repo "${github_repo}")"
    fetch_raw_from_github "${repo}" "${github_ref}" "${github_file}" "${tmp_source}"
  else
    if [[ "${IS_NETWORK_REQUEST_EXECUTION}" != "true" && -f "${default_source_file}" ]]; then
      cp "${default_source_file}" "${tmp_source}"
    elif fetch_raw_from_github "${DEFAULT_GITHUB_REPO}" "${DEFAULT_GITHUB_REF}" "codex/AGENTS.md" "${tmp_source}" 2>/dev/null; then
      :
    elif [[ -f "${default_source_file}" ]]; then
      cp "${default_source_file}" "${tmp_source}"
    else
      echo "错误: 默认远程源与本地源都不可用。" >&2
      echo "远程: https://raw.githubusercontent.com/${DEFAULT_GITHUB_REPO}/${DEFAULT_GITHUB_REF}/codex/AGENTS.md" >&2
      echo "本地: ${default_source_file}" >&2
      return 1
    fi
  fi

  if [[ ! -s "${tmp_source}" ]]; then
    echo "错误: 获取到的 AGENTS.md 为空" >&2
    return 1
  fi

  echo "准备安装 AGENTS.md ..."
  install_file_with_prompt "${target_user_file}" "${tmp_source}" "~/.codex/AGENTS.md"

  current_dir_file="$(pwd)/AGENTS.md"
  if confirm "是否在当前目录生成或更新 AGENTS.md?" "N"; then
    install_file_with_prompt "${current_dir_file}" "${tmp_source}" "当前目录 AGENTS.md"
  else
    echo "已跳过当前目录 AGENTS.md"
  fi

  echo "AGENTS 安装完成。"
}

install_skills_main() {
  local source_mode=""
  local github_repo=""
  local github_ref="${DEFAULT_GITHUB_REF}"
  local github_skills_path="codex/skills"
  local local_skills_root="${SCRIPT_DIR}/skills"
  local target_root="${HOME}/.codex/skills"
  local skills_root=""
  local source_label=""
  local tmp_fetch_dir=""
  local archive_url archive_file extract_root candidate repo path
  local dir skill_file name desc
  local cmd token idx tty_opened
  local installed overwritten skipped selected_count
  local src dest preserve_dir cfg rel
  local -a skill_dirs=()
  local -a skill_names=()
  local -a skill_descs=()
  local -a selected=()
  declare -A seen_names=()

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
      --yes)
        AUTO_YES="true"
        shift
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
  else
    repo="$(normalize_github_repo "${github_repo:-${DEFAULT_GITHUB_REPO}}")"
    path="${github_skills_path}"
    tmp_fetch_dir="$(new_tmp_dir)"

    if ! command -v curl >/dev/null 2>&1; then
      echo "错误: 需要 curl 来拉取远程仓库压缩包。" >&2
      return 1
    fi
    if ! command -v tar >/dev/null 2>&1; then
      echo "错误: 需要 tar 来解压远程仓库压缩包。" >&2
      return 1
    fi

    archive_url="https://codeload.github.com/${repo}/tar.gz/${github_ref}"
    archive_file="${tmp_fetch_dir}/repo.tar.gz"
    echo "正在使用 curl 拉取远程仓库压缩包: ${repo}@${github_ref}"
    if ! curl -fsSL "${archive_url}" -o "${archive_file}" >/dev/null 2>&1; then
      echo "错误: 无法下载远程仓库压缩包 ${archive_url}" >&2
      return 1
    fi

    if ! tar -xzf "${archive_file}" -C "${tmp_fetch_dir}" >/dev/null 2>&1; then
      echo "错误: 无法解压远程仓库压缩包 ${archive_file}" >&2
      return 1
    fi

    extract_root="$(find "${tmp_fetch_dir}" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
    if [[ -z "${extract_root}" ]]; then
      echo "错误: 压缩包解压后未找到仓库目录 ${repo}@${github_ref}" >&2
      return 1
    fi

    candidate="${extract_root}/${path}"
    if [[ ! -d "${candidate}" ]]; then
      echo "错误: 远程仓库中不存在 skills 路径: ${path}" >&2
      echo "仓库: ${repo} 分支: ${github_ref}" >&2
      return 1
    fi

    skills_root="${candidate}"
    source_label="远程仓库 ${repo}@${github_ref}:${path}"
  fi

  while IFS= read -r dir; do
    skill_file=""
    if [[ -f "${dir}/SKILL.md" ]]; then
      skill_file="${dir}/SKILL.md"
    elif [[ -f "${dir}/skill.md" ]]; then
      skill_file="${dir}/skill.md"
    else
      continue
    fi

    name="$(read_frontmatter_field "${skill_file}" "name")"
    desc="$(read_frontmatter_field "${skill_file}" "description")"

    [[ -z "${name}" ]] && name="$(basename "${dir}")"
    [[ -z "${desc}" ]] && desc="(无 description)"

    if [[ -n "${seen_names[${name}]+x}" ]]; then
      echo "警告: 发现重复 skill 名称 '${name}'，已忽略目录: ${dir}" >&2
      continue
    fi
    seen_names["${name}"]=1

    skill_dirs+=("${dir}")
    skill_names+=("${name}")
    skill_descs+=("${desc}")
    selected+=(0)
  done < <(find "${skills_root}" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ ${#skill_dirs[@]} -eq 0 ]]; then
    echo "错误: 未在 ${skills_root} 下找到可安装的 skill" >&2
    return 1
  fi

  tty_opened="false"
  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  while true; do
    echo
    echo "可安装的 skills（来源: ${source_label}）"
    for idx in "${!skill_names[@]}"; do
      if [[ "${selected[idx]}" -eq 1 ]]; then
        printf "%2d. [x] %s\n" "$((idx + 1))" "${skill_names[idx]}"
      else
        printf "%2d. [ ] %s\n" "$((idx + 1))" "${skill_names[idx]}"
      fi
      printf "    %s\n" "${skill_descs[idx]}"
    done
    echo
    echo "操作: 输入编号切换勾选（支持空格/逗号），a=全选，n=全不选，i=反选，d=开始安装，q=退出"

    if [[ "${tty_opened}" == "true" ]]; then
      printf "> " >&9
      IFS= read -r cmd <&9 || cmd="q"
    else
      read -r -p "> " cmd || cmd="q"
    fi
    case "${cmd}" in
      a|A)
        for idx in "${!selected[@]}"; do selected[idx]=1; done
        ;;
      n|N)
        for idx in "${!selected[@]}"; do selected[idx]=0; done
        ;;
      i|I)
        for idx in "${!selected[@]}"; do
          if [[ "${selected[idx]}" -eq 1 ]]; then
            selected[idx]=0
          else
            selected[idx]=1
          fi
        done
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
        cmd="${cmd//,/ }"
        for token in ${cmd}; do
          if [[ "${token}" =~ ^[0-9]+$ ]]; then
            if (( token >= 1 && token <= ${#skill_names[@]} )); then
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
            echo "无效输入: ${token}"
          fi
        done
        ;;
    esac
  done

  if [[ "${tty_opened}" == "true" ]]; then
    exec 9<&-
  fi

  mkdir -p "${target_root}"
  installed=0
  overwritten=0
  skipped=0

  echo
  echo "开始安装到: ${target_root}"
  for idx in "${!skill_names[@]}"; do
    [[ "${selected[idx]}" -ne 1 ]] && continue

    name="${skill_names[idx]}"
    src="${skill_dirs[idx]}"
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
        cp -R "${src}/." "${dest}/"

        while IFS= read -r cfg; do
          rel="${cfg#${preserve_dir}/}"
          mkdir -p "${dest}/$(dirname "${rel}")"
          cp "${cfg}" "${dest}/${rel}"
        done < <(find "${preserve_dir}" -type f -name 'config.env')

        echo "已覆盖同名 skill: ${name} -> ${dest}（保留本地 config.env）"
        ((overwritten += 1))
      else
        echo "跳过: ${name}（本地已存在: ${dest}）"
        ((skipped += 1))
      fi
      continue
    fi

    cp -R "${src}" "${dest}"
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
  local github_mcp_path="codex/mcp.md"
  local target_config="${HOME}/.codex/config.toml"
  local source_label=""
  local local_fallback_source="${SCRIPT_DIR}/mcp.md"
  local cwd_fallback_source_1="$(pwd)/codex/mcp.md"
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

  mcp_use_local_fallback() {
    local candidate=""
    for candidate in "${local_fallback_source}" "${cwd_fallback_source_1}" "${cwd_fallback_source_2}"; do
      if [[ -n "${candidate}" && -f "${candidate}" ]]; then
        cp "${candidate}" "${tmp_source_file}"
        source_label="本地回退 ${candidate}"
        return 0
      fi
    done
    return 1
  }

  mcp_fetch_source_file() {
    local repo raw_url
    tmp_source_file="$(new_tmp_file)"

    if [[ "${source_mode}" == "source" ]]; then
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
    raw_url="https://raw.githubusercontent.com/${repo}/${github_ref}/${github_mcp_path}"
    echo "正在拉取远程 MCP 清单: ${repo}@${github_ref}:${github_mcp_path}"

    if ! command -v curl >/dev/null 2>&1; then
      if mcp_use_local_fallback; then
        echo "警告: 未安装 curl，已回退到本地文件: ${source_label#本地回退 }" >&2
        return
      fi
      echo "错误: 未安装 curl，且未找到可用本地 mcp.md 回退文件。" >&2
      echo "提示: 可使用 --source 指定本地文件或 URL，例如: --source codex/mcp.md" >&2
      exit 1
    fi

    if command -v timeout >/dev/null 2>&1; then
      if timeout 30s curl -fsSL "${raw_url}" -o "${tmp_source_file}" >/dev/null 2>&1; then
        source_label="远程文件 ${raw_url}"
        return
      fi
    else
      if curl -fsSL "${raw_url}" -o "${tmp_source_file}" >/dev/null 2>&1; then
        source_label="远程文件 ${raw_url}"
        return
      fi
    fi

    if mcp_use_local_fallback; then
      echo "警告: 远程拉取失败，已回退到本地文件: ${source_label#本地回退 }" >&2
      return
    fi

    echo "错误: 无法拉取远程文件 ${raw_url}" >&2
    echo "提示: 可使用 --source 指定本地文件或 URL，例如: --source codex/mcp.md" >&2
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
            print "警告: mcp.md 条目缺少配置代码块，已跳过: " server > "/dev/stderr"
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
      echo "错误: 未在 mcp.md 中发现可安装的 mcp server" >&2
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
        echo "警告: mcp.md 中不存在 ${name} 的配置代码块，已跳过。"
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
        echo "警告: 跳过 ${name}（mcp.md 配置代码块不存在）"
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
      --yes)
        AUTO_YES="true"
        shift
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
  local -a yes_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        AUTO_YES="true"
        yes_args+=(--yes)
        shift
        ;;
      -h|--help)
        cat <<'EOF'
用法:
  ./install.sh all [--yes]

说明:
  all 模式会按顺序执行 mcp -> agents -> skills。
  为避免参数语义冲突，all 模式仅支持 --yes。
EOF
        return "${HELP_EXIT_CODE}"
        ;;
      *)
        echo "错误: all 模式仅支持 --yes 参数，收到: $1" >&2
        return 1
        ;;
    esac
  done

  echo ">>> 开始执行 MCP 安装"
  install_mcp_main "${yes_args[@]}"

  echo
  echo ">>> 开始执行 AGENTS 安装"
  install_agents_main "${yes_args[@]}"

  echo
  echo ">>> 开始执行 Skills 安装"
  install_skills_main "${yes_args[@]}"
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
