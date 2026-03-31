#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  git_merge.sh prepare [options]
  git_merge.sh apply [options]

prepare options:
  --develop-dir <path>   Develop repository directory (required)
  --master-dir <path>    Master target directory (required)
  --source <branch>      Source branch in develop repo (default: develop)
  --target <branch>      Base branch in develop repo (default: master)
  --author <pattern>     Author filter (required)
  --since <date>         Since date, e.g. "2026-03-01"
  --until <date>         Until date
  --max-count <N>        Maximum commit count
  --output <path>        Report file path (default: git-merge.md)
  --plan-file <path>     Plan file path (default: .git-merge-plan.env)

apply options:
  --plan-file <path>     Plan file path (default: .git-merge-plan.env)
  --confirm yes          Required confirmation
EOF
}

escape_single_quote() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

require_directory() {
  local dir="$1"
  local label="$2"
  [[ -n "$dir" ]] || die "$label 不能为空。"
  [[ -d "$dir" ]] || die "$label 不存在或不是目录: $dir"
}

require_git_repo() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "develop_dir 不是 Git 仓库: $repo_dir"
}

require_local_branch() {
  local repo_dir="$1"
  local branch="$2"
  git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch" || die "develop_dir 本地分支不存在: $branch"
}

to_abs_dir() {
  local dir="$1"
  (
    cd "$dir" 2>/dev/null || exit 1
    pwd -P
  )
}

ensure_parent_dir() {
  local path="$1"
  local parent
  parent="$(dirname "$path")"
  mkdir -p "$parent"
}

write_list_file() {
  local path="$1"
  shift
  {
    for item in "$@"; do
      printf '%s\n' "$item"
    done
  } >"$path"
}

write_plan_file() {
  local plan_file="$1"
  local develop_dir="$2"
  local master_dir="$3"
  local source_branch="$4"
  local target_branch="$5"
  local author_filter="$6"
  local since_value="$7"
  local until_value="$8"
  local max_count_value="$9"
  local report_file="${10}"
  local added_list_file="${11}"
  local modified_list_file="${12}"
  local deleted_list_file="${13}"
  local commit_list="${14}"

  cat >"$plan_file" <<EOF
DEVELOP_DIR='$(escape_single_quote "$develop_dir")'
MASTER_DIR='$(escape_single_quote "$master_dir")'
SOURCE_BRANCH='$(escape_single_quote "$source_branch")'
TARGET_BRANCH='$(escape_single_quote "$target_branch")'
AUTHOR_FILTER='$(escape_single_quote "$author_filter")'
SINCE='$(escape_single_quote "$since_value")'
UNTIL='$(escape_single_quote "$until_value")'
MAX_COUNT='$(escape_single_quote "$max_count_value")'
REPORT_FILE='$(escape_single_quote "$report_file")'
ADDED_LIST_FILE='$(escape_single_quote "$added_list_file")'
MODIFIED_LIST_FILE='$(escape_single_quote "$modified_list_file")'
DELETED_LIST_FILE='$(escape_single_quote "$deleted_list_file")'
COMMITS='$(escape_single_quote "$commit_list")'
GENERATED_AT='$(date -u '+%Y-%m-%dT%H:%M:%SZ')'
EOF
}

git_path_exists() {
  local repo_dir="$1"
  local ref_name="$2"
  local rel_path="$3"
  git -C "$repo_dir" cat-file -e "${ref_name}:${rel_path}" >/dev/null 2>&1
}

git_export_path_to_file() {
  local repo_dir="$1"
  local ref_name="$2"
  local rel_path="$3"
  local output_file="$4"
  local object_type
  local object_mode

  object_type="$(git -C "$repo_dir" cat-file -t "${ref_name}:${rel_path}" 2>/dev/null || true)"
  [[ "$object_type" == "blob" ]] || die "仅支持文件路径导出，当前不是文件: ${ref_name}:${rel_path}"

  git -C "$repo_dir" show "${ref_name}:${rel_path}" >"$output_file"

  object_mode="$(git -C "$repo_dir" ls-tree "$ref_name" -- "$rel_path" | awk 'NR==1{print $1}')"
  if [[ "$object_mode" == "100755" ]]; then
    chmod 755 "$output_file"
  else
    chmod 644 "$output_file"
  fi
}

