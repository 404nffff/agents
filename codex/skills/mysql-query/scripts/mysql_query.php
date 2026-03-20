#!/usr/bin/env php
<?php
declare(strict_types=1);

const MAX_LIMIT = 1000;
const DEFAULT_LIMIT = 100;
const DEFAULT_MAX_ROWS = 2000;
const DEFAULT_SQL_ALLOWED_START = ['select', 'show', 'desc', 'describe', 'explain', 'with'];
const DEFAULT_SQL_FORBIDDEN_KEYWORDS = [
    'delete', 'insert', 'update', 'replace', 'truncate', 'drop', 'alter', 'create',
    'grant', 'revoke', 'rename', 'merge', 'call',
];
const DEFAULT_SQL_FORBIDDEN_PHRASES = [
    'into outfile', 'into dumpfile', 'load data', 'lock tables', 'unlock tables',
];

function usage(): void
{
    $text = <<<TXT
Usage:
  mysql_query.php [options]

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
TXT;
    fwrite(STDOUT, $text . PHP_EOL);
}

function fail(string $message): void
{
    fwrite(STDERR, "ERROR: {$message}" . PHP_EOL);
    exit(1);
}

function startsWith(string $text, string $prefix): bool
{
    return substr($text, 0, strlen($prefix)) === $prefix;
}

function endsWith(string $text, string $suffix): bool
{
    if ($suffix === '') {
        return true;
    }
    return substr($text, -strlen($suffix)) === $suffix;
}

function expandEnvRefs(string $value, array $vars): string
{
    $expanded = preg_replace_callback(
        '/\$(\{)?([A-Za-z_][A-Za-z0-9_]*)(?(1)\})/',
        function (array $match) use ($vars): string {
            $name = $match[2];
            if (array_key_exists($name, $vars)) {
                return (string) $vars[$name];
            }
            $env = getenv($name);
            return $env === false ? '' : (string) $env;
        },
        $value
    );

    return $expanded === null ? $value : $expanded;
}

function isIdentifier(string $value): bool
{
    return (bool) preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $value);
}

function isProfileName(string $value): bool
{
    return (bool) preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $value);
}

function parseArgs(array $argv): array
{
    $scriptDir = dirname(__DIR__);
    $opts = [
        'config_path' => $scriptDir . '/config.env',
        'profile' => '',
        'host' => '',
        'port' => '',
        'user' => '',
        'password' => '',
        'database' => '',
        'socket' => '',
        'timeout' => '',
        'query' => '',
        'table' => '',
        'columns' => '*',
        'where' => '',
        'order_by' => '',
        'limit' => (string) DEFAULT_LIMIT,
        'max_rows' => (string) DEFAULT_MAX_ROWS,
        'format' => 'json',
    ];

    $expectValueFor = null;
    $map = [
        '--profile' => 'profile',
        '--host' => 'host',
        '--port' => 'port',
        '--user' => 'user',
        '--password' => 'password',
        '--database' => 'database',
        '--socket' => 'socket',
        '--timeout' => 'timeout',
        '--query' => 'query',
        '--table' => 'table',
        '--columns' => 'columns',
        '--where' => 'where',
        '--order-by' => 'order_by',
        '--limit' => 'limit',
        '--max-rows' => 'max_rows',
        '--format' => 'format',
    ];

    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($expectValueFor !== null) {
            $opts[$expectValueFor] = (string) $arg;
            $expectValueFor = null;
            continue;
        }

        if ($arg === '-h' || $arg === '--help') {
            usage();
            exit(0);
        }

        if (!array_key_exists($arg, $map)) {
            fail("unknown argument: {$arg}");
        }

        $expectValueFor = $map[$arg];
    }

    if ($expectValueFor !== null) {
        fail("missing value for --" . str_replace('_', '-', $expectValueFor));
    }

    return $opts;
}

function loadEnvFile(string $path): array
{
    if (!is_file($path)) {
        fail("config file not found: {$path}");
    }

    $lines = file($path, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        fail("unable to read config file: {$path}");
    }

    $vars = [];
    foreach ($lines as $line) {
        $trimmed = trim($line);
        if ($trimmed === '' || startsWith($trimmed, '#')) {
            continue;
        }

        if (startsWith($trimmed, 'export ')) {
            $trimmed = trim(substr($trimmed, 7));
        }

        $pos = strpos($trimmed, '=');
        if ($pos === false) {
            continue;
        }

        $key = trim(substr($trimmed, 0, $pos));
        $rawVal = trim(substr($trimmed, $pos + 1));
        if ($key === '') {
            continue;
        }

        $doubleQuoted = startsWith($rawVal, '"') && endsWith($rawVal, '"');
        $singleQuoted = startsWith($rawVal, "'") && endsWith($rawVal, "'");

        if ($doubleQuoted || $singleQuoted) {
            $val = substr($rawVal, 1, -1);
        } else {
            $withoutComment = preg_replace('/\s+#.*$/', '', $rawVal);
            $val = trim($withoutComment === null ? $rawVal : $withoutComment);
        }

        if (!$singleQuoted) {
            $val = expandEnvRefs($val, $vars);
        }

        $vars[$key] = $val;
    }

    return $vars;
}

