#!/usr/bin/env php
<?php
declare(strict_types=1);

function stderr(string $message): void
{
    fwrite(STDERR, $message . PHP_EOL);
}

function fail(string $message, int $exitCode = 1): void
{
    stderr('ERROR: ' . $message);
    exit($exitCode);
}

function normalizeText(string $value): string
{
    $value = str_replace(["\r\n", "\r"], "\n", str_replace("\\n", "\n", $value));
    return trim($value);
}

function getOptionValue(array $options, string $key): string
{
    if (!array_key_exists($key, $options)) {
        return '';
    }
    $value = $options[$key];
    if (is_array($value)) {
        $value = end($value);
    }
    return is_string($value) ? normalizeText($value) : '';
}

function hasFlag(array $options, string $key): bool
{
    return array_key_exists($key, $options);
}

function envValue(string $key): string
{
    $value = getenv($key);
    return is_string($value) ? normalizeText($value) : '';
}

function loadDotEnvFile(string $path): void
{
    if (!is_file($path)) {
        return;
    }

    $lines = @file($path, FILE_IGNORE_NEW_LINES);
    if (!is_array($lines)) {
        fail("cannot read env file: {$path}");
    }

    foreach ($lines as $line) {
        $text = trim((string) $line);
        if ($text === '' || strpos($text, '#') === 0 || strpos($text, '=') === false) {
            continue;
        }

        [$key, $value] = explode('=', $text, 2);
        $key = trim($key);
        $value = trim($value);
        if ($key === '' || getenv($key) !== false) {
            continue;
        }

        if (
            strlen($value) >= 2 &&
            (($value[0] === '"' && substr($value, -1) === '"') || ($value[0] === "'" && substr($value, -1) === "'"))
        ) {
            $value = substr($value, 1, -1);
        }

        // 只写入当前进程环境，避免把用户密钥输出到日志、提交信息或项目文件。
        putenv($key . '=' . $value);
        $_ENV[$key] = $value;
    }
}

function pickFirst(string ...$values): string
{
    foreach ($values as $value) {
        $text = normalizeText($value);
        if ($text !== '') {
            return $text;
        }
    }
    return '';
}

function resolveProjectDir(string $projectDir): string
{
    if ($projectDir === '') {
        $projectDir = getcwd() ?: '.';
    }
    $realPath = realpath($projectDir);
    if ($realPath === false || !is_dir($realPath)) {
        fail("project dir not found: {$projectDir}");
    }
    return rtrim($realPath, "/\\");
}

function windowsShellArg(string $value): string
{
    if (preg_match('/^[A-Za-z0-9_\-\.\/\\\\:=]+$/u', $value) === 1) {
        return $value;
    }
    return '"' . str_replace('"', '\"', $value) . '"';
}

function shellCommand(array $command): string
{
    $parts = [];
    foreach ($command as $part) {
        $value = (string) $part;
        $parts[] = PHP_OS_FAMILY === 'Windows' ? windowsShellArg($value) : escapeshellarg($value);
    }
    return implode(' ', $parts);
}

function runProcess(array $command, string $cwd): array
{
    $descriptorSpec = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];
    $process = proc_open(shellCommand($command), $descriptorSpec, $pipes, $cwd);
    if (!is_resource($process)) {
        fail('cannot start process: ' . implode(' ', $command));
    }
    fclose($pipes[0]);
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($process);

    return [
        'exitCode' => $exitCode,
        'stdout' => is_string($stdout) ? $stdout : '',
        'stderr' => is_string($stderr) ? $stderr : '',
    ];
}

function gitOutput(array $args, string $projectDir): string
{
    $result = runProcess(array_merge(['git'], $args), $projectDir);
    if ((int) $result['exitCode'] !== 0) {
        fail('git command failed: ' . normalizeText((string) $result['stderr']));
    }
    return normalizeText((string) $result['stdout']);
}

function gitLogOutput(string $projectDir): string
{
    $result = runProcess(['git', 'log', '--oneline', '-10'], $projectDir);
    if ((int) $result['exitCode'] !== 0) {
        $message = normalizeText((string) $result['stderr']);
        if (strpos($message, 'does not have any commits yet') !== false) {
            return '';
        }
        fail('git log failed: ' . $message);
    }
    return normalizeText((string) $result['stdout']);
}

