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

DEFAULT_GITHUB_REPO="404nffff/agents"
DEFAULT_GITHUB_REF="master"
DEFAULT_GITHUB_MCP_PATH="mcp"
TARGET_CONFIG="${HOME}/.codex/config.toml"
AUTO_YES="false"

SOURCE_MODE="github"
SOURCE_INPUT=""
GITHUB_REPO="${DEFAULT_GITHUB_REPO}"
GITHUB_REF="${DEFAULT_GITHUB_REF}"
GITHUB_MCP_PATH="${DEFAULT_GITHUB_MCP_PATH}"
SOURCE_LABEL=""
LOCAL_FALLBACK_SOURCE=""
CWD_FALLBACK_SOURCE_1="$(pwd)/mcp"
CWD_FALLBACK_SOURCE_2="$(pwd)/mcp.md"
if [[ -n "${REPO_ROOT}" ]]; then
  LOCAL_FALLBACK_SOURCE="${REPO_ROOT}/mcp"
fi

TMP_FETCH_DIR=""
TMP_SOURCE_FILE=""
TMP_STATUS_DIR=""
TMP_PARSE_DIR=""

declare -a SERVER_NAMES=()
declare -a SERVER_TITLES=()
declare -a SERVER_DESCS=()
declare -a SELECTED=()
declare -a UPSERT=()
declare -A SOURCE_BLOCK_BY_NAME=()

cleanup() {
  if [[ -n "${TMP_FETCH_DIR}" && -d "${TMP_FETCH_DIR}" ]]; then
    rm -rf "${TMP_FETCH_DIR}"
  fi
  if [[ -n "${TMP_SOURCE_FILE}" && -f "${TMP_SOURCE_FILE}" ]]; then
    rm -f "${TMP_SOURCE_FILE}"
  fi
  if [[ -n "${TMP_STATUS_DIR}" && -d "${TMP_STATUS_DIR}" ]]; then
    rm -rf "${TMP_STATUS_DIR}"
  fi
  if [[ -n "${TMP_PARSE_DIR}" && -d "${TMP_PARSE_DIR}" ]]; then
    rm -rf "${TMP_PARSE_DIR}"
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
  ./shell/codex/install_mcp.sh
  ./shell/codex/install_mcp.sh [--github <owner/repo|https://github.com/owner/repo>] [--ref <branch_or_tag>] [--mcp-path <path_in_repo>]
  ./shell/codex/install_mcp.sh [--source <path_or_url>] [--config <config_path>] [--yes]

说明:
  1) 默认从远程仓库读取 404nffff/agents@master:mcp 目录下的单服务 Markdown
  2) 读取 ~/.codex/config.toml 的 mcp_servers 相关配置并对比
  3) 交互勾选要安装/更新的 mcp server
  4) 若目标已存在且配置不同，会逐项询问是否覆盖
  5) 只修改 mcp_servers 相关段落，不改动 config.toml 其他内容

参数:
  --source   直接指定 MCP 来源（本地目录、单个 Markdown 文件或 http(s) URL）
  --github   指定 GitHub 仓库（owner/repo 或完整 URL）
  --ref      指定 GitHub 分支或标签，默认 master
  --mcp-path 指定仓库中的 MCP 目录或单个 Markdown 文件路径，默认 mcp
  --config   指定目标配置文件路径，默认 ~/.codex/config.toml
  --yes      自动同意覆盖（仅对“配置不同”的已存在 server 生效）
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
  echo "${repo}"
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

append_source_file_to_bundle() {
  local file="$1"
  if [[ -s "${TMP_SOURCE_FILE}" ]]; then
    printf "\n\n" >> "${TMP_SOURCE_FILE}"
  fi
  cat "${file}" >> "${TMP_SOURCE_FILE}"
  printf "\n" >> "${TMP_SOURCE_FILE}"
}

bundle_local_directory() {
  local source_dir="$1"
  local file count=0

  : > "${TMP_SOURCE_FILE}"
  while IFS= read -r file; do
    append_source_file_to_bundle "${file}"
    count=$((count + 1))
  done < <(find "${source_dir}" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'mcp.md' | sort)

  if (( count == 0 )); then
    echo "错误: MCP 目录未包含可解析的单服务 Markdown 文件: ${source_dir}" >&2
    exit 1
  fi
}