function getProfileValue(array $envVars, string $key, string $profile): string
{
    $profileKey = $key . '_' . $profile;
    return (string) ($envVars[$profileKey] ?? '');
}

function resolveConnection(array $opts, array $envVars): array
{
    $profile = $opts['profile'] !== '' ? $opts['profile'] : (string) ($envVars['MYSQL_PROFILE'] ?? '');
    $profileVals = [
        'host' => '',
        'port' => '',
        'user' => '',
        'password' => '',
        'database' => '',
        'socket' => '',
        'timeout' => '',
    ];

    if ($profile !== '') {
        if (!isProfileName($profile)) {
            fail("invalid --profile name: {$profile}");
        }

        $profileVals = [
            'host' => getProfileValue($envVars, 'MYSQL_HOST', $profile),
            'port' => getProfileValue($envVars, 'MYSQL_PORT', $profile),
            'user' => getProfileValue($envVars, 'MYSQL_USER', $profile),
            'password' => getProfileValue($envVars, 'MYSQL_PASSWORD', $profile),
            'database' => getProfileValue($envVars, 'MYSQL_DATABASE', $profile),
            'socket' => getProfileValue($envVars, 'MYSQL_SOCKET', $profile),
            'timeout' => getProfileValue($envVars, 'MYSQL_TIMEOUT', $profile),
        ];

        $allEmpty = true;
        foreach ($profileVals as $val) {
            if ($val !== '') {
                $allEmpty = false;
                break;
            }
        }
        if ($allEmpty) {
            fail("profile not found: {$profile}");
        }
    }

    $hasCliConn = $opts['host'] !== '' ||
        $opts['port'] !== '' ||
        $opts['user'] !== '' ||
        $opts['password'] !== '' ||
        $opts['database'] !== '' ||
        $opts['socket'] !== '' ||
        $opts['timeout'] !== '';

    if ($profile === '' && !$hasCliConn) {
        fail('profile is required: pass --profile or set MYSQL_PROFILE');
    }

    return [
        'host' => $opts['host'] !== '' ? $opts['host'] : $profileVals['host'],
        'port' => $opts['port'] !== '' ? $opts['port'] : $profileVals['port'],
        'user' => $opts['user'] !== '' ? $opts['user'] : $profileVals['user'],
        'password' => $opts['password'] !== '' ? $opts['password'] : $profileVals['password'],
        'database' => $opts['database'] !== '' ? $opts['database'] : $profileVals['database'],
        'socket' => $opts['socket'] !== '' ? $opts['socket'] : $profileVals['socket'],
        'timeout' => $opts['timeout'] !== '' ? $opts['timeout'] : $profileVals['timeout'],
    ];
}

function normalizeSql(string $sql): string
{
    $noBlock = preg_replace('/\/\*.*?\*\//s', ' ', $sql);
    $noDash = preg_replace('/--[^\n]*/', ' ', (string) $noBlock);
    $noHash = preg_replace('/#[^\n]*/', ' ', (string) $noDash);
    $normalized = trim((string) $noHash);
    $normalized = rtrim($normalized, ';');
    return trim($normalized);
}

function normalizeSpacesLower(string $value): string
{
    $normalized = preg_replace('/\s+/', ' ', strtolower(trim($value)));
    return trim((string) $normalized);
}

function parseKeywordCsv(string $raw): array
{
    if (trim($raw) === '') {
        return [];
    }
    $items = explode(',', $raw);
    $out = [];
    foreach ($items as $item) {
        $normalized = normalizeSpacesLower($item);
        if ($normalized === '') {
            continue;
        }
        if (!preg_match('/^[a-z_][a-z0-9_]*$/', $normalized)) {
            continue;
        }
        if (!in_array($normalized, $out, true)) {
            $out[] = $normalized;
        }
    }
    return $out;
}