function stagedFiles(string $projectDir): array
{
    $output = gitOutput(['diff', '--cached', '--name-only'], $projectDir);
    if ($output === '') {
        return [];
    }
    return array_values(array_filter(preg_split('/\R/u', $output) ?: [], static function (string $path): bool {
        return !in_array(basename($path), ['pnpm-lock.yaml', 'package-lock.json', 'yarn.lock', 'bun.lockb'], true);
    }));
}

function stagedContext(string $projectDir): array
{
    $exclude = [
        ':(exclude)pnpm-lock.yaml',
        ':(exclude)package-lock.json',
        ':(exclude)yarn.lock',
        ':(exclude)bun.lockb',
    ];
    $stat = gitOutput(array_merge(['diff', '--cached', '--stat', '--'], $exclude), $projectDir);
    $diff = gitOutput(array_merge(['diff', '--cached', '--', '.'], $exclude), $projectDir);
    $log = gitLogOutput($projectDir);

    return [
        'stat' => mb_substr($stat, 0, 4000),
        'diff' => mb_substr($diff, 0, 12000),
        'log' => $log,
    ];
}

function classifyGitmoji(array $files, string $diff): string
{
    $joined = implode("\n", $files);
    if (preg_match('/(^|\/)(README|docs\/|.*\.md$)/iu', $joined) === 1) {
        return ':memo:';
    }
    if (preg_match('/(^|\/)(tests?|__tests__)\/|\.test\.|\.spec\./iu', $joined) === 1) {
        return ':white_check_mark:';
    }
    if (preg_match('/(^|\/)(Dockerfile|docker|docker-compose\.ya?ml)/iu', $joined) === 1) {
        return ':whale:';
    }
    if (preg_match('/(^|\/)(AGENTS\.md|\.env\.example|.*\.ya?ml$|.*\.json$)/iu', $joined) === 1) {
        return ':wrench:';
    }
    if (preg_match('/^deleted file mode/mu', $diff) === 1) {
        return ':fire:';
    }
    return ':sparkles:';
}

function moduleName(array $files): string
{
    foreach ($files as $file) {
        $path = str_replace('\\', '/', $file);
        $parts = array_values(array_filter(explode('/', $path), static function (string $part): bool {
            return $part !== '';
        }));
        if (count($parts) >= 2) {
            return $parts[0] . '/' . $parts[1];
        }
        if (count($parts) === 1) {
            return $parts[0];
        }
    }
    return '暂存变更';
}

function localCommitTitle(array $files, string $diff): string
{
    $emoji = classifyGitmoji($files, $diff);
    $module = moduleName($files);
    if (strpos(implode("\n", $files), 'skills/git-commit-helper') !== false) {
        return "{$emoji} 增强 git-commit-helper 的第三方 AI 提交标题润色能力";
    }
    if (preg_match('/^new file mode/mu', $diff) === 1) {
        return "{$emoji} 新增 {$module} 相关能力与配套说明";
    }
    if (preg_match('/^deleted file mode/mu', $diff) === 1) {
        return "{$emoji} 清理 {$module} 过时文件与无效实现";
    }
    return "{$emoji} 更新 {$module} 相关实现与文档说明";
}

function normalizeAiUrl(string $url): string
{
    $url = rtrim($url, "/ \t\n\r\0\x0B");
    if ($url === '') {
        return '';
    }
    if (preg_match('#/v1/chat/completions?$#u', $url) === 1) {
        return $url;
    }
    return $url . '/v1/chat/completions';
}

function shouldUseAi(array $options, string $url, string $model, string $key): bool
{
    if (hasFlag($options, 'no-ai')) {
        return false;
    }
    return $url !== '' || $model !== '' || $key !== '';
}

function sanitizeTitle(string $title): string
{
    $lines = preg_split('/\R/u', normalizeText($title));
    $first = '';
    foreach ($lines ?: [] as $line) {
        $text = trim((string) $line);
        if ($text !== '') {
            $first = $text;
            break;
        }
    }
    $first = trim($first, " \t\n\r\0\x0B`\"'");
    return preg_replace('/\s+/u', ' ', $first) ?? $first;
}

