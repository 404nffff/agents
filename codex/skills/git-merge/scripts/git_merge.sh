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
  --source <branch>      Source branch (default: develop)
  --target <branch>      Target branch (default: master)
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

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "当前目录不是 Git 仓库。"
}

require_local_branch() {
  local branch="$1"
  git show-ref --verify --quiet "refs/heads/$branch" || die "本地分支不存在: $branch"
}

escape_single_quote() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

write_plan_file() {
  local plan_file="$1"
  local source_branch="$2"
  local target_branch="$3"
  local author_filter="$4"
  local since_value="$5"
  local until_value="$6"
  local max_count_value="$7"
  local report_file="$8"
  local commit_list="$9"

  cat >"$plan_file" <<EOF
SOURCE_BRANCH='$(escape_single_quote "$source_branch")'
TARGET_BRANCH='$(escape_single_quote "$target_branch")'
AUTHOR_FILTER='$(escape_single_quote "$author_filter")'
SINCE='$(escape_single_quote "$since_value")'
UNTIL='$(escape_single_quote "$until_value")'
MAX_COUNT='$(escape_single_quote "$max_count_value")'
REPORT_FILE='$(escape_single_quote "$report_file")'
COMMITS='$(escape_single_quote "$commit_list")'
GENERATED_AT='$(date -u '+%Y-%m-%dT%H:%M:%SZ')'
EOF
}

render_commit_block() {
  local hash="$1"
  local author_name="$2"
  local author_email="$3"
  local author_date="$4"
  local subject="$5"
  local index="$6"

  {
    printf '## %s. %s\n\n' "$index" "$subject"
    printf -- '- Commit: `%s`\n' "$hash"
    printf -- '- Author: `%s <%s>`\n' "$author_name" "$author_email"
    printf -- '- Date: `%s`\n' "$author_date"
    printf -- '- 修改文件:\n'
  }

  local files
  files="$(git show --pretty='' --name-only "$hash" | sed '/^$/d')"
  if [[ -n "$files" ]]; then
    while IFS= read -r file; do
      printf '  - `%s`\n' "$file"
    done <<<"$files"
  else
    printf '  - 无\n'
  fi

  printf -- '- 文件增删统计:\n'
  local numstat
  numstat="$(git show --numstat --format='' "$hash")"
  if [[ -n "$numstat" ]]; then
    while IFS=$'\t' read -r add del file; do
      [[ -z "${file:-}" ]] && continue
      printf '  - `%s`: +%s / -%s\n' "$file" "$add" "$del"
    done <<<"$numstat"
  else
    printf '  - 无\n'
  fi

  printf -- '- 关键改动片段（最多 120 行）:\n\n'
  printf '```diff\n'
  git show --no-color --format='' --unified=1 "$hash" | awk 'NR<=120{print} NR==121{print "...(truncated)"}'
  printf '```\n\n'
}

do_prepare() {
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

  require_git_repo
  require_local_branch "$source_branch"
  require_local_branch "$target_branch"

  [[ -n "$author_filter" ]] || die "prepare 必须指定 --author。"
  if [[ -z "$since_value" && -z "$max_count_value" ]]; then
    die "prepare 至少需要指定 --since 或 --max-count，用于限定提交历史。"
  fi

  local range_spec="${target_branch}..${source_branch}"
  local -a log_cmd=(
    git log "$range_spec"
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
    printf -- '- 源分支: `%s`\n' "$source_branch"
    printf -- '- 目标分支: `%s`\n' "$target_branch"
    printf -- '- 提交人筛选: `%s`\n' "$author_filter"
    [[ -n "$since_value" ]] && printf -- '- Since: `%s`\n' "$since_value"
    [[ -n "$until_value" ]] && printf -- '- Until: `%s`\n' "$until_value"
    [[ -n "$max_count_value" ]] && printf -- '- Max Count: `%s`\n' "$max_count_value"
    printf -- '- 待合并提交数: `%s`\n\n' "${#commit_lines[@]}"
  } >"$output_file"

  if [[ ${#commit_lines[@]} -eq 0 ]]; then
    {
      printf '## 结果\n\n'
      printf '未找到符合条件的提交。\n'
    } >>"$output_file"
    write_plan_file "$plan_file" "$source_branch" "$target_branch" "$author_filter" "$since_value" "$until_value" "$max_count_value" "$output_file" ""
    log "已生成报告: $output_file"
    log "未发现可合并提交。"
    exit 0
  fi

  local -a hashes=()
  local idx=1
  for line in "${commit_lines[@]}"; do
    IFS=$'\x1f' read -r hash author_name author_email author_date subject <<<"$line"
    hashes+=("$hash")
    render_commit_block "$hash" "$author_name" "$author_email" "$author_date" "$subject" "$idx" >>"$output_file"
    idx=$((idx + 1))
  done

  local commit_list
  commit_list="$(printf '%s ' "${hashes[@]}" | sed 's/[[:space:]]*$//')"
  write_plan_file "$plan_file" "$source_branch" "$target_branch" "$author_filter" "$since_value" "$until_value" "$max_count_value" "$output_file" "$commit_list"

  log "已生成报告: $output_file"
  log "已生成计划: $plan_file"
  log "请先人工确认报告，再执行 apply。"
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

  require_git_repo
  [[ -f "$plan_file" ]] || die "计划文件不存在: $plan_file"
  [[ "$confirm_value" == "yes" ]] || die "apply 必须显式传入 --confirm yes。"

  # shellcheck source=/dev/null
  source "$plan_file"

  [[ -n "${SOURCE_BRANCH:-}" ]] || die "计划文件缺少 SOURCE_BRANCH"
  [[ -n "${TARGET_BRANCH:-}" ]] || die "计划文件缺少 TARGET_BRANCH"
  [[ -n "${REPORT_FILE:-}" ]] || die "计划文件缺少 REPORT_FILE"

  require_local_branch "$SOURCE_BRANCH"
  require_local_branch "$TARGET_BRANCH"

  if [[ -z "${COMMITS:-}" ]]; then
    log "计划文件中没有可合并提交，跳过写入。"
    exit 0
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    die "当前工作区不干净，请先提交或清理后再执行 apply。"
  fi

  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "$TARGET_BRANCH" ]]; then
    git checkout "$TARGET_BRANCH" >/dev/null
    log "已切换到目标分支: $TARGET_BRANCH"
  fi

  local -a commit_array=()
  read -r -a commit_array <<<"$COMMITS"
  [[ ${#commit_array[@]} -gt 0 ]] || die "COMMITS 为空，无法执行。"

  local applied=0
  for hash in "${commit_array[@]}"; do
    log "开始 cherry-pick: $hash"
    if git cherry-pick "$hash" >/dev/null; then
      applied=$((applied + 1))
      log "完成 cherry-pick: $hash"
    else
      die "cherry-pick 失败: $hash。请处理冲突后执行 git cherry-pick --continue，或执行 git cherry-pick --abort。"
    fi
  done

  {
    printf '\n## Apply 结果\n\n'
    printf -- '- 执行时间: `%s`\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf -- '- 源分支: `%s`\n' "$SOURCE_BRANCH"
    printf -- '- 目标分支: `%s`\n' "$TARGET_BRANCH"
    printf -- '- 实际写入提交数: `%s`\n' "$applied"
    printf -- '- 写入提交:\n'
    for hash in "${commit_array[@]}"; do
      printf '  - `%s`\n' "$hash"
    done
  } >>"$REPORT_FILE"

  log "已写入目标分支: $TARGET_BRANCH"
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
