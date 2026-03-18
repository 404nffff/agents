#!/usr/bin/env bash
set -euo pipefail

MAX_LIMIT=1000
DEFAULT_LIMIT=100
DEFAULT_MAX_ROWS=2000

usage() {
  cat <<'EOF'
Usage:
  mysql_query.sh [options]

Options:
  --profile <name>      connection profile name in config env
  --host <host>         mysql host
  --port <port>         mysql port
  --user <user>         mysql user
  --password <pwd>      mysql password
  --database <db>       mysql database
  --socket <path>       mysql unix socket
  --timeout <sec>       connect timeout seconds
  --query <sql>         read-only sql
  --table <name>        structured select mode table name
  --columns <csv>       structured mode columns (default: *)
  --where <expr>        where expression
  --order-by <expr>     order by expression
  --limit <n>           structured mode limit (1-1000)
  --max-rows <n>        maximum allowed result rows (default: 2000)
  -h, --help            show this help
EOF
}

error() {
  echo "ERROR: $*" >&2
  exit 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_identifier() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

is_profile_name() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

get_profile_var() {
  local key="$1"
  local profile="$2"
  local var_name="${key}_${profile}"
  printf '%s' "${!var_name-}"
}

strip_sql_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{ }gs;
    s/--[^\n]*/ /g;
    s/\#[^\n]*/ /g;
  ' <<<"$1"
}

validate_sql() {
  local raw="$1"
  local norm lower first

  norm="$(strip_sql_comments "$raw")"
  norm="$(trim "$norm")"
  norm="${norm%;}"
  norm="$(trim "$norm")"
  [[ -n "$norm" ]] || error "query is empty after normalization"

  [[ "$norm" != *";"* ]] || error "multiple SQL statements are not allowed"

  lower="$(tr '[:upper:]' '[:lower:]' <<<"$norm")"
  first="$(awk '{print tolower($1)}' <<<"$lower")"
  case "$first" in
    select|show|desc|describe|explain|with) ;;
    *) error "only read-only SQL is allowed (SELECT/SHOW/DESC/DESCRIBE/EXPLAIN/WITH)" ;;
  esac

  local forbidden_keywords=(
    delete insert update replace truncate drop alter create grant revoke rename merge call
  )
  local kw
  for kw in "${forbidden_keywords[@]}"; do
    if grep -Eiq "\\b${kw}\\b" <<<"$lower"; then
      error "forbidden SQL keyword detected: ${kw}"
    fi
  done

  grep -Eiq '\binto[[:space:]]+outfile\b' <<<"$lower" && error "forbidden SQL pattern detected: INTO OUTFILE"
  grep -Eiq '\binto[[:space:]]+dumpfile\b' <<<"$lower" && error "forbidden SQL pattern detected: INTO DUMPFILE"
  grep -Eiq '\bload[[:space:]]+data\b' <<<"$lower" && error "forbidden SQL pattern detected: LOAD DATA"
  grep -Eiq '\block[[:space:]]+tables?\b' <<<"$lower" && error "forbidden SQL pattern detected: LOCK TABLES"
  grep -Eiq '\bunlock[[:space:]]+tables?\b' <<<"$lower" && error "forbidden SQL pattern detected: UNLOCK TABLES"

  printf '%s' "$norm"
}

build_structured_query() {
  local table="$1"
  local columns="$2"
  local where="$3"
  local order_by="$4"
  local limit="$5"
  local query="SELECT "

  if [[ "$columns" == "*" ]]; then
    query+="*"
  else
    IFS=',' read -r -a cols <<<"$columns"
    local joined=""
    local c
    for c in "${cols[@]}"; do
      c="$(trim "$c")"
      [[ -n "$c" ]] || continue
      is_identifier "$c" || error "invalid column: $c"
      if [[ -n "$joined" ]]; then
        joined+=", "
      fi
      joined+="\`$c\`"
    done
    [[ -n "$joined" ]] || error "columns cannot be empty"
    query+="$joined"
  fi

  query+=" FROM \`$table\`"

  if [[ -n "$where" ]]; then
    query+=" WHERE $where"
  fi
  if [[ -n "$order_by" ]]; then
    query+=" ORDER BY $order_by"
  fi
  query+=" LIMIT $limit"
  printf '%s' "$query"
}

CONFIG_PATH="$(cd "$(dirname "$0")/.." && pwd)/config.env"
HOST=""
PORT=""
USER=""
PASSWORD=""
DATABASE=""
SOCKET=""
TIMEOUT=""
QUERY=""
TABLE=""
COLUMNS="*"
WHERE_EXPR=""
ORDER_BY=""
LIMIT="$DEFAULT_LIMIT"
MAX_ROWS="$DEFAULT_MAX_ROWS"
PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --socket) SOCKET="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --query) QUERY="$2"; shift 2 ;;
    --table) TABLE="$2"; shift 2 ;;
    --columns) COLUMNS="$2"; shift 2 ;;
    --where) WHERE_EXPR="$2"; shift 2 ;;
    --order-by) ORDER_BY="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --max-rows) MAX_ROWS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) error "unknown argument: $1" ;;
  esac
done

