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

REPO_ROOT="${SCRIPT_DIR}"
if [[ -n "${SCRIPT_DIR}" && "${SCRIPT_DIR}" == */shell/codex ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
elif [[ -n "${SCRIPT_DIR}" && "${SCRIPT_DIR}" == */shell ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

LOCAL_SKILLS_ROOT=""
if [[ -n "${REPO_ROOT}" ]]; then
  LOCAL_SKILLS_ROOT="${REPO_ROOT}/skills"
fi
TARGET_ROOT="${HOME}/.codex/skills"

DEFAULT_GITHUB_REPO="404nffff/agents"
DEFAULT_GITHUB_REF="master"
DEFAULT_GITHUB_SKILLS_PATH="skills"
DB_QUERY_RELEASE_TAG="${DB_QUERY_RELEASE_TAG:-latest}"
DB_QUERY_RELEASE_REPO="${DB_QUERY_RELEASE_REPO:-}"
DB_QUERY_RELEASE_BASE_URL="${DB_QUERY_RELEASE_BASE_URL:-}"

SOURCE_MODE=""
GITHUB_REPO=""
GITHUB_REF="${DEFAULT_GITHUB_REF}"
GITHUB_SKILLS_PATH="${DEFAULT_GITHUB_SKILLS_PATH}"
REF_SET="false"
SKILLS_PATH_SET="false"

SKILLS_ROOT=""
SOURCE_LABEL=""
TMP_FETCH_DIR=""
REMOTE_REPO_RESOLVED=""
REMOTE_SKILLS_PATH_RESOLVED=""
REMOTE_SKILLS_ROOT=""

declare -a SKILL_DIRS=()
declare -a SKILL_NAMES=()
declare -a SKILL_DESCS=()
declare -a SELECTED=()

cleanup() {
  if [[ -n "${TMP_FETCH_DIR}" && -d "${TMP_FETCH_DIR}" ]]; then
    rm -rf "${TMP_FETCH_DIR}"
  fi
}

handle_interrupt() {
  echo
  echo "已取消安装（Ctrl+C）。"
  exit 130
}

usage() {
  cat <<'EOF'
用法:
  ./shell/codex/install_skills.sh
  ./shell/codex/install_skills.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--skills-path <path_in_repo>]

说明:
  1) 扫描当前仓库的 skills 目录
  2) 若本地 skills 不存在，则默认从远程仓库读取（404nffff/agents@master:skills）
  3) 可通过 --github / --ref / --skills-path 指定远程仓库来源
  4) 读取每个 skill 的 SKILL.md/skill.md 的 name 与 description
  5) 交互勾选需要安装的 skills
  6) 安装到 ~/.codex/skills/
  7) 若本地存在同名 skill，提示是否覆盖

db-query 发行二进制下载配置（可选环境变量）:
  DB_QUERY_RELEASE_BASE_URL  例如: https://github.com/owner/repo/releases/download/v0.1.0
  DB_QUERY_RELEASE_REPO      例如: owner/repo（默认 404nffff/agents）
  DB_QUERY_RELEASE_TAG       例如: v0.1.0（默认 latest）
EOF
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer=""
  local tty_opened="false"

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
  echo "${repo}"
}

curl_download_with_retry() {
  local url="$1"
  local out_file="$2"
  local max_attempts="${3:-2}"
  local connect_timeout="${4:-5}"
  local max_time="${5:-25}"
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

  if ! run_with_timeout_if_available 40 git clone --depth 1 --branch "${ref}" --filter=blob:none --sparse "${repo_url}" "${clone_dir}"; then
    return 1
  fi

  if ! (
    cd "${clone_dir}" &&
    run_with_timeout_if_available 20 git sparse-checkout set "${sparse_paths[@]}"
  ); then
    return 1
  fi

  if [[ ! -d "${clone_dir}/${root_path}" ]]; then
    return 1
  fi

  printf "%s\n" "${clone_dir}/${root_path}"
}

fetch_raw_from_github() {
  local repo="$1"
  local ref="$2"
  local path="$3"
  local out_file="$4"
  local raw_url="https://raw.githubusercontent.com/${repo}/${ref}/${path}"

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 需要 curl 来拉取 GitHub 源。" >&2
    exit 1
  fi

  if ! curl_download_with_retry "${raw_url}" "${out_file}" 2 5 15; then
    echo "错误: 无法拉取 GitHub 源: ${raw_url}" >&2
    exit 1
  fi
}