function parsePhraseCsv(string $raw): array
{
    if (trim($raw) === '') {
        return [];
    }
    $items = explode(',', $raw);
    $out = [];
    foreach ($items as $item) {
        $normalized = str_replace('_', ' ', strtolower(trim($item)));
        $normalized = normalizeSpacesLower($normalized);
        if ($normalized === '') {
            continue;
        }
        if (!in_array($normalized, $out, true)) {
            $out[] = $normalized;
        }
    }
    return $out;
}

function buildValidationRules(array $envVars): array
{
    $allowedStart = parseKeywordCsv((string) ($envVars['MYSQL_SQL_ALLOWED_START'] ?? ''));
    if (count($allowedStart) === 0) {
        $allowedStart = DEFAULT_SQL_ALLOWED_START;
    }

    $forbiddenKeywords = parseKeywordCsv((string) ($envVars['MYSQL_SQL_FORBIDDEN_KEYWORDS'] ?? ''));
    if (count($forbiddenKeywords) === 0) {
        $forbiddenKeywords = DEFAULT_SQL_FORBIDDEN_KEYWORDS;
    }

    $forbiddenPhrases = parsePhraseCsv((string) ($envVars['MYSQL_SQL_FORBIDDEN_PHRASES'] ?? ''));
    if (count($forbiddenPhrases) === 0) {
        $forbiddenPhrases = DEFAULT_SQL_FORBIDDEN_PHRASES;
    }

    return [
        'allowed_start' => $allowedStart,
        'forbidden_keywords' => $forbiddenKeywords,
        'forbidden_phrases' => $forbiddenPhrases,
    ];
}

function validateSql(string $sql, array $rules): string
{
    $normalized = normalizeSql($sql);
    if ($normalized === '') {
        fail('query is empty after normalization');
    }
    if (strpos($normalized, ';') !== false) {
        fail('multiple SQL statements are not allowed');
    }

    $lower = strtolower($normalized);
    $allowShowCreate = preg_match('/^show\s+create\b/i', $lower) === 1;
    $parts = preg_split('/\s+/', $lower);
    $first = $parts[0] ?? '';
    $allowed = $rules['allowed_start'];
    if (!in_array($first, $allowed, true)) {
        fail('only read-only SQL is allowed (allowed starts: ' . strtoupper(implode('/', $allowed)) . ')');
    }

    $forbiddenKeywords = $rules['forbidden_keywords'];
    foreach ($forbiddenKeywords as $keyword) {
        if ($keyword === 'create' && $allowShowCreate) {
            continue;
        }
        if (preg_match('/\b' . preg_quote($keyword, '/') . '\b/i', $lower)) {
            fail("forbidden SQL keyword detected: {$keyword}");
        }
    }

    $compactSql = normalizeSpacesLower($lower);
    foreach ($rules['forbidden_phrases'] as $phrase) {
        if ($phrase !== '' && strpos($compactSql, $phrase) !== false) {
            fail('forbidden SQL pattern detected: ' . strtoupper($phrase));
        }
    }

    return $normalized;
}

function parsePositiveInt(string $value, string $name): int
{
    if (!preg_match('/^[0-9]+$/', $value)) {
        fail("{$name} must be a positive integer");
    }
    $n = (int) $value;
    if ($n <= 0) {
        fail("{$name} must be greater than 0");
    }
    return $n;
}

function parseOptionalPositiveInt(string $value, string $name): int
{
    if (trim($value) === '') {
        return 0;
    }
    return parsePositiveInt($value, $name);
}

function buildStructuredQuery(array $opts, int $limit): string
{
    $table = trim($opts['table']);
    if ($table === '') {
        fail('either --query or --table is required');
    }
    if (!isIdentifier($table)) {
        fail("invalid table: {$table}");
    }

    $columns = trim($opts['columns']);
    if ($columns === '*') {
        $selectExpr = '*';
    } else {
        $parts = array_filter(array_map('trim', explode(',', $columns)), function ($s) {
            return $s !== '';
        });
        if (count($parts) === 0) {
            fail('columns cannot be empty');
        }
        $quoted = [];
        foreach ($parts as $col) {
            if (!isIdentifier($col)) {
                fail("invalid column: {$col}");
            }
            $quoted[] = "`{$col}`";
        }
        $selectExpr = implode(', ', $quoted);
    }

    $query = "SELECT {$selectExpr} FROM `{$table}`";
    if (trim($opts['where']) !== '') {
        $query .= ' WHERE ' . $opts['where'];
    }
    if (trim($opts['order_by']) !== '') {
        $query .= ' ORDER BY ' . $opts['order_by'];
    }
    $query .= " LIMIT {$limit}";

    return $query;
}