use_local_fallback() {
  local candidate=""
  for candidate in "${LOCAL_FALLBACK_SOURCE}" "${CWD_FALLBACK_SOURCE_1}" "${CWD_FALLBACK_SOURCE_2}"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
      bundle_local_directory "${candidate}"
      SOURCE_LABEL="本地回退目录 ${candidate}"
      return 0
    fi
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      cp "${candidate}" "${TMP_SOURCE_FILE}"
      SOURCE_LABEL="本地回退 ${candidate}"
      return 0
    fi
  done
  return 1
}

fetch_github_directory() {
  local repo="$1"
  local path="$2"
  local manifest_file download_url file tmp_file count=0

  manifest_file="$(mktemp)"
  TMP_FETCH_DIR="${TMP_FETCH_DIR:-$(mktemp -d)}"
  if ! curl_download_with_retry "https://api.github.com/repos/${repo}/contents/${path}?ref=${GITHUB_REF}" "${manifest_file}" 2 5 15; then
    rm -f "${manifest_file}"
    return 1
  fi
  : > "${TMP_SOURCE_FILE}"

  while IFS= read -r download_url; do
    [[ -z "${download_url}" ]] && continue
    file="${download_url%%\?*}"
    file="$(basename "${file}")"
    [[ "${file}" == "README.md" || "${file}" == "mcp.md" ]] && continue

    tmp_file="$(mktemp)"
    if ! curl_download_with_retry "${download_url}" "${tmp_file}" 2 5 15; then
      rm -f "${manifest_file}" "${tmp_file}"
      return 1
    fi
    append_source_file_to_bundle "${tmp_file}"
    rm -f "${tmp_file}"
    count=$((count + 1))
  done < <(
    sed -n 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.md\)".*/\1/p' "${manifest_file}" | sort
  )

  rm -f "${manifest_file}"

  if (( count == 0 )); then
    echo "错误: 远程 MCP 目录未包含可解析的单服务 Markdown 文件: ${repo}@${GITHUB_REF}:${path}" >&2
    return 1
  fi
}

