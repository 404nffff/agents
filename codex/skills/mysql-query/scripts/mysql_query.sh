#!/usr/bin/env bash
set -euo pipefail

MAX_LIMIT=1000
DEFAULT_LIMIT=100
DEFAULT_MAX_ROWS=2000
DEFAULT_SQL_ALLOWED_START="select,show,desc,describe,explain,with"
DEFAULT_SQL_FORBIDDEN_KEYWORDS="delete,insert,update,replace,truncate,drop,alter,create,grant,revoke,rename,merge,call"
DEFAULT_SQL_FORBIDDEN_PHRASES="into_outfile,into_dumpfile,load_data,lock_tables,unlock_tables"

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
  --format <json|table> output format (default: json)
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

normalize_spaces_lower() {
  local s="$1"
  s="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
  s="$(tr -s '[:space:]' ' ' <<<"$s")"
  s="$(trim "$s")"
  printf '%s' "$s"
}

parse_keyword_csv() {
  local csv="$1"
  local item normalized
  IFS=',' read -r -a items <<<"$csv"
  for item in "${items[@]}"; do
    normalized="$(normalize_spaces_lower "$item")"
    [[ -n "$normalized" ]] || continue
    [[ "$normalized" =~ ^[a-z_][a-z0-9_]*$ ]] || continue
    printf '%s\n' "$normalized"
  done | awk '!seen[$0]++'
}

parse_phrase_csv() {
  local csv="$1"
  local item normalized
  IFS=',' read -r -a items <<<"$csv"
  for item in "${items[@]}"; do
    normalized="$(normalize_spaces_lower "$item")"
    normalized="${normalized//_/ }"
    normalized="$(normalize_spaces_lower "$normalized")"
    [[ -n "$normalized" ]] || continue
    printf '%s\n' "$normalized"
  done | awk '!seen[$0]++'
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
  local norm lower first allow_show_create compact_sql

  norm="$(strip_sql_comments "$raw")"
  norm="$(trim "$norm")"
  norm="${norm%;}"
  norm="$(trim "$norm")"
  [[ -n "$norm" ]] || error "query is empty after normalization"

  [[ "$norm" != *";"* ]] || error "multiple SQL statements are not allowed"

  lower="$(tr '[:upper:]' '[:lower:]' <<<"$norm")"
  compact_sql="$(normalize_spaces_lower "$lower")"
  allow_show_create="false"
  if grep -Eiq '^[[:space:]]*show[[:space:]]+create\b' <<<"$lower"; then
    allow_show_create="true"
  fi
  first="$(awk '{print tolower($1)}' <<<"$lower")"
  local allowed_match="false"
  local kw phrase
  while IFS= read -r kw; do
    [[ "$first" == "$kw" ]] && allowed_match="true" && break
  done < <(parse_keyword_csv "$SQL_ALLOWED_START")
  [[ "$allowed_match" == "true" ]] || error "only read-only SQL is allowed (allowed starts: ${SQL_ALLOWED_START})"

  while IFS= read -r kw; do
    if [[ "$kw" == "create" && "$allow_show_create" == "true" ]]; then
      continue
    fi
    if grep -Eiq "\\b${kw}\\b" <<<"$lower"; then
      error "forbidden SQL keyword detected: ${kw}"
    fi
  done < <(parse_keyword_csv "$SQL_FORBIDDEN_KEYWORDS")

  while IFS= read -r phrase; do
    if [[ "$compact_sql" == *"$phrase"* ]]; then
      error "forbidden SQL pattern detected: $(tr '[:lower:]' '[:upper:]' <<<"$phrase")"
    fi
  done < <(parse_phrase_csv "$SQL_FORBIDDEN_PHRASES")

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
OUTPUT_FORMAT="json"
SQL_ALLOWED_START="$DEFAULT_SQL_ALLOWED_START"
SQL_FORBIDDEN_KEYWORDS="$DEFAULT_SQL_FORBIDDEN_KEYWORDS"
SQL_FORBIDDEN_PHRASES="$DEFAULT_SQL_FORBIDDEN_PHRASES"

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
    --format) OUTPUT_FORMAT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) error "unknown argument: $1" ;;
  esac
done

[[ -f "$CONFIG_PATH" ]] || error "config file not found: $CONFIG_PATH"
# shellcheck disable=SC1090
source "$CONFIG_PATH"

SQL_ALLOWED_START="${MYSQL_SQL_ALLOWED_START:-$DEFAULT_SQL_ALLOWED_START}"
SQL_FORBIDDEN_KEYWORDS="${MYSQL_SQL_FORBIDDEN_KEYWORDS:-$DEFAULT_SQL_FORBIDDEN_KEYWORDS}"
SQL_FORBIDDEN_PHRASES="${MYSQL_SQL_FORBIDDEN_PHRASES:-$DEFAULT_SQL_FORBIDDEN_PHRASES}"
[[ -n "$(parse_keyword_csv "$SQL_ALLOWED_START")" ]] || SQL_ALLOWED_START="$DEFAULT_SQL_ALLOWED_START"
[[ -n "$(parse_keyword_csv "$SQL_FORBIDDEN_KEYWORDS")" ]] || SQL_FORBIDDEN_KEYWORDS="$DEFAULT_SQL_FORBIDDEN_KEYWORDS"
[[ -n "$(parse_phrase_csv "$SQL_FORBIDDEN_PHRASES")" ]] || SQL_FORBIDDEN_PHRASES="$DEFAULT_SQL_FORBIDDEN_PHRASES"

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

case "$OUTPUT_FORMAT" in
  json|table) ;;
  *) error "--format must be json or table" ;;
esac

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

NORMALIZED_OUTPUT="${MYSQL_OUTPUT//$'\r'/}"
NORMALIZED_OUTPUT="${NORMALIZED_OUTPUT%$'\n'}"
if [[ -z "$NORMALIZED_OUTPUT" ]]; then
  LINE_COUNT=0
else
  LINE_COUNT="$(printf '%s' "$NORMALIZED_OUTPUT" | awk 'END { print NR }')"
fi
ROW_COUNT=$(( LINE_COUNT > 0 ? LINE_COUNT - 1 : 0 ))
(( ROW_COUNT <= MAX_ROWS )) || error "query returned ${ROW_COUNT} rows, exceeding --max-rows=${MAX_ROWS}"

if [[ "$OUTPUT_FORMAT" == "table" ]]; then
  printf '%s\n' "$MYSQL_OUTPUT"
  exit 0
fi

printf '%s\n' "$MYSQL_OUTPUT" | perl -MJSON::PP -e '
my $query = shift @ARGV;
my $content = do { local $/; <STDIN> };
$content = "" unless defined $content;
$content =~ s/\r\n/\n/g;
$content =~ s/\r/\n/g;
$content =~ s/\n\z//;
my @lines = length($content) ? split(/\n/, $content, -1) : ();
my @columns = ();
my @rows = ();
if (@lines) {
  @columns = split(/\t/, shift @lines, -1);
  for my $line (@lines) {
    my @vals = split(/\t/, $line, -1);
    my %row;
    for my $i (0 .. $#columns) {
      $row{$columns[$i]} = defined $vals[$i] ? $vals[$i] : q{};
    }
    push @rows, \%row;
  }
}
my %out = (
  query => $query,
  row_count => scalar(@rows),
  columns => \@columns,
  rows => \@rows,
);
print JSON::PP->new->utf8->pretty->encode(\%out);
' "$FINAL_QUERY"