function tsvEncodeValue($value): string
{
    if ($value === null) {
        return '\N';
    }
    return (string) $value;
}

function renderTsvOutput(array $columns, array $rows): string
{
    if (count($columns) === 0) {
        return '';
    }

    $lines = [implode("\t", $columns)];
    foreach ($rows as $row) {
        $vals = [];
        foreach ($columns as $col) {
            $vals[] = tsvEncodeValue($row[$col] ?? null);
        }
        $lines[] = implode("\t", $vals);
    }

    return implode("\n", $lines) . "\n";
}

function runMysql(array $conn, string $query): array
{
    if (!function_exists('mysqli_init')) {
        fail('mysqli extension is required');
    }

    mysqli_report(MYSQLI_REPORT_OFF);
    $mysql = mysqli_init();
    if ($mysql === false) {
        fail('failed to initialize mysqli');
    }

    $timeout = parseOptionalPositiveInt((string) $conn['timeout'], '--timeout');
    if ($timeout > 0 && !mysqli_options($mysql, MYSQLI_OPT_CONNECT_TIMEOUT, $timeout)) {
        mysqli_close($mysql);
        fail('failed to apply mysql connection timeout');
    }

    $port = parseOptionalPositiveInt((string) $conn['port'], '--port');
    $host = (string) ($conn['host'] ?? '');
    $user = (string) ($conn['user'] ?? '');
    $password = (string) ($conn['password'] ?? '');
    $database = (string) ($conn['database'] ?? '');
    $socket = (string) ($conn['socket'] ?? '');

    $connected = mysqli_real_connect($mysql, $host, $user, $password, $database, $port, $socket);
    if ($connected !== true) {
        $error = trim((string) mysqli_connect_error());
        mysqli_close($mysql);
        fail($error !== '' ? $error : 'mysql connection failed');
    }

    if (!mysqli_set_charset($mysql, 'utf8mb4')) {
        $error = trim(mysqli_error($mysql));
        mysqli_close($mysql);
        fail($error !== '' ? $error : 'failed to set mysql charset utf8mb4');
    }

    $result = mysqli_query($mysql, $query, MYSQLI_STORE_RESULT);
    if ($result === false) {
        $error = trim(mysqli_error($mysql));
        mysqli_close($mysql);
        fail($error !== '' ? $error : 'mysql query failed');
    }
    if ($result === true) {
        mysqli_close($mysql);
        return ['columns' => [], 'rows' => [], 'table_output' => ''];
    }

    $fields = mysqli_fetch_fields($result);
    $columns = [];
    foreach ($fields as $field) {
        $columns[] = $field->name;
    }

    $rows = [];
    while (($vals = mysqli_fetch_row($result)) !== null) {
        $row = [];
        foreach ($columns as $idx => $col) {
            $row[$col] = array_key_exists($idx, $vals) ? $vals[$idx] : null;
        }
        $rows[] = $row;
    }
    mysqli_free_result($result);
    mysqli_close($mysql);

    return [
        'columns' => $columns,
        'rows' => $rows,
        'table_output' => renderTsvOutput($columns, $rows),
    ];
}

$opts = parseArgs($argv);
$envVars = loadEnvFile($opts['config_path']);
$validationRules = buildValidationRules($envVars);
$conn = resolveConnection($opts, $envVars);

$limit = parsePositiveInt($opts['limit'], '--limit');
if ($limit > MAX_LIMIT) {
    fail('--limit cannot exceed ' . MAX_LIMIT);
}
$maxRows = parsePositiveInt($opts['max_rows'], '--max-rows');
$outputFormat = strtolower(trim($opts['format']));
if (!in_array($outputFormat, ['json', 'table'], true)) {
    fail('--format must be json or table');
}

$queryInput = trim($opts['query']);
if ($queryInput !== '') {
    $finalQuery = validateSql($queryInput, $validationRules);
} else {
    $structuredQuery = buildStructuredQuery($opts, $limit);
    $finalQuery = validateSql($structuredQuery, $validationRules);
}

$result = runMysql($conn, $finalQuery);
$rowCount = count($result['rows']);
if ($rowCount > $maxRows) {
    fail("query returned {$rowCount} rows, exceeding --max-rows={$maxRows}");
}

if ($outputFormat === 'table') {
    fwrite(STDOUT, $result['table_output']);
    exit(0);
}

$payload = [
    'query' => $finalQuery,
    'row_count' => $rowCount,
    'columns' => $result['columns'],
    'rows' => $result['rows'],
];
$json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
if ($json === false) {
    fail('failed to encode JSON output');
}
fwrite(STDOUT, $json . PHP_EOL);
