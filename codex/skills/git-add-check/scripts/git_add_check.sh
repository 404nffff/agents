#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
STRICT=0
VERBOSE=0
STAGED_ONLY=1

usage() {
  cat <<'EOF'
Usage:
  git_add_check.sh [options]

Options:
  --verbose        Print per-file details
  --strict         Treat unsupported types or missing checkers as failure
  --staged-only    Check staged files only (default behavior)
  -h, --help       Show this help
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

err() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

extname() {
  local path="$1"
  local base="${path##*/}"
  if [[ "$base" == *.* ]]; then
    printf '%s' "${base##*.}"
  else
    printf ''
  fi
}

mk_temp_with_suffix() {
  local suffix="$1"
  mktemp "/tmp/git-add-check.XXXXXX.${suffix}"
}

check_shell() {
  local tmp="$1"
  if command_exists bash; then
    bash -n "$tmp"
  else
    return 127
  fi
}

check_python() {
  local tmp="$1"
  if command_exists python3; then
    python3 -m py_compile "$tmp"
  else
    return 127
  fi
}

check_js_like() {
  local tmp="$1"
  if command_exists node; then
    node --check "$tmp"
  else
    return 127
  fi
}

check_go() {
  local tmp="$1"
  if command_exists gofmt; then
    local out
    out="$(gofmt -e "$tmp" 2>&1 >/dev/null || true)"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out" >&2
      return 1
    fi
    return 0
  else
    return 127
  fi
}

check_php() {
  local tmp="$1"
  if command_exists php; then
    php -l "$tmp" >/dev/null
  else
    return 127
  fi
}

check_ruby() {
  local tmp="$1"
  if command_exists ruby; then
    ruby -c "$tmp" >/dev/null
  else
    return 127
  fi
}

run_checker_for_file() {
  local staged_path="$1"
  local ext="$2"
  local tmp_file="$3"

  case "$ext" in
    sh|bash|zsh)
      check_shell "$tmp_file"
      ;;
    py)
      check_python "$tmp_file"
      ;;
    js|mjs|cjs|jsx|ts|tsx|mts|cts)
      check_js_like "$tmp_file"
      ;;
    go)
      check_go "$tmp_file"
      ;;
    php)
      check_php "$tmp_file"
      ;;
    rb)
      check_ruby "$tmp_file"
      ;;
    *)
      return 126
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose)
        VERBOSE=1
        shift
        ;;
      --strict)
        STRICT=1
        shift
        ;;
      --staged-only)
        STAGED_ONLY=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

ensure_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    err "Current directory is not a Git repository."
    exit 1
  }
}

main() {
  parse_args "$@"
  ensure_git_repo

  if [[ "$STAGED_ONLY" -ne 1 ]]; then
    err "Only staged mode is supported."
    exit 1
  fi

  mapfile -t staged_files < <(git diff --cached --name-only --diff-filter=ACMR)

  if [[ "${#staged_files[@]}" -eq 0 ]]; then
    log "No staged files found."
    exit 0
  fi

  local total=0
  local checked=0
  local skipped=0
  local failed=0
  local strict_fail=0

  for path in "${staged_files[@]}"; do
    total=$((total + 1))

    if ! git cat-file -e ":$path" 2>/dev/null; then
      skipped=$((skipped + 1))
      [[ "$VERBOSE" -eq 1 ]] && log "SKIP  $path (not found in index)"
      [[ "$STRICT" -eq 1 ]] && strict_fail=$((strict_fail + 1))
      continue
    fi

    local ext
    ext="$(extname "$path")"
    local suffix="$ext"
    [[ -z "$suffix" ]] && suffix="tmp"

    local tmp_file
    tmp_file="$(mk_temp_with_suffix "$suffix")"

    if ! git show ":$path" >"$tmp_file" 2>/dev/null; then
      rm -f "$tmp_file"
      skipped=$((skipped + 1))
      [[ "$VERBOSE" -eq 1 ]] && log "SKIP  $path (cannot read staged blob)"
      [[ "$STRICT" -eq 1 ]] && strict_fail=$((strict_fail + 1))
      continue
    fi

    set +e
    run_checker_for_file "$path" "$ext" "$tmp_file"
    rc=$?
    set -e

    rm -f "$tmp_file"

    case "$rc" in
      0)
        checked=$((checked + 1))
        [[ "$VERBOSE" -eq 1 ]] && log "PASS  $path"
        ;;
      126)
        skipped=$((skipped + 1))
        [[ "$VERBOSE" -eq 1 ]] && log "SKIP  $path (unsupported type: .$ext)"
        [[ "$STRICT" -eq 1 ]] && strict_fail=$((strict_fail + 1))
        ;;
      127)
        skipped=$((skipped + 1))
        [[ "$VERBOSE" -eq 1 ]] && log "SKIP  $path (checker command missing)"
        [[ "$STRICT" -eq 1 ]] && strict_fail=$((strict_fail + 1))
        ;;
      *)
        failed=$((failed + 1))
        log "FAIL  $path"
        ;;
    esac
  done

  log "Summary: total=$total checked=$checked skipped=$skipped failed=$failed"

  if [[ "$failed" -gt 0 ]]; then
    err "Syntax check failed."
    exit 1
  fi

  if [[ "$STRICT" -eq 1 && "$strict_fail" -gt 0 ]]; then
    err "Strict mode failed due to skipped files/checkers."
    exit 1
  fi

  log "Syntax check passed."
}

main "$@"