render_commit_block() {
  local repo_dir="$1"
  local hash="$2"
  local author_name="$3"
  local author_email="$4"
  local author_date="$5"
  local subject="$6"
  local index="$7"

  {
    printf '## %s. %s\n\n' "$index" "$subject"
    printf -- '- Commit: `%s`\n' "$hash"
    printf -- '- Author: `%s <%s>`\n' "$author_name" "$author_email"
    printf -- '- Date: `%s`\n' "$author_date"
    printf -- '- 修改文件:\n'
  }

  local files
  files="$(git -C "$repo_dir" show --pretty='' --name-only "$hash" | sed '/^$/d')"
  if [[ -n "$files" ]]; then
    while IFS= read -r file; do
      printf '  - `%s`\n' "$file"
    done <<<"$files"
  else
    printf -- '  - 无\n'
  fi

  printf -- '- 文件增删统计:\n'
  local numstat
  numstat="$(git -C "$repo_dir" show --numstat --format='' "$hash")"
  if [[ -n "$numstat" ]]; then
    while IFS=$'\t' read -r add del file; do
      [[ -z "${file:-}" ]] && continue
      printf '  - `%s`: +%s / -%s\n' "$file" "$add" "$del"
    done <<<"$numstat"
  else
    printf -- '  - 无\n'
  fi

  printf -- '- 关键改动片段（最多 120 行）:\n\n'
  printf '```diff\n'
  git -C "$repo_dir" show --no-color --format='' --unified=1 "$hash" | awk 'NR<=120{print} NR==121{print "...(truncated)"}'
  printf '```\n\n'
}

collect_commit_touched_paths() {
  local repo_dir="$1"
  local hash="$2"
  local -n touched_map_ref="$3"

  while IFS=$'\t' read -r status path_a path_b; do
    [[ -z "${status:-}" ]] && continue
    case "$status" in
      R*|C*)
        [[ -n "${path_a:-}" ]] && touched_map_ref["$path_a"]=1
        [[ -n "${path_b:-}" ]] && touched_map_ref["$path_b"]=1
        ;;
      *)
        [[ -n "${path_a:-}" ]] && touched_map_ref["$path_a"]=1
        ;;
    esac
  done < <(git -C "$repo_dir" show --name-status --find-renames --format='' "$hash")
}

