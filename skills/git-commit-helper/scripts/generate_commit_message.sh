#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR=""
AI_URL_ARG=""
AI_MODEL_ARG=""
AI_KEY_ARG=""
NO_AI=0

stderr() {
  printf '%s\n' "$*" >&2
}

fail() {
  local message="$1"
  local code="${2:-1}"
  stderr "ERROR: ${message}"
  exit "$code"
}

trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

load_dotenv_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(printf '%s' "$line" | trim)"
    [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *"="* ]] && continue

    key="$(printf '%s' "${line%%=*}" | trim)"
    value="$(printf '%s' "${line#*=}" | trim)"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -z "${!key+x}" ]] || continue

    if [[ ${#value} -ge 2 ]]; then
      if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:${#value}-2}"
      elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
        value="${value:1:${#value}-2}"
      fi
    fi

    # 仅写入当前进程环境，避免密钥进入日志、提交信息或仓库文件。
    export "${key}=${value}"
  done < "$path"
}

usage() {
  cat <<'EOF'
Usage: generate_commit_message.sh [--project-dir DIR] [--ai-url URL] [--ai-model MODEL] [--ai-key KEY] [--no-ai]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || fail "--project-dir requires a value"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --ai-url)
      [[ $# -ge 2 ]] || fail "--ai-url requires a value"
      AI_URL_ARG="$2"
      shift 2
      ;;
    --ai-model)
      [[ $# -ge 2 ]] || fail "--ai-model requires a value"
      AI_MODEL_ARG="$2"
      shift 2
      ;;
    --ai-key)
      [[ $# -ge 2 ]] || fail "--ai-key requires a value"
      AI_KEY_ARG="$2"
      shift 2
      ;;
    --no-ai)
      NO_AI=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

resolve_project_dir() {
  local dir="$1"
  [[ -n "$dir" ]] || dir="$(pwd -P)"
  [[ -d "$dir" ]] || fail "project dir not found: ${dir}"
  (cd "$dir" && pwd -P) || fail "project dir not found: ${dir}"
}

git_output() {
  local output
  if ! output="$(git -C "$PROJECT_DIR" "$@" 2>&1)"; then
    fail "git command failed: $(printf '%s' "$output" | head -c 500)"
  fi
  printf '%s' "$output"
}

git_log_output() {
  local output
  if ! git -C "$PROJECT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    return 0
  fi
  if ! output="$(git -C "$PROJECT_DIR" log --oneline -10 2>&1)"; then
    fail "git log failed: $(printf '%s' "$output" | head -c 500)"
  fi
  printf '%s' "$output"
}

is_ignored_lockfile() {
  case "$(basename -- "$1")" in
    pnpm-lock.yaml|package-lock.json|yarn.lock|bun.lockb) return 0 ;;
    *) return 1 ;;
  esac
}

collect_staged_files() {
  local file
  STAGED_FILES=()
  while IFS= read -r file || [[ -n "$file" ]]; do
    [[ -n "$file" ]] || continue
    if ! is_ignored_lockfile "$file"; then
      STAGED_FILES+=("$file")
    fi
  done < <(git_output diff --cached --name-only)
}

staged_diff() {
  git_output diff --cached -- . \
    ':(exclude)pnpm-lock.yaml' \
    ':(exclude)package-lock.json' \
    ':(exclude)yarn.lock' \
    ':(exclude)bun.lockb'
}

staged_stat() {
  git_output diff --cached --stat -- . \
    ':(exclude)pnpm-lock.yaml' \
    ':(exclude)package-lock.json' \
    ':(exclude)yarn.lock' \
    ':(exclude)bun.lockb'
}

record_secret_violation() {
  SECRET_VIOLATIONS+=("$1")
}

check_sensitive_paths() {
  local file base lower_base lower_file
  for file in "${STAGED_FILES[@]}"; do
    base="$(basename -- "$file")"
    lower_base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    lower_file="$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')"

    case "$lower_base" in
      .env|.env.*)
        if [[ "$lower_base" != ".env.example" && "$lower_base" != *.example ]]; then
          record_secret_violation "敏感文件路径: ${file}"
        fi
        ;;
      *.pem|*.key|*.p12|*.pfx|id_rsa|id_ed25519|id_dsa|id_ecdsa)
        record_secret_violation "密钥文件路径: ${file}"
        ;;
    esac

    case "$lower_file" in
      *credentials*.json|*service-account*.json|*service_account*.json)
        record_secret_violation "凭证文件路径: ${file}"
        ;;
    esac
  done
}

check_added_lines_for_secret() {
  local diff added_lines
  diff="$1"
  added_lines="$(printf '%s\n' "$diff" | awk '/^\+\+\+ / { next } /^\+/ { print substr($0, 2) }')"
  [[ -n "$added_lines" ]] || return 0

  if grep -Eiq -- '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----' <<< "$added_lines"; then
    record_secret_violation "新增行命中私钥块规则"
  fi
  if grep -Eiq -- 'AKIA[0-9A-Z]{16}' <<< "$added_lines"; then
    record_secret_violation "新增行命中 AWS Access Key 规则"
  fi
  if grep -Eiq -- '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}' <<< "$added_lines"; then
    record_secret_violation "新增行命中 GitHub Token 规则"
  fi
  if grep -Eiq -- 'sk-[A-Za-z0-9][A-Za-z0-9_-]{18,}' <<< "$added_lines"; then
    record_secret_violation "新增行命中 OpenAI 风格 Key 规则"
  fi
  if grep -Eiq -- 'xox[baprs]-[A-Za-z0-9-]{10,}' <<< "$added_lines"; then
    record_secret_violation "新增行命中 Slack Token 规则"
  fi
  if grep -Eiq -- "(api[_-]?key|apikey|secret|token|password|passwd|pwd)[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_./+=:@%~-]{12,}" <<< "$added_lines"; then
    record_secret_violation "新增行命中密钥字段赋值规则"
  fi
  if grep -Eiq -- 'bearer[[:space:]]+[A-Za-z0-9_./+=:@%~-]{20,}' <<< "$added_lines"; then
    record_secret_violation "新增行命中 Bearer Token 规则"
  fi
}

assert_no_staged_secrets() {
  local diff="$1"
  SECRET_VIOLATIONS=()

  # 提交信息生成前先扫描暂存区，命中后只输出规则和文件名，避免泄露具体值。
  check_sensitive_paths
  check_added_lines_for_secret "$diff"

  if [[ ${#SECRET_VIOLATIONS[@]} -gt 0 ]]; then
    stderr "ERROR: staged changes may contain sensitive information:"
    local violation
    for violation in "${SECRET_VIOLATIONS[@]}"; do
      stderr "- ${violation}"
    done
    stderr "Remove sensitive values from staged changes before generating commit message. Matched values are not printed."
    exit 2
  fi
}

classify_gitmoji() {
  local joined="$1"
  local diff="$2"
  if grep -Eiq -- '(^|/)(README|docs/|.*\.md$)' <<< "$joined"; then
    printf ':memo:'
  elif grep -Eiq -- '(^|/)(tests?|__tests__)/|\.test\.|\.spec\.' <<< "$joined"; then
    printf ':white_check_mark:'
  elif grep -Eiq -- '(^|/)(Dockerfile|docker|docker-compose\.ya?ml)' <<< "$joined"; then
    printf ':whale:'
  elif grep -Eiq -- '(^|/)(AGENTS\.md|\.env\.example|.*\.ya?ml$|.*\.json$)' <<< "$joined"; then
    printf ':wrench:'
  elif grep -Eq -- '^deleted file mode' <<< "$diff"; then
    printf ':fire:'
  else
    printf ':sparkles:'
  fi
}

module_name() {
  local file path first second
  for file in "${STAGED_FILES[@]}"; do
    path="${file//\\//}"
    IFS='/' read -r first second _ <<< "$path"
    if [[ -n "${first:-}" && -n "${second:-}" ]]; then
      printf '%s/%s' "$first" "$second"
      return 0
    fi
    if [[ -n "${first:-}" ]]; then
      printf '%s' "$first"
      return 0
    fi
  done
  printf '暂存变更'
}

local_commit_title() {
  local diff="$1"
  local joined emoji module
  joined="$(printf '%s\n' "${STAGED_FILES[@]}")"
  emoji="$(classify_gitmoji "$joined" "$diff")"
  module="$(module_name)"

  if grep -Fq 'skills/git-commit-helper' <<< "$joined"; then
    printf '%s 增强 git-commit-helper 暂存敏感信息检查与 shell 入口' "$emoji"
  elif grep -Eq -- '^new file mode' <<< "$diff"; then
    printf '%s 新增 %s 相关能力与配套说明' "$emoji" "$module"
  elif grep -Eq -- '^deleted file mode' <<< "$diff"; then
    printf '%s 清理 %s 过时文件与无效实现' "$emoji" "$module"
  else
    printf '%s 更新 %s 相关实现与文档说明' "$emoji" "$module"
  fi
}

pick_first() {
  local value
  for value in "$@"; do
    if [[ -n "${value:-}" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

normalize_ai_url() {
  local url="${1%/}"
  [[ -n "$url" ]] || return 0
  if [[ "$url" =~ /v1/chat/completions?$ ]]; then
    printf '%s' "$url"
  else
    printf '%s/v1/chat/completions' "$url"
  fi
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

sanitize_title() {
  awk 'NF { print; exit }' | sed -e 's/^[[:space:]`"'"'"']*//' -e 's/[[:space:]`"'"'"']*$//' -e 's/[[:space:]][[:space:]]*/ /g'
}

assert_useful_title() {
  local title="$1"
  local plain="$title"
  plain="$(printf '%s' "$plain" | sed -E 's/^:[a-z0-9_+-]+:[[:space:]]*//I')"
  if [[ ${#plain} -lt 16 ]]; then
    fail "AI commit title is too short; expected a concrete title with module and change intent"
  fi
  if [[ ${#title} -gt 90 ]]; then
    fail "AI commit title is too long; keep it as one concise commit subject"
  fi
}

extract_ai_content() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
  elif command -v python >/dev/null 2>&1 && python -c 'import json' >/dev/null 2>&1; then
    python -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
  elif command -v node >/dev/null 2>&1 && node -e 'JSON.parse("{}")' >/dev/null 2>&1; then
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).choices[0].message.content));'
  else
    fail "AI title polish requires python3, python or node to parse JSON response"
  fi
}

polish_with_openai() {
  local local_title="$1"
  local stat="$2"
  local diff="$3"
  local log="$4"
  local url="$5"
  local model="$6"
  local key="$7"

  [[ -n "$url" && -n "$model" && -n "$key" ]] || fail "AI title polish requires API_URL, MODEL and API_KEY"
  command -v curl >/dev/null 2>&1 || fail "AI title polish requires curl"

  local files prompt payload response http_code body content title
  files="$(printf '%s\n' "${STAGED_FILES[@]}")"
  prompt="$(cat <<EOF
请基于暂存区变更润色 Git 提交标题，只输出一行标题。
要求：沿用历史提交风格；优先使用合适 GitMoji；中文标题不要太短，需包含模块和具体变更意图；长度建议 18-72 个中文字符；不要解释。

【本地初稿】
${local_title}

【暂存文件】
${files}

【变更统计】
${stat}

【关键 diff】
${diff}

【最近提交】
${log}
EOF
)"
  prompt="$(printf '%s' "$prompt" | head -c 18000)"
  payload="{\"model\":\"$(json_escape "$model")\",\"messages\":[{\"role\":\"system\",\"content\":\"你是 Git 提交信息编辑器，只输出一行提交标题。\"},{\"role\":\"user\",\"content\":\"$(json_escape "$prompt")\"}],\"temperature\":0.2}"

  if ! response="$(curl -sS -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${key}" \
    --data "$payload" \
    "$url")"; then
    fail "AI title polish request failed: ${url}"
  fi

  http_code="${response##*$'\n'}"
  body="${response%$'\n'"$http_code"}"
  if [[ "$http_code" =~ ^[45][0-9][0-9]$ ]]; then
    fail "AI title polish HTTP ${http_code}: $(printf '%s' "$body" | head -c 500)"
  fi

  if ! content="$(printf '%s' "$body" | extract_ai_content 2>/dev/null)"; then
    fail "AI title polish response missing choices[0].message.content"
  fi
  title="$(printf '%s' "$content" | sanitize_title)"
  [[ -n "$title" ]] || fail "AI title polish response missing choices[0].message.content"
  assert_useful_title "$title"
  printf '%s' "$title"
}

load_dotenv_file "${SCRIPT_DIR}/.env"
PROJECT_DIR="$(resolve_project_dir "$PROJECT_DIR")"

collect_staged_files
[[ ${#STAGED_FILES[@]} -gt 0 ]] || fail "no staged files found; run git add first"

DIFF="$(staged_diff)"
assert_no_staged_secrets "$DIFF"

STAT="$(staged_stat | head -c 4000)"
DIFF_FOR_PROMPT="$(printf '%s' "$DIFF" | head -c 12000)"
LOG="$(git_log_output)"
TITLE="$(local_commit_title "$DIFF")"

AI_URL="$(pick_first "$AI_URL_ARG" "${API_URL:-}")"
AI_MODEL="$(pick_first "$AI_MODEL_ARG" "${MODEL:-}")"
AI_KEY="$(pick_first "$AI_KEY_ARG" "${API_KEY:-}")"

if [[ "$NO_AI" -eq 0 && ( -n "$AI_URL" || -n "$AI_MODEL" || -n "$AI_KEY" ) ]]; then
  TITLE="$(polish_with_openai "$TITLE" "$STAT" "$DIFF_FOR_PROMPT" "$LOG" "$(normalize_ai_url "$AI_URL")" "$AI_MODEL" "$AI_KEY")"
fi

printf '%s\n' "$TITLE" | sanitize_title