fetch_source_file() {
  TMP_SOURCE_FILE="$(mktemp)"

  if [[ "${SOURCE_MODE}" == "source" ]]; then
    if [[ -d "${SOURCE_INPUT}" ]]; then
      bundle_local_directory "${SOURCE_INPUT}"
      SOURCE_LABEL="本地目录 ${SOURCE_INPUT}"
      return
    fi

    if [[ "${SOURCE_INPUT}" =~ ^https?:// ]]; then
      if ! command -v curl >/dev/null 2>&1; then
        echo "错误: 需要 curl 来拉取 URL 源。" >&2
        exit 1
      fi
      if ! curl_download_with_retry "${SOURCE_INPUT}" "${TMP_SOURCE_FILE}"; then
        echo "错误: 无法拉取 URL 源: ${SOURCE_INPUT}" >&2
        exit 1
      fi
      SOURCE_LABEL="URL ${SOURCE_INPUT}"
    else
      if [[ ! -f "${SOURCE_INPUT}" ]]; then
        echo "错误: 本地源文件不存在: ${SOURCE_INPUT}" >&2
        exit 1
      fi
      cp "${SOURCE_INPUT}" "${TMP_SOURCE_FILE}"
      SOURCE_LABEL="本地文件 ${SOURCE_INPUT}"
    fi
    return
  fi

  local repo raw_url bundle_path
  repo="$(normalize_github_repo "${GITHUB_REPO}")"

  echo "正在拉取远程 MCP 清单: ${repo}@${GITHUB_REF}:${GITHUB_MCP_PATH}"
  if ! command -v curl >/dev/null 2>&1; then
    if use_local_fallback; then
      echo "警告: 未安装 curl，已回退到本地文件: ${SOURCE_LABEL#本地回退 }" >&2
      return
    fi
    echo "错误: 未安装 curl，且未找到可用本地 MCP 目录或 Markdown 回退文件。" >&2
    echo "提示: 可使用 --source 指定本地目录或文件，例如: --source mcp" >&2
    exit 1
  fi

  if [[ "${GITHUB_MCP_PATH}" != *.md ]]; then
    bundle_path="${GITHUB_MCP_PATH%/}/mcp.md"
    raw_url="https://raw.githubusercontent.com/${repo}/${GITHUB_REF}/${bundle_path}"
    if curl_download_with_retry "${raw_url}" "${TMP_SOURCE_FILE}" 2 5 20; then
      SOURCE_LABEL="远程聚合文件 ${raw_url}"
      return
    fi

    if fetch_github_directory "${repo}" "${GITHUB_MCP_PATH}"; then
      SOURCE_LABEL="远程目录 ${repo}@${GITHUB_REF}:${GITHUB_MCP_PATH}"
      return
    fi

    raw_url="https://raw.githubusercontent.com/${repo}/${GITHUB_REF}/${bundle_path}"
  else
    raw_url="https://raw.githubusercontent.com/${repo}/${GITHUB_REF}/${GITHUB_MCP_PATH}"
  fi

  if curl_download_with_retry "${raw_url}" "${TMP_SOURCE_FILE}" 2 5 20; then
    SOURCE_LABEL="远程文件 ${raw_url}"
    return
  fi

  if use_local_fallback; then
    echo "警告: 远程拉取失败，已回退到本地文件: ${SOURCE_LABEL#本地回退 }" >&2
    return
  fi

  echo "错误: 无法拉取远程文件 ${raw_url}" >&2
  echo "提示: 可使用 --source 指定本地目录或文件，例如: --source mcp" >&2
  exit 1
}

discover_servers() {
  local row name title desc_encoded desc block

  TMP_PARSE_DIR="$(mktemp -d)"

  while IFS=$'\t' read -r name title desc_encoded block; do
    [[ -z "${name}" ]] && continue
    desc="$(printf '%s' "${desc_encoded}" | sed 's/\\n/\n/g')"

    SERVER_NAMES+=("${name}")
    SERVER_TITLES+=("${title}")
    SERVER_DESCS+=("${desc}")
    SELECTED+=(0)
    SOURCE_BLOCK_BY_NAME["${name}"]="${block}"
  done < <(
    awk -v out_dir="${TMP_PARSE_DIR}" '
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
    ' "${TMP_SOURCE_FILE}"
  )

  if [[ ${#SERVER_NAMES[@]} -eq 0 ]]; then
    echo "错误: 未在 MCP 来源中发现可安装的 mcp server" >&2
    exit 1
  fi
}

render_menu() {
  local i mark
  local first_line rest_lines line
  echo
  echo "可安装的 MCP servers（来源: ${SOURCE_LABEL}）"
  for i in "${!SERVER_NAMES[@]}"; do
    mark="[ ]"
    if [[ "${SELECTED[i]}" -eq 1 ]]; then
      mark="[x]"
    fi
    printf "%2d. %s %s : %s\n" "$((i + 1))" "${mark}" "${SERVER_NAMES[i]}" "${SERVER_TITLES[i]}"
    first_line="$(printf "%s\n" "${SERVER_DESCS[i]}" | sed -n '1p')"
    if [[ -n "${first_line}" ]]; then
      printf "    %s\n" "${first_line}"
    fi
    rest_lines="$(printf "%s\n" "${SERVER_DESCS[i]}" | sed -n '2,$p')"
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

toggle_by_indices() {
  local input="$1"
  local token idx matched

  input="${input//,/ }"
  for token in ${input}; do
    if [[ "${token}" =~ ^[0-9]+$ ]]; then
      if (( token >= 1 && token <= ${#SERVER_NAMES[@]} )); then
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
      matched="false"
      for idx in "${!SERVER_NAMES[@]}"; do
        if [[ "${token}" == "${SERVER_NAMES[idx]}" ]]; then
          if [[ "${SELECTED[idx]}" -eq 1 ]]; then
            SELECTED[idx]=0
          else
            SELECTED[idx]=1
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

preview_selected_items() {
  local i selected_count preview_file line src_block
  selected_count=0
  for i in "${!SELECTED[@]}"; do
    if [[ "${SELECTED[i]}" -eq 1 ]]; then
      ((selected_count += 1))
    fi
  done

  if (( selected_count == 0 )); then
    echo "当前未勾选任何 MCP server。"
    return
  fi

  preview_file="$(mktemp)"
  {
    echo "已选 MCP servers 预览（共 ${selected_count} 项）"
    echo "来源: ${SOURCE_LABEL}"
    echo
    for i in "${!SELECTED[@]}"; do
      if [[ "${SELECTED[i]}" -ne 1 ]]; then
        continue
      fi

      echo "[$((i + 1))] ${SERVER_NAMES[i]} - ${SERVER_TITLES[i]}"
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        echo "  ${line}"
      done < <(printf "%s\n" "${SERVER_DESCS[i]}")
      echo "  配置:"
      src_block="${SOURCE_BLOCK_BY_NAME[${SERVER_NAMES[i]}]:-}"
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

  rm -f "${preview_file}"
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
      v|V)
        preview_selected_items
        ;;
      d|D)
        selected_count=0
        for i in "${!SELECTED[@]}"; do
          if [[ "${SELECTED[i]}" -eq 1 ]]; then
            ((selected_count += 1))
          fi
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

extract_server_block_to_file() {
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

normalize_block_file() {
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

replace_server_block() {
  local target_file="$1"
  local server="$2"
  local source_block_file="$3"
  local tmp_out
  tmp_out="$(mktemp)"

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

  mv "${tmp_out}" "${target_file}"
}

append_server_block() {
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

collect_upsert_targets() {
  local -a selected_names=()
  local i name status
  local src_block dst_block src_norm dst_norm

  TMP_STATUS_DIR="$(mktemp -d)"

  for i in "${!SERVER_NAMES[@]}"; do
    if [[ "${SELECTED[i]}" -eq 1 ]]; then
      selected_names+=("${SERVER_NAMES[i]}")
    fi
  done

  if [[ ${#selected_names[@]} -eq 0 ]]; then
    echo "未选择任何 MCP server。"
    exit 0
  fi

  if [[ ! -f "${TARGET_CONFIG}" ]]; then
    mkdir -p "$(dirname "${TARGET_CONFIG}")"
    : > "${TARGET_CONFIG}"
  fi

  for name in "${selected_names[@]}"; do
    src_block="${SOURCE_BLOCK_BY_NAME[$name]:-}"
    dst_block="${TMP_STATUS_DIR}/dst-${name}.toml"
    src_norm="${TMP_STATUS_DIR}/src-${name}.norm"
    dst_norm="${TMP_STATUS_DIR}/dst-${name}.norm"

    if [[ -z "${src_block}" || ! -s "${src_block}" ]]; then
      echo "警告: MCP 来源中不存在 ${name} 的配置代码块，已跳过。"
      continue
    fi

    extract_server_block_to_file "${TARGET_CONFIG}" "${name}" "${dst_block}"

    if [[ ! -s "${dst_block}" ]]; then
      status="missing"
    else
      normalize_block_file "${src_block}" "${src_norm}"
      normalize_block_file "${dst_block}" "${dst_norm}"
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
        UPSERT+=("${name}")
        echo "将新增: ${name}"
        ;;
      different)
        if confirm "配置 ${name} 已存在且不同，是否覆盖?" "N"; then
          UPSERT+=("${name}")
          echo "将覆盖: ${name}"
        else
          echo "跳过覆盖: ${name}"
        fi
        ;;
    esac
  done
}

apply_merge() {
  local name src_block dst_block

  if [[ ${#UPSERT[@]} -eq 0 ]]; then
    echo
    echo "无需更新，未对 ${TARGET_CONFIG} 做任何修改。"
    return 0
  fi

  for name in "${UPSERT[@]}"; do
    src_block="${SOURCE_BLOCK_BY_NAME[$name]:-}"
    dst_block="${TMP_STATUS_DIR}/dst-apply-${name}.toml"

    if [[ -z "${src_block}" || ! -s "${src_block}" ]]; then
      echo "警告: 跳过 ${name}（MCP 配置代码块不存在）"
      continue
    fi

    extract_server_block_to_file "${TARGET_CONFIG}" "${name}" "${dst_block}"
    if [[ -s "${dst_block}" ]]; then
      replace_server_block "${TARGET_CONFIG}" "${name}" "${src_block}"
    else
      append_server_block "${TARGET_CONFIG}" "${src_block}"
    fi
  done
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --source 需要参数" >&2
          exit 1
        fi
        SOURCE_MODE="source"
        SOURCE_INPUT="${2:-}"
        shift 2
        ;;
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
        shift 2
        ;;
      --mcp-path)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --mcp-path 需要参数" >&2
          exit 1
        fi
        GITHUB_MCP_PATH="${2:-}"
        shift 2
        ;;
      --config)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "错误: --config 需要参数" >&2
          exit 1
        fi
        TARGET_CONFIG="${2:-}"
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

  trap cleanup EXIT
  trap handle_interrupt INT

  fetch_source_file
  discover_servers
  interactive_select
  collect_upsert_targets
  apply_merge

  echo
  echo "处理完成，目标文件: ${TARGET_CONFIG}"
}

main "$@"