resolve_skills_root() {
  local repo path

  if [[ "${SOURCE_MODE}" == "github" ]]; then
    if [[ -z "${GITHUB_REPO}" ]]; then
      GITHUB_REPO="${DEFAULT_GITHUB_REPO}"
    fi
    repo="$(normalize_github_repo "${GITHUB_REPO}")"
    path="${GITHUB_SKILLS_PATH}"
    REMOTE_REPO_RESOLVED="${repo}"
    REMOTE_SKILLS_PATH_RESOLVED="${path}"
    SKILLS_ROOT=""
    SOURCE_LABEL="远程目录 ${repo}@${GITHUB_REF}:${path}（先读取 README 列表）"
    return
  fi

  if [[ -n "${LOCAL_SKILLS_ROOT}" && -d "${LOCAL_SKILLS_ROOT}" ]]; then
    SKILLS_ROOT="${LOCAL_SKILLS_ROOT}"
    SOURCE_LABEL="本地目录 ${SKILLS_ROOT}"
    return
  fi

  repo="${DEFAULT_GITHUB_REPO}"
  path="${DEFAULT_GITHUB_SKILLS_PATH}"
  echo "未检测到本地 skills 目录，默认使用远程仓库: ${repo}@${DEFAULT_GITHUB_REF}:${path}"
  SOURCE_MODE="github"
  GITHUB_REPO="${repo}"
  GITHUB_REF="${DEFAULT_GITHUB_REF}"
  GITHUB_SKILLS_PATH="${path}"
  REMOTE_REPO_RESOLVED="${repo}"
  REMOTE_SKILLS_PATH_RESOLVED="${path}"
  SKILLS_ROOT=""
  SOURCE_LABEL="远程目录 ${repo}@${GITHUB_REF}:${path}（先读取 README 列表）"
}

fetch_remote_skills_root() {
  local repo="$1"
  local ref="$2"
  local path="$3"
  local archive_url archive_file archive_extract_dir sparse_clone_dir
  local candidate extract_root

  TMP_FETCH_DIR="$(mktemp -d)"
  archive_extract_dir="${TMP_FETCH_DIR}/archive"
  sparse_clone_dir="${TMP_FETCH_DIR}/sparse-repo"
  mkdir -p "${archive_extract_dir}"

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 需要 curl 来拉取远程仓库压缩包。" >&2
    exit 1
  fi
  if ! command -v tar >/dev/null 2>&1; then
    echo "错误: 需要 tar 来解压远程仓库压缩包。" >&2
    exit 1
  fi

  archive_url="https://codeload.github.com/${repo}/tar.gz/${ref}"
  archive_file="${TMP_FETCH_DIR}/repo.tar.gz"
  echo "正在使用 curl 拉取远程仓库压缩包: ${repo}@${ref}"

  candidate=""
  if curl_download_with_retry "${archive_url}" "${archive_file}" 2 5 25; then
    if run_with_timeout_if_available 20 tar -xzf "${archive_file}" -C "${archive_extract_dir}"; then
      extract_root="$(find "${archive_extract_dir}" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
      if [[ -n "${extract_root}" ]]; then
        candidate="${extract_root}/${path}"
      fi
    fi
  fi

  if [[ -z "${candidate}" || ! -d "${candidate}" ]]; then
    echo "警告: 远程仓库压缩包下载较慢或失败，尝试按目录稀疏拉取: ${repo}@${ref}:${path}" >&2
    candidate="$(git_sparse_checkout_repo_path "${repo}" "${ref}" "${path}" "${sparse_clone_dir}" 2>/dev/null || true)"
  fi

  if [[ -z "${candidate}" || ! -d "${candidate}" ]]; then
    echo "错误: 无法获取远程 skills 目录 ${repo}@${ref}:${path}" >&2
    echo "已尝试: codeload 压缩包、git sparse-checkout" >&2
    exit 1
  fi

  SKILLS_ROOT="${candidate}"
  SOURCE_LABEL="远程仓库 ${repo}@${ref}:${path}"
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
  echo "${value}"
}