function assertUsefulTitle(string $title): void
{
    $plain = preg_replace('/^:[a-z0-9_+-]+:\s*/iu', '', $title) ?? $title;
    if (mb_strlen($plain) < 16) {
        fail('AI commit title is too short; expected a concrete title with module and change intent');
    }
    if (mb_strlen($title) > 90) {
        fail('AI commit title is too long; keep it as one concise commit subject');
    }
}

function polishWithOpenAi(string $localTitle, array $files, array $context, string $url, string $model, string $key): string
{
    if ($url === '' || $model === '' || $key === '') {
        fail('AI title polish requires API_URL, MODEL and API_KEY');
    }

    $prompt = "请基于暂存区变更润色 Git 提交标题，只输出一行标题。\n" .
        "要求：沿用历史提交风格；优先使用合适 GitMoji；中文标题不要太短，需包含模块和具体变更意图；长度建议 18-72 个中文字符；不要解释。\n\n" .
        "【本地初稿】\n{$localTitle}\n\n" .
        "【暂存文件】\n" . implode("\n", $files) . "\n\n" .
        "【变更统计】\n{$context['stat']}\n\n" .
        "【关键 diff】\n{$context['diff']}\n\n" .
        "【最近提交】\n{$context['log']}";

    $payload = json_encode([
        'model' => $model,
        'messages' => [
            [
                'role' => 'system',
                'content' => '你是 Git 提交信息编辑器，只输出一行提交标题。',
            ],
            [
                'role' => 'user',
                'content' => mb_substr($prompt, 0, 18000),
            ],
        ],
        'temperature' => 0.2,
    ], JSON_UNESCAPED_UNICODE);
    if (!is_string($payload)) {
        fail('cannot encode AI request payload');
    }

    $httpContext = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => implode("\r\n", [
                'Content-Type: application/json',
                'Authorization: Bearer ' . $key,
            ]),
            'content' => $payload,
            'timeout' => 90,
            'ignore_errors' => true,
        ],
    ]);
    $response = @file_get_contents($url, false, $httpContext);
    if ($response === false) {
        fail("AI title polish request failed: {$url}");
    }

    $statusLine = $http_response_header[0] ?? '';
    if (is_string($statusLine) && preg_match('/\s([45]\d\d)\s/u', $statusLine, $m) === 1) {
        fail("AI title polish HTTP {$m[1]}: " . mb_substr(normalizeText($response), 0, 500));
    }

    $data = json_decode($response, true);
    if (!is_array($data)) {
        fail('AI title polish response is not JSON');
    }
    $content = $data['choices'][0]['message']['content'] ?? '';
    if (!is_string($content) || normalizeText($content) === '') {
        fail('AI title polish response missing choices[0].message.content');
    }
    $title = sanitizeTitle($content);
    assertUsefulTitle($title);
    return $title;
}

$options = getopt('', [
    'project-dir:',
    'ai-url:',
    'ai-model:',
    'ai-key:',
    'no-ai',
]);
if (!is_array($options)) {
    fail('invalid options');
}

loadDotEnvFile(__DIR__ . DIRECTORY_SEPARATOR . '.env');

$projectDir = resolveProjectDir(getOptionValue($options, 'project-dir'));
$files = stagedFiles($projectDir);
if (count($files) === 0) {
    fail('no staged files found; run git add first');
}

$context = stagedContext($projectDir);
$title = localCommitTitle($files, $context['diff']);

$aiUrl = pickFirst(getOptionValue($options, 'ai-url'), envValue('API_URL'));
$aiModel = pickFirst(getOptionValue($options, 'ai-model'), envValue('MODEL'));
$aiKey = pickFirst(getOptionValue($options, 'ai-key'), envValue('API_KEY'));

if (shouldUseAi($options, $aiUrl, $aiModel, $aiKey)) {
    $title = polishWithOpenAi($title, $files, $context, normalizeAiUrl($aiUrl), $aiModel, $aiKey);
}

echo sanitizeTitle($title) . PHP_EOL;
