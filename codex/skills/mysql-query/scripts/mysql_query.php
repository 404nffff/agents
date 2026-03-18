#!/usr/bin/env php
<?php
declare(strict_types=1);

const MAX_LIMIT = 1000;
const DEFAULT_LIMIT = 100;
const DEFAULT_MAX_ROWS = 2000;

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

function validateSql(string $sql): string
{
    $normalized = normalizeSql($sql);
    if ($normalized === '') {
        fail('query is empty after normalization');
    }
    if (strpos($normalized, ';') !== false) {
        fail('multiple SQL statements are not allowed');
    }

    $lower = strtolower($normalized);
    $parts = preg_split('/\s+/', $lower);
    $first = $parts[0] ?? '';
    $allowed = ['select', 'show', 'desc', 'describe', 'explain', 'with'];
    if (!in_array($first, $allowed, true)) {
        fail('only read-only SQL is allowed (SELECT/SHOW/DESC/DESCRIBE/EXPLAIN/WITH)');
    }

    $forbiddenKeywords = [
        'delete', 'insert', 'update', 'replace', 'truncate', 'drop', 'alter', 'create',
        'grant', 'revoke', 'rename', 'merge', 'call',
    ];
    foreach ($forbiddenKeywords as $keyword) {
        if (preg_match('/\b' . preg_quote($keyword, '/') . '\b/i', $lower)) {
            fail("forbidden SQL keyword detected: {$keyword}");
        }
    }

    $forbiddenPatterns = [
        '/\binto\s+outfile\b/i' => 'INTO OUTFILE',
        '/\binto\s+dumpfile\b/i' => 'INTO DUMPFILE',
        '/\bload\s+data\b/i' => 'LOAD DATA',
        '/\block\s+tables?\b/i' => 'LOCK TABLES',
        '/\bunlock\s+tables?\b/i' => 'UNLOCK TABLES',
    ];
    foreach ($forbiddenPatterns as $pattern => $label) {
        if (preg_match($pattern, $lower)) {
            fail("forbidden SQL pattern detected: {$label}");
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

function shellJoin(array $parts): string
{
    return implode(' ', array_map('escapeshellarg', $parts));
}

function runMysql(array $conn, string $query): array
{
    $cmd = ['mysql', '--batch', '--raw', '--default-character-set=utf8mb4'];

    if ($conn['host'] !== '') {
        $cmd[] = '--host';
        $cmd[] = $conn['host'];
    }
    if ($conn['port'] !== '') {
        $cmd[] = '--port';
        $cmd[] = $conn['port'];
    }
    if ($conn['user'] !== '') {
        $cmd[] = '--user';
        $cmd[] = $conn['user'];
    }
    if ($conn['socket'] !== '') {
        $cmd[] = '--socket';
        $cmd[] = $conn['socket'];
    }
    if ($conn['timeout'] !== '') {
        $cmd[] = '--connect-timeout';
        $cmd[] = $conn['timeout'];
    }
    if ($conn['database'] !== '') {
        $cmd[] = $conn['database'];
    }
    $cmd[] = '--execute';
    $cmd[] = $query;

    $descriptorSpec = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $env = $_ENV;
    if ($conn['password'] !== '') {
        $env['MYSQL_PWD'] = $conn['password'];
    }

    $process = proc_open(shellJoin($cmd), $descriptorSpec, $pipes, null, $env);
    if (!is_resource($process)) {
        fail('failed to execute mysql command');
    }

    fclose($pipes[0]);
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);

    $exitCode = proc_close($process);
    return [
        'exit_code' => $exitCode,
        'stdout' => $stdout !== false ? $stdout : '',
        'stderr' => $stderr !== false ? $stderr : '',
    ];
}

function countResultRows(string $output): int
{
    $lines = preg_split('/\R/', $output);
    $nonEmpty = 0;
    foreach ($lines as $line) {
        if (trim((string) $line) !== '') {
            $nonEmpty++;
        }
    }
    return max($nonEmpty - 1, 0);
}

$opts = parseArgs($argv);
$envVars = loadEnvFile($opts['config_path']);
$conn = resolveConnection($opts, $envVars);

$limit = parsePositiveInt($opts['limit'], '--limit');
if ($limit > MAX_LIMIT) {
    fail('--limit cannot exceed ' . MAX_LIMIT);
}
$maxRows = parsePositiveInt($opts['max_rows'], '--max-rows');

$queryInput = trim($opts['query']);
if ($queryInput !== '') {
    $finalQuery = validateSql($queryInput);
} else {
    $structuredQuery = buildStructuredQuery($opts, $limit);
    $finalQuery = validateSql($structuredQuery);
}

$result = runMysql($conn, $finalQuery);
if ($result['exit_code'] !== 0) {
    $message = trim($result['stderr']) !== '' ? trim($result['stderr']) : trim($result['stdout']);
    if ($message === '') {
        $message = 'mysql command failed';
    }
    fail($message);
}

$rowCount = countResultRows($result['stdout']);
if ($rowCount > $maxRows) {
    fail("query returned {$rowCount} rows, exceeding --max-rows={$maxRows}");
}

fwrite(STDOUT, $result['stdout']);