[[ -f "$CONFIG_PATH" ]] || error "config file not found: $CONFIG_PATH"
# shellcheck disable=SC1090
source "$CONFIG_PATH"

PROFILE_HOST=""
PROFILE_PORT=""
PROFILE_USER=""
PROFILE_PASSWORD=""
PROFILE_DATABASE=""
PROFILE_SOCKET=""
PROFILE_TIMEOUT=""

if [[ -z "$PROFILE" && -n "${MYSQL_PROFILE:-}" ]]; then
  PROFILE="$MYSQL_PROFILE"
fi

if [[ -n "$PROFILE" ]]; then
  is_profile_name "$PROFILE" || error "invalid --profile name: $PROFILE"

  PROFILE_HOST="$(get_profile_var MYSQL_HOST "$PROFILE")"
  PROFILE_PORT="$(get_profile_var MYSQL_PORT "$PROFILE")"
  PROFILE_USER="$(get_profile_var MYSQL_USER "$PROFILE")"
  PROFILE_PASSWORD="$(get_profile_var MYSQL_PASSWORD "$PROFILE")"
  PROFILE_DATABASE="$(get_profile_var MYSQL_DATABASE "$PROFILE")"
  PROFILE_SOCKET="$(get_profile_var MYSQL_SOCKET "$PROFILE")"
  PROFILE_TIMEOUT="$(get_profile_var MYSQL_TIMEOUT "$PROFILE")"

  if [[ -z "$PROFILE_HOST" && -z "$PROFILE_PORT" && -z "$PROFILE_USER" && -z "$PROFILE_PASSWORD" && -z "$PROFILE_DATABASE" && -z "$PROFILE_SOCKET" && -z "$PROFILE_TIMEOUT" ]]; then
    error "profile not found: $PROFILE"
  fi

fi

if [[ -z "$PROFILE" && -z "$HOST" && -z "$PORT" && -z "$USER" && -z "$PASSWORD" && -z "$DATABASE" && -z "$SOCKET" && -z "$TIMEOUT" ]]; then
  error "profile is required: pass --profile or set MYSQL_PROFILE"
fi

HOST="${HOST:-$PROFILE_HOST}"
PORT="${PORT:-$PROFILE_PORT}"
USER="${USER:-$PROFILE_USER}"
PASSWORD="${PASSWORD:-$PROFILE_PASSWORD}"
DATABASE="${DATABASE:-$PROFILE_DATABASE}"
SOCKET="${SOCKET:-$PROFILE_SOCKET}"
TIMEOUT="${TIMEOUT:-$PROFILE_TIMEOUT}"

[[ "$LIMIT" =~ ^[0-9]+$ ]] || error "--limit must be a positive integer"
(( LIMIT > 0 )) || error "--limit must be greater than 0"
(( LIMIT <= MAX_LIMIT )) || error "--limit cannot exceed ${MAX_LIMIT}"

[[ "$MAX_ROWS" =~ ^[0-9]+$ ]] || error "--max-rows must be a positive integer"
(( MAX_ROWS > 0 )) || error "--max-rows must be greater than 0"

if [[ -n "$QUERY" ]]; then
  FINAL_QUERY="$(validate_sql "$QUERY")"
else
  [[ -n "$TABLE" ]] || error "either --query or --table is required"
  is_identifier "$TABLE" || error "invalid table: $TABLE"
  STRUCTURED_QUERY="$(build_structured_query "$TABLE" "$COLUMNS" "$WHERE_EXPR" "$ORDER_BY" "$LIMIT")"
  FINAL_QUERY="$(validate_sql "$STRUCTURED_QUERY")"
fi

MYSQL_CMD=(mysql --batch --raw --default-character-set=utf8mb4)
[[ -n "$HOST" ]] && MYSQL_CMD+=(--host "$HOST")
[[ -n "$PORT" ]] && MYSQL_CMD+=(--port "$PORT")
[[ -n "$USER" ]] && MYSQL_CMD+=(--user "$USER")
[[ -n "$SOCKET" ]] && MYSQL_CMD+=(--socket "$SOCKET")
[[ -n "$TIMEOUT" ]] && MYSQL_CMD+=(--connect-timeout "$TIMEOUT")
[[ -n "$DATABASE" ]] && MYSQL_CMD+=("$DATABASE")
MYSQL_CMD+=(--execute "$FINAL_QUERY")

MYSQL_OUTPUT=""
if [[ -n "$PASSWORD" ]]; then
  MYSQL_OUTPUT="$(MYSQL_PWD="$PASSWORD" "${MYSQL_CMD[@]}" 2>&1)" || error "$MYSQL_OUTPUT"
else
  MYSQL_OUTPUT="$("${MYSQL_CMD[@]}" 2>&1)" || error "$MYSQL_OUTPUT"
fi

NON_EMPTY_LINES="$(grep -cve '^[[:space:]]*$' <<<"$MYSQL_OUTPUT" || true)"
ROW_COUNT=$(( NON_EMPTY_LINES > 0 ? NON_EMPTY_LINES - 1 : 0 ))
(( ROW_COUNT <= MAX_ROWS )) || error "query returned ${ROW_COUNT} rows, exceeding --max-rows=${MAX_ROWS}"
printf '%s\n' "$MYSQL_OUTPUT"
