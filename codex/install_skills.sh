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

LOCAL_SKILLS_ROOT=""
if [[ -n "${SCRIPT_DIR}" ]]; then
  LOCAL_SKILLS_ROOT="${SCRIPT_DIR}/skills"
fi
TARGET_ROOT="${HOME}/.codex/skills"

DEFAULT_GITHUB_REPO="404nffff/agents"
DEFAULT_GITHUB_REF="master"
DEFAULT_GITHUB_SKILLS_PATH="codex/skills"

SOURCE_MODE=""
GITHUB_REPO=""
GITHUB_REF="${DEFAULT_GITHUB_REF}"
GITHUB_SKILLS_PATH="${DEFAULT_GITHUB_SKILLS_PATH}"
REF_SET="false"
SKILLS_PATH_SET="false"

SKILLS_ROOT=""
SOURCE_LABEL=""
TMP_FETCH_DIR=""

declare -a SKILL_DIRS=()
declare -a SKILL_NAMES=()
declare -a SKILL_DESCS=()
declare -a SELECTED=()

cleanup() {
  if [[ -n "${TMP_FETCH_DIR}" && -d "${TMP_FETCH_DIR}" ]]; then
    rm -rf "${TMP_FETCH_DIR}"
  fi
}

usage() {
  cat <<'EOF'
用法:
  ./install_skills.sh
  ./install_skills.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--skills-path <path_in_repo>]

说明:
  1) 扫描当前仓库的 skills 目录
  2) 若本地 skills 不存在，则默认从远程仓库读取（404nffff/agents@master:codex/skills）
  3) 可通过 --github / --ref / --skills-path 指定远程仓库来源
  4) 读取每个 skill 的 SKILL.md/skill.md 的 name 与 description
  5) 交互勾选需要安装的 skills
  6) 安装到 ~/.codex/skills/
  7) 若本地存在同名 skill，提示是否覆盖
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

resolve_skills_root() {
  local repo path

  if [[ "${SOURCE_MODE}" == "github" ]]; then
    if [[ -z "${GITHUB_REPO}" ]]; then
      GITHUB_REPO="${DEFAULT_GITHUB_REPO}"
    fi
    repo="$(normalize_github_repo "${GITHUB_REPO}")"
    path="${GITHUB_SKILLS_PATH}"
    fetch_remote_skills_root "${repo}" "${GITHUB_REF}" "${path}"
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
  fetch_remote_skills_root "${repo}" "${DEFAULT_GITHUB_REF}" "${path}"
}

fetch_remote_skills_root() {
  local repo="$1"
  local ref="$2"
  local path="$3"
  local clone_url
  local candidate

  if ! command -v git >/dev/null 2>&1; then
    echo "错误: 需要 git 来拉取远程仓库，请先安装 git。" >&2
    exit 1
  fi

  TMP_FETCH_DIR="$(mktemp -d)"
  clone_url="https://github.com/${repo}.git"
  if ! git clone --depth 1 --branch "${ref}" "${clone_url}" "${TMP_FETCH_DIR}" >/dev/null 2>&1; then
    echo "错误: 无法拉取远程仓库 ${repo} 分支 ${ref}" >&2
    exit 1
  fi

  candidate="${TMP_FETCH_DIR}/${path}"
  if [[ ! -d "${candidate}" ]]; then
    echo "错误: 远程仓库中不存在 skills 路径: ${path}" >&2
    echo "仓库: ${repo} 分支: ${ref}" >&2
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
  if [[ -z "${SKILLS_ROOT}" || ! -d "${SKILLS_ROOT}" ]]; then
    echo "错误: 未找到 skills 目录: ${SKILLS_ROOT}" >&2
    exit 1
  fi

  local dir skill_file name desc
  declare -A seen_names=()

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

  if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
    echo "错误: 未在 ${SKILLS_ROOT} 下找到可安装的 skill" >&2
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
  installed=0
  overwritten=0
  skipped=0

  echo
  echo "开始安装到: ${TARGET_ROOT}"
  for i in "${!SKILL_NAMES[@]}"; do
    if [[ "${SELECTED[i]}" -ne 1 ]]; then
      continue
    fi

    name="${SKILL_NAMES[i]}"
    src="${SKILL_DIRS[i]}"
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

        rm -rf "${preserve_dir}"
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
  echo "安装完成: 新增 ${installed} 个，覆盖 ${overwritten} 个，跳过 ${skipped} 个。"
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
  resolve_skills_root
  discover_skills
  interactive_select
  install_selected
}

main "$@"