discover_skills() {
  local dir skill_file name desc rel_path tmp_catalog_file
  declare -A seen_names=()

  if [[ "${SOURCE_MODE}" == "github" ]]; then
    TMP_FETCH_DIR="${TMP_FETCH_DIR:-$(mktemp -d)}"
    tmp_catalog_file="${TMP_FETCH_DIR}/skills-readme.md"
    fetch_raw_from_github "${REMOTE_REPO_RESOLVED}" "${GITHUB_REF}" "${REMOTE_SKILLS_PATH_RESOLVED}/README.md" "${tmp_catalog_file}"

    while IFS=$'\t' read -r name rel_path desc; do
      [[ -z "${name}" || -z "${rel_path}" ]] && continue
      [[ -z "${desc}" ]] && desc="(无 description)"

      if [[ -n "${seen_names[${name}]+x}" ]]; then
        echo "警告: 发现重复 skill 名称 '${name}'，已忽略目录: ${rel_path}" >&2
        continue
      fi
      seen_names["${name}"]=1

      SKILL_DIRS+=("${rel_path}")
      SKILL_NAMES+=("${name}")
      SKILL_DESCS+=("${desc}")
      SELECTED+=(0)
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
          split(line, raw_fields, /\|/)

          field_count = 0
          for (i = 1; i <= length(raw_fields); i++) {
            field = trim(raw_fields[i])
            if (field == "") {
              continue
            }
            field_count++
            fields[field_count] = field
          }

          if (field_count < 3) {
            next
          }

          name = fields[1]
          rel_path = fields[2]
          desc = fields[3]

          if (tolower(name) == "name" && tolower(rel_path) == "directory") {
            next
          }
          if (name ~ /^-+$/ && rel_path ~ /^-+$/) {
            next
          }

          gsub(/`/, "", rel_path)
          print name "\t" rel_path "\t" desc
        }
      ' "${tmp_catalog_file}"
    )
  else
    if [[ -z "${SKILLS_ROOT}" || ! -d "${SKILLS_ROOT}" ]]; then
      echo "错误: 未找到 skills 目录: ${SKILLS_ROOT}" >&2
      exit 1
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

      if [[ -z "${name}" ]]; then
        name="$(basename "${dir}")"
      fi
      if [[ -z "${desc}" ]]; then
        desc="(无 description)"
      fi

      if [[ -n "${seen_names[${name}]+x}" ]]; then
        echo "警告: 发现重复 skill 名称 '${name}'，已忽略目录: ${dir}" >&2
        continue
      fi
      seen_names["${name}"]=1

      SKILL_DIRS+=("${dir}")
      SKILL_NAMES+=("${name}")
      SKILL_DESCS+=("${desc}")
      SELECTED+=(0)
    done < <(find "${SKILLS_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
    echo "错误: 未找到可安装的 skill" >&2
    exit 1
  fi
}

render_menu() {
  local i mark
  echo
  echo "可安装的 skills（来源: ${SOURCE_LABEL}）"
  for i in "${!SKILL_NAMES[@]}"; do
    mark="[ ]"
    if [[ "${SELECTED[i]}" -eq 1 ]]; then
      mark="[x]"
    fi
    printf "%2d. %s %s\n" "$((i + 1))" "${mark}" "${SKILL_NAMES[i]}"
    printf "    %s\n" "${SKILL_DESCS[i]}"
  done
  echo
  echo "操作: 输入编号切换勾选（支持空格/逗号），a=全选，n=全不选，i=反选，d=开始安装，q=退出"
}

toggle_by_indices() {
  local input="$1"
  local token idx

  input="${input//,/ }"
  for token in ${input}; do
    if [[ "${token}" =~ ^[0-9]+$ ]]; then
      if (( token >= 1 && token <= ${#SKILL_NAMES[@]} )); then
        idx=$((token - 1))
        if [[ "${SELECTED[idx]}" -eq 1 ]]; then
          SELECTED[idx]=0
        else
          SELECTED[idx]=1
        fi
      else
        echo "无效编号: ${token}"
      fi
    else
      echo "无效输入: ${token}"
    fi
  done
}

interactive_select() {
  local cmd i selected_count tty_opened done_select
  tty_opened="false"
  done_select="false"

  if [[ -t 1 && -r /dev/tty ]] && exec 9<>/dev/tty 2>/dev/null; then
    tty_opened="true"
  fi

  while true; do
    render_menu

    if [[ "${tty_opened}" == "true" ]]; then
      printf "> " >&9
      IFS= read -r cmd <&9 || cmd="q"
    else
      read -r -p "> " cmd || cmd="q"
    fi

    case "${cmd}" in
      a|A)
        for i in "${!SELECTED[@]}"; do
          SELECTED[i]=1
        done
        ;;
      n|N)
        for i in "${!SELECTED[@]}"; do
          SELECTED[i]=0
        done
        ;;
      i|I)
        for i in "${!SELECTED[@]}"; do
          if [[ "${SELECTED[i]}" -eq 1 ]]; then
            SELECTED[i]=0
          else
            SELECTED[i]=1
          fi
        done
        ;;
      d|D)
        selected_count=0
        for i in "${!SELECTED[@]}"; do
          if [[ "${SELECTED[i]}" -eq 1 ]]; then
            ((selected_count += 1))
          fi
        done
        if (( selected_count == 0 )); then
          echo "未勾选任何 skill，请先勾选。"
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
        toggle_by_indices "${cmd}"
        ;;
    esac
  done

  if [[ "${tty_opened}" == "true" ]]; then
    exec 9<&-
  fi

  if [[ "${done_select}" == "true" ]]; then
    return 0
  fi

  exit 0
}

install_selected() {
  mkdir -p "${TARGET_ROOT}"

  local i name src dest installed overwritten skipped
  local -a selected_sparse_paths=()
  installed=0
  overwritten=0
  skipped=0

  if [[ "${SOURCE_MODE}" == "github" ]]; then
    for i in "${!SKILL_NAMES[@]}"; do
      [[ "${SELECTED[i]}" -ne 1 ]] && continue
      selected_sparse_paths+=("${REMOTE_SKILLS_PATH_RESOLVED}/${SKILL_DIRS[i]}")
    done

    echo "已选择 ${#selected_sparse_paths[@]} 个 skill，开始按目录拉取远程仓库: ${REMOTE_REPO_RESOLVED}@${GITHUB_REF}"
    REMOTE_SKILLS_ROOT="$(git_sparse_checkout_repo_path "${REMOTE_REPO_RESOLVED}" "${GITHUB_REF}" "${REMOTE_SKILLS_PATH_RESOLVED}" "${TMP_FETCH_DIR}/sparse-selected" "${selected_sparse_paths[@]}" 2>/dev/null || true)"
    if [[ -z "${REMOTE_SKILLS_ROOT}" || ! -d "${REMOTE_SKILLS_ROOT}" ]]; then
      echo "错误: 无法按目录拉取远程 skills ${REMOTE_REPO_RESOLVED}@${GITHUB_REF}:${REMOTE_SKILLS_PATH_RESOLVED}" >&2
      exit 1
    fi
  fi

  echo
  echo "开始安装到: ${TARGET_ROOT}"
  for i in "${!SKILL_NAMES[@]}"; do
    if [[ "${SELECTED[i]}" -ne 1 ]]; then
      continue
    fi

    name="${SKILL_NAMES[i]}"
    if [[ -n "${REMOTE_SKILLS_ROOT}" ]]; then
      src="${REMOTE_SKILLS_ROOT}/${SKILL_DIRS[i]}"
    else
      src="${SKILL_DIRS[i]}"
    fi
    dest="${TARGET_ROOT}/${name}"

    if [[ -e "${dest}" ]]; then
      if confirm "技能 ${name} 已存在，是否覆盖?" "N"; then
        # 覆盖前保留本地 config.env，避免更新时冲掉本地配置。
        local preserve_dir preserved_count cfg rel
        preserve_dir="$(mktemp -d)"
        preserved_count=0
        while IFS= read -r cfg; do
          rel="${cfg#${dest}/}"
          mkdir -p "${preserve_dir}/$(dirname "${rel}")"
          cp "${cfg}" "${preserve_dir}/${rel}"
          ((preserved_count += 1))
        done < <(find "${dest}" -type f -name 'config.env')

        mkdir -p "${dest}"
        cp -R "${src}/." "${dest}/"

        if (( preserved_count > 0 )); then
          while IFS= read -r cfg; do
            rel="${cfg#${preserve_dir}/}"
            mkdir -p "${dest}/$(dirname "${rel}")"
            cp "${cfg}" "${dest}/${rel}"
          done < <(find "${preserve_dir}" -type f -name 'config.env')
          echo "已覆盖同名文件: ${name} -> ${dest}（保留旧目录其他文件，保留本地 config.env）"
        else
          echo "已覆盖同名文件: ${name} -> ${dest}（保留旧目录其他文件）"
        fi

        if [[ "${name}" == "db-query" ]]; then
          if ! sync_db_query_release_bins "${dest}"; then
            exit 1
          fi
        fi

        rm -rf "${preserve_dir}"
        ((overwritten += 1))
      else
        echo "跳过: ${name}（本地已存在: ${dest}）"
        if [[ "${name}" == "db-query" ]]; then
          if ! sync_db_query_release_bins "${dest}"; then
            exit 1
          fi
          echo "已同步 db-query release 二进制（未覆盖其他文件）: ${dest}/bin"
        fi
        ((skipped += 1))
      fi
      continue
    fi

    cp -R "${src}" "${dest}"

    if [[ "${name}" == "db-query" ]]; then
      if ! sync_db_query_release_bins "${dest}"; then
        exit 1
      fi
    fi

    echo "已安装: ${name} -> ${dest}"
    ((installed += 1))
  done

  echo
  echo "安装完成: 新增 ${installed} 个，覆盖 ${overwritten} 个，跳过 ${skipped} 个。"
}

resolve_db_query_release_base_url() {
  if [[ -n "${DB_QUERY_RELEASE_BASE_URL}" ]]; then
    echo "${DB_QUERY_RELEASE_BASE_URL}"
    return
  fi

  local repo
  if [[ -n "${DB_QUERY_RELEASE_REPO}" ]]; then
    repo="$(normalize_github_repo "${DB_QUERY_RELEASE_REPO}")"
  elif [[ "${SOURCE_MODE}" == "github" && -n "${GITHUB_REPO}" ]]; then
    repo="$(normalize_github_repo "${GITHUB_REPO}")"
  else
    repo="${DEFAULT_GITHUB_REPO}"
  fi

  if [[ "${DB_QUERY_RELEASE_TAG}" == "latest" ]]; then
    echo "https://github.com/${repo}/releases/latest/download"
  else
    echo "https://github.com/${repo}/releases/download/${DB_QUERY_RELEASE_TAG}"
  fi
}

download_db_query_release_bins() {
  local dest="$1"
  local base_url url tmp_file asset
  base_url="$(resolve_db_query_release_base_url)"

  if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 下载 db-query release 二进制需要 curl。" >&2
    return 1
  fi

  mkdir -p "${dest}/bin"
  for asset in "db-query-linux-amd64" "db-query-windows-amd64.exe"; do
    url="${base_url}/${asset}"
    tmp_file="${dest}/bin/.tmp-${asset}"
    if ! curl -fsSL "${url}" -o "${tmp_file}" >/dev/null 2>&1; then
      rm -f "${tmp_file}"
      echo "错误: 下载 db-query release 文件失败: ${url}" >&2
      echo "可通过 DB_QUERY_RELEASE_BASE_URL 覆盖地址。" >&2
      return 1
    fi
    mv "${tmp_file}" "${dest}/bin/${asset}"
  done

  chmod +x "${dest}/bin/db-query-linux-amd64" 2>/dev/null || true
  echo "已同步 db-query release 二进制: ${base_url}"
  return 0
}

sync_db_query_release_bins() {
  local dest="$1"

  if download_db_query_release_bins "${dest}"; then
    return 0
  fi

  if [[ -s "${dest}/bin/db-query-linux-amd64" && -s "${dest}/bin/db-query-windows-amd64.exe" ]]; then
    echo "警告: release 下载失败，已保留本地现有 db-query 二进制。"
    return 0
  fi

  echo "错误: db-query 缺少可用二进制，请检查 release 地址后重试。" >&2
  return 1
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --github)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --github 需要参数" >&2
          exit 1
        fi
        SOURCE_MODE="github"
        GITHUB_REPO="${2:-}"
        shift 2
        ;;
      --ref)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --ref 需要参数" >&2
          exit 1
        fi
        GITHUB_REF="${2:-}"
        REF_SET="true"
        shift 2
        ;;
      --skills-path)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --skills-path 需要参数" >&2
          exit 1
        fi
        GITHUB_SKILLS_PATH="${2:-}"
        SKILLS_PATH_SET="true"
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

  if [[ "${REF_SET}" == "true" || "${SKILLS_PATH_SET}" == "true" ]]; then
    SOURCE_MODE="github"
  fi

  if [[ "${SOURCE_MODE}" == "github" && -z "${GITHUB_REPO}" ]]; then
    GITHUB_REPO="${DEFAULT_GITHUB_REPO}"
  fi

  if [[ "${SOURCE_MODE}" == "github" ]]; then
    echo "使用远程仓库来源: $(normalize_github_repo "${GITHUB_REPO}")@${GITHUB_REF}:${GITHUB_SKILLS_PATH}"
  fi

  trap cleanup EXIT
  trap handle_interrupt INT
  resolve_skills_root
  discover_skills
  interactive_select
  install_selected
}

main "$@"