sort_unique_array() {
  local -n in_ref="$1"
  local -n out_ref="$2"

  if [[ ${#in_ref[@]} -eq 0 ]]; then
    out_ref=()
    return 0
  fi

  mapfile -t out_ref < <(printf '%s\n' "${in_ref[@]}" | LC_ALL=C sort -u)
}

do_prepare() {
  local develop_dir=""
  local master_dir=""
  local source_branch="develop"
  local target_branch="master"
  local author_filter=""
  local since_value=""
  local until_value=""
  local max_count_value=""
  local output_file="git-merge.md"
  local plan_file=".git-merge-plan.env"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --develop-dir)
        develop_dir="$2"
        shift 2
        ;;
      --master-dir)
        master_dir="$2"
        shift 2
        ;;
      --source)
        source_branch="$2"
        shift 2
        ;;
      --target)
        target_branch="$2"
        shift 2
        ;;
      --author)
        author_filter="$2"
        shift 2
        ;;
      --since)
        since_value="$2"
        shift 2
        ;;
      --until)
        until_value="$2"
        shift 2
        ;;
      --max-count)
        max_count_value="$2"
        shift 2
        ;;
      --output)
        output_file="$2"
        shift 2
        ;;
      --plan-file)
        plan_file="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done

  require_directory "$develop_dir" "--develop-dir"
  require_directory "$master_dir" "--master-dir"

  develop_dir="$(to_abs_dir "$develop_dir")" || die "无法解析 --develop-dir 的绝对路径: $develop_dir"
  master_dir="$(to_abs_dir "$master_dir")" || die "无法解析 --master-dir 的绝对路径: $master_dir"

  require_git_repo "$develop_dir"
  require_local_branch "$develop_dir" "$source_branch"
  require_local_branch "$develop_dir" "$target_branch"

  [[ -n "$author_filter" ]] || die "prepare 必须指定 --author。"
  if [[ -z "$since_value" && -z "$max_count_value" ]]; then
    die "prepare 至少需要指定 --since 或 --max-count，用于限定提交历史。"
  fi

  local added_list_file="${plan_file}.added"
  local modified_list_file="${plan_file}.modified"
  local deleted_list_file="${plan_file}.deleted"

  ensure_parent_dir "$output_file"
  ensure_parent_dir "$plan_file"
  ensure_parent_dir "$added_list_file"
  ensure_parent_dir "$modified_list_file"
  ensure_parent_dir "$deleted_list_file"

  local range_spec="${target_branch}..${source_branch}"
  local -a log_cmd=(
    git -C "$develop_dir" log "$range_spec"
    "--author=$author_filter"
    --reverse
    --date=iso-strict
    "--pretty=format:%H%x1f%an%x1f%ae%x1f%ad%x1f%s"
  )

  [[ -n "$since_value" ]] && log_cmd+=("--since=$since_value")
  [[ -n "$until_value" ]] && log_cmd+=("--until=$until_value")
  [[ -n "$max_count_value" ]] && log_cmd+=("--max-count=$max_count_value")

  local raw_lines
  raw_lines="$("${log_cmd[@]}")"

  local -a commit_lines=()
  if [[ -n "$raw_lines" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && commit_lines+=("$line")
    done <<<"$raw_lines"
  fi

  {
    printf '# Git Merge Report\n\n'
    printf -- '- 生成时间: `%s`\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf -- '- develop_dir: `%s`\n' "$develop_dir"
    printf -- '- master_dir: `%s`\n' "$master_dir"
    printf -- '- source 分支: `%s`\n' "$source_branch"
    printf -- '- target 分支: `%s`\n' "$target_branch"
    printf -- '- 提交人筛选: `%s`\n' "$author_filter"
    [[ -n "$since_value" ]] && printf -- '- Since: `%s`\n' "$since_value"
    [[ -n "$until_value" ]] && printf -- '- Until: `%s`\n' "$until_value"
    [[ -n "$max_count_value" ]] && printf -- '- Max Count: `%s`\n' "$max_count_value"
    printf -- '- 待处理提交数: `%s`\n\n' "${#commit_lines[@]}"
  } >"$output_file"

  if [[ ${#commit_lines[@]} -eq 0 ]]; then
    {
      printf '## 结果\n\n'
      printf '未找到符合条件的提交。\n'
    } >>"$output_file"
    write_list_file "$added_list_file"
    write_list_file "$modified_list_file"
    write_list_file "$deleted_list_file"
    write_plan_file "$plan_file" "$develop_dir" "$master_dir" "$source_branch" "$target_branch" "$author_filter" "$since_value" "$until_value" "$max_count_value" "$output_file" "$added_list_file" "$modified_list_file" "$deleted_list_file" ""
    log "已生成报告: $output_file"
    log "已生成计划: $plan_file"
    log "未发现可合并改动。"
    exit 0
  fi

  declare -A touched_path_map=()
  local -a commit_hashes=()
  local idx=1
  for line in "${commit_lines[@]}"; do
    IFS=$'\x1f' read -r hash author_name author_email author_date subject <<<"$line"
    commit_hashes+=("$hash")
    render_commit_block "$develop_dir" "$hash" "$author_name" "$author_email" "$author_date" "$subject" "$idx" >>"$output_file"
    collect_commit_touched_paths "$develop_dir" "$hash" touched_path_map
    idx=$((idx + 1))
  done

  local -a touched_paths=()
  local rel_path
  for rel_path in "${!touched_path_map[@]}"; do
    touched_paths+=("$rel_path")
  done

  local -a sorted_touched_paths=()
  sort_unique_array touched_paths sorted_touched_paths

  local -a added_files=()
  local -a modified_files=()
  local -a deleted_files=()
  for rel_path in "${sorted_touched_paths[@]}"; do
    if git_path_exists "$develop_dir" "$source_branch" "$rel_path"; then
      if [[ -e "$master_dir/$rel_path" ]]; then
        modified_files+=("$rel_path")
      else
        added_files+=("$rel_path")
      fi
    else
      if [[ -e "$master_dir/$rel_path" ]]; then
        deleted_files+=("$rel_path")
      fi
    fi
  done

  write_list_file "$added_list_file" "${added_files[@]}"
  write_list_file "$modified_list_file" "${modified_files[@]}"
  write_list_file "$deleted_list_file" "${deleted_files[@]}"

  local commit_list
  commit_list="$(printf '%s ' "${commit_hashes[@]}" | sed 's/[[:space:]]*$//')"
  write_plan_file "$plan_file" "$develop_dir" "$master_dir" "$source_branch" "$target_branch" "$author_filter" "$since_value" "$until_value" "$max_count_value" "$output_file" "$added_list_file" "$modified_list_file" "$deleted_list_file" "$commit_list"

  {
    printf '## 修改计划\n\n'
    printf -- '- 新增文件数: `%s`\n' "${#added_files[@]}"
    printf -- '- 修改文件数: `%s`\n' "${#modified_files[@]}"
    printf -- '- 删除文件数: `%s`\n\n' "${#deleted_files[@]}"

    printf '### 新增文件（复制到 master_dir）\n\n'
    if [[ ${#added_files[@]} -eq 0 ]]; then
      printf -- '- 无\n'
    else
      for rel_path in "${added_files[@]}"; do
        printf -- '- `%s`\n' "$rel_path"
      done
    fi

    printf '\n### 修改文件（覆盖到 master_dir）\n\n'
    if [[ ${#modified_files[@]} -eq 0 ]]; then
      printf -- '- 无\n'
    else
      for rel_path in "${modified_files[@]}"; do
        printf -- '- `%s`\n' "$rel_path"
      done
    fi

    printf '\n### 删除文件（从 master_dir 删除）\n\n'
    if [[ ${#deleted_files[@]} -eq 0 ]]; then
      printf -- '- 无\n'
    else
      for rel_path in "${deleted_files[@]}"; do
        printf -- '- `%s`\n' "$rel_path"
      done
    fi
  } >>"$output_file"

  log "已生成报告: $output_file"
  log "已生成计划: $plan_file"
  log "请先人工确认修改计划，再执行 apply。"
}

apply_copy_list() {
  local list_file="$1"
  local develop_dir="$2"
  local source_branch="$3"
  local master_dir="$4"
  local action_label="$5"
  local counter=0
  local rel_path

  while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    git_path_exists "$develop_dir" "$source_branch" "$rel_path" || die "计划中的源文件不存在: ${source_branch}:${rel_path}"
    local target_path="$master_dir/$rel_path"
    mkdir -p "$(dirname "$target_path")"
    git_export_path_to_file "$develop_dir" "$source_branch" "$rel_path" "$target_path"
    counter=$((counter + 1))
    log "$action_label: $rel_path"
  done <"$list_file"

  printf '%s' "$counter"
}

cleanup_empty_parent_dirs() {
  local file_path="$1"
  local root_dir="$2"
  local current_dir
  current_dir="$(dirname "$file_path")"

  while [[ "$current_dir" != "$root_dir" && "$current_dir" != "/" ]]; do
    rmdir "$current_dir" 2>/dev/null || break
    current_dir="$(dirname "$current_dir")"
  done
}

apply_delete_list() {
  local list_file="$1"
  local master_dir="$2"
  local counter=0
  local rel_path

  while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    local target_path="$master_dir/$rel_path"
    if [[ -e "$target_path" ]]; then
      rm -f "$target_path"
      cleanup_empty_parent_dirs "$target_path" "$master_dir"
    fi
    counter=$((counter + 1))
    log "删除文件: $rel_path"
  done <"$list_file"

  printf '%s' "$counter"
}

append_apply_detail() {
  local report_file="$1"
  local title="$2"
  local list_file="$3"

  {
    printf '### %s\n\n' "$title"
    if [[ -s "$list_file" ]]; then
      local rel_path
      while IFS= read -r rel_path; do
        [[ -z "$rel_path" ]] && continue
        printf -- '- `%s`\n' "$rel_path"
      done <"$list_file"
    else
      printf -- '- 无\n'
    fi
    printf '\n'
  } >>"$report_file"
}

do_apply() {
  local plan_file=".git-merge-plan.env"
  local confirm_value=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan-file)
        plan_file="$2"
        shift 2
        ;;
      --confirm)
        confirm_value="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done

  [[ -f "$plan_file" ]] || die "计划文件不存在: $plan_file"
  [[ "$confirm_value" == "yes" ]] || die "apply 必须显式传入 --confirm yes。"

  # shellcheck source=/dev/null
  source "$plan_file"

  [[ -n "${DEVELOP_DIR:-}" ]] || die "计划文件缺少 DEVELOP_DIR"
  [[ -n "${MASTER_DIR:-}" ]] || die "计划文件缺少 MASTER_DIR"
  [[ -n "${SOURCE_BRANCH:-}" ]] || die "计划文件缺少 SOURCE_BRANCH"
  [[ -n "${REPORT_FILE:-}" ]] || die "计划文件缺少 REPORT_FILE"
  [[ -n "${ADDED_LIST_FILE:-}" ]] || die "计划文件缺少 ADDED_LIST_FILE"
  [[ -n "${MODIFIED_LIST_FILE:-}" ]] || die "计划文件缺少 MODIFIED_LIST_FILE"
  [[ -n "${DELETED_LIST_FILE:-}" ]] || die "计划文件缺少 DELETED_LIST_FILE"

  require_directory "$DEVELOP_DIR" "DEVELOP_DIR"
  require_directory "$MASTER_DIR" "MASTER_DIR"
  require_git_repo "$DEVELOP_DIR"
  require_local_branch "$DEVELOP_DIR" "$SOURCE_BRANCH"
  [[ -f "$ADDED_LIST_FILE" ]] || die "计划文件引用的新增列表不存在: $ADDED_LIST_FILE"
  [[ -f "$MODIFIED_LIST_FILE" ]] || die "计划文件引用的修改列表不存在: $MODIFIED_LIST_FILE"
  [[ -f "$DELETED_LIST_FILE" ]] || die "计划文件引用的删除列表不存在: $DELETED_LIST_FILE"

  local added_applied
  local modified_applied
  local deleted_applied

  added_applied="$(apply_copy_list "$ADDED_LIST_FILE" "$DEVELOP_DIR" "$SOURCE_BRANCH" "$MASTER_DIR" "新增文件写入")"
  modified_applied="$(apply_copy_list "$MODIFIED_LIST_FILE" "$DEVELOP_DIR" "$SOURCE_BRANCH" "$MASTER_DIR" "修改文件写入")"
  deleted_applied="$(apply_delete_list "$DELETED_LIST_FILE" "$MASTER_DIR")"

  {
    printf '\n## Apply 结果\n\n'
    printf -- '- 执行时间: `%s`\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf -- '- develop_dir: `%s`\n' "$DEVELOP_DIR"
    printf -- '- source 分支: `%s`\n' "$SOURCE_BRANCH"
    printf -- '- master_dir: `%s`\n' "$MASTER_DIR"
    printf -- '- 新增写入数: `%s`\n' "$added_applied"
    printf -- '- 修改写入数: `%s`\n' "$modified_applied"
    printf -- '- 删除执行数: `%s`\n\n' "$deleted_applied"
  } >>"$REPORT_FILE"

  append_apply_detail "$REPORT_FILE" "新增写入文件" "$ADDED_LIST_FILE"
  append_apply_detail "$REPORT_FILE" "修改写入文件" "$MODIFIED_LIST_FILE"
  append_apply_detail "$REPORT_FILE" "删除文件" "$DELETED_LIST_FILE"

  log "已将计划变更写入 master_dir: $MASTER_DIR"
  log "已更新报告: $REPORT_FILE"
}

main() {
  local action="${1:-}"
  case "$action" in
    prepare)
      shift
      do_prepare "$@"
      ;;
    apply)
      shift
      do_apply "$@"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      die "未知动作: $action"
      ;;
  esac
}

main "$@"
