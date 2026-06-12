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

function decodeEscapedNewline(string $value): string
{
    return str_replace("\\n", "\n", $value);
}

function normalizeText(string $value): string
{
    $value = str_replace(["\r\n", "\r"], "\n", decodeEscapedNewline($value));
    return trim($value);
}

function stdinIsTty(): bool
{
    if (function_exists('stream_isatty')) {
        return (bool) @stream_isatty(STDIN);
    }
    if (function_exists('posix_isatty')) {
        return (bool) @posix_isatty(STDIN);
    }
    return true;
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

function getOptionValues(array $options, string $key): array
{
    if (!array_key_exists($key, $options)) {
        return [];
    }
    $value = $options[$key];
    $items = is_array($value) ? $value : [$value];
    $result = [];
    foreach ($items as $item) {
        if (!is_string($item)) {
            continue;
        }
        $text = normalizeText($item);
        if ($text !== '') {
            $result[] = $text;
        }
    }
    return $result;
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
            (strlen($value) >= 2) &&
            (($value[0] === '"' && substr($value, -1) === '"') || ($value[0] === "'" && substr($value, -1) === "'"))
        ) {
            $value = substr($value, 1, -1);
        }

        // 只写入当前进程环境，避免把用户配置输出到日志或项目文件。
        putenv($key . '=' . $value);
        $_ENV[$key] = $value;
    }
}

function loadScriptEnv(): void
{
    $scriptDir = __DIR__;
    loadDotEnvFile($scriptDir . DIRECTORY_SEPARATOR . '.env');
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

function listDocsRequirementDirs(string $projectDir): array
{
    $docsDir = $projectDir . DIRECTORY_SEPARATOR . 'docs';
    if (!is_dir($docsDir)) {
        return [];
    }

    $items = scandir($docsDir);
    if ($items === false) {
        fail("cannot scan docs dir: {$docsDir}");
    }

    $ignored = ['.', '..', 'day-log'];
    $dirs = [];
    foreach ($items as $item) {
        if (in_array($item, $ignored, true)) {
            continue;
        }
        $path = $docsDir . DIRECTORY_SEPARATOR . $item;
        if (is_dir($path)) {
            $dirs[] = $item;
        }
    }
    sort($dirs, SORT_NATURAL | SORT_FLAG_CASE);
    return $dirs;
}

function printRequirementDirs(array $dirs): void
{
    if (count($dirs) === 0) {
        echo "未发现 docs 下的需求目录" . PHP_EOL;
        return;
    }
    echo "当前项目 docs 下的需求目录：" . PHP_EOL;
    foreach ($dirs as $index => $dir) {
        echo sprintf("%d. %s", $index + 1, $dir) . PHP_EOL;
    }
}

function chooseTaskDir(array $options, string $projectDir, array $dirs): string
{
    $taskDir = getOptionValue($options, 'task-dir');
    if ($taskDir !== '') {
        $name = basename(str_replace('\\', '/', $taskDir));
        if (!in_array($name, $dirs, true)) {
            fail("task dir not found under docs: {$taskDir}");
        }
        return $name;
    }

    printRequirementDirs($dirs);
    if (count($dirs) === 0) {
        fail('no docs requirement dir found');
    }
    if (stdinIsTty()) {
        echo "请输入目录编号或名称：";
        $input = fgets(STDIN);
        $input = is_string($input) ? trim($input) : '';
        if ($input === '') {
            fail('task dir is required');
        }
        if (ctype_digit($input)) {
            $index = (int) $input - 1;
            if (!isset($dirs[$index])) {
                fail("invalid dir index: {$input}");
            }
            return $dirs[$index];
        }
        if (!in_array($input, $dirs, true)) {
            fail("task dir not found under docs: {$input}");
        }
        return $input;
    }

    fail('task dir is required in non-interactive mode; use --task-dir');
}

function resolveOutputDir(string $outputDir, string $projectDir): string
{
    if ($outputDir === '') {
        return $projectDir . DIRECTORY_SEPARATOR . 'docs' . DIRECTORY_SEPARATOR . 'day-log';
    }
    if (preg_match('/^(?:\/|[A-Za-z]:[\/\\\\])/u', $outputDir) !== 1) {
        $outputDir = $projectDir . DIRECTORY_SEPARATOR . $outputDir;
    }
    return rtrim($outputDir, "/\\");
}

function collectLocalTaskText(string $projectDir, string $taskDir): string
{
    $baseDir = $projectDir . DIRECTORY_SEPARATOR . 'docs' . DIRECTORY_SEPARATOR . $taskDir;
    if (!is_dir($baseDir)) {
        return '';
    }

    $files = [];
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($baseDir, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iterator as $fileInfo) {
        if (!$fileInfo instanceof SplFileInfo || !$fileInfo->isFile()) {
            continue;
        }
        $path = $fileInfo->getPathname();
        $ext = strtolower((string) pathinfo($path, PATHINFO_EXTENSION));
        if (!in_array($ext, ['md', 'json', 'txt'], true)) {
            continue;
        }
        $normalized = str_replace('\\', '/', $path);
        if (preg_match('#/(sql|node_modules|vendor)/#u', $normalized) === 1) {
            continue;
        }
        $files[] = $path;
    }
    usort($files, static function (string $left, string $right): int {
        $priority = static function (string $path): int {
            $name = basename($path);
            if ($name === 'mini-plan.md') {
                return 10;
            }
            if ($name === 'status.md') {
                return 20;
            }
            if (preg_match('/^00[12]/u', $name) === 1) {
                return 30;
            }
            if (preg_match('/^003/u', $name) === 1) {
                return 40;
            }
            return 90;
        };
        $diff = $priority($left) <=> $priority($right);
        return $diff !== 0 ? $diff : strnatcasecmp($left, $right);
    });

    $chunks = [];
    foreach (array_slice($files, 0, 12) as $path) {
        $content = @file_get_contents($path);
        if ($content === false) {
            continue;
        }
        $relative = str_replace($projectDir . DIRECTORY_SEPARATOR, '', $path);
        $chunks[] = "### {$relative}\n" . mb_substr(normalizeText($content), 0, 2500);
    }
    return implode("\n\n", $chunks);
}

function defaultAiLocalbaseScript(): string
{
    $home = getenv('HOME');
    if (!is_string($home) || $home === '') {
        $home = getenv('USERPROFILE') ?: '';
    }
    if ($home === '') {
        return '';
    }
    $base = rtrim($home, "/\\") . DIRECTORY_SEPARATOR . '.codex' . DIRECTORY_SEPARATOR . 'skills' . DIRECTORY_SEPARATOR . 'ai-localbase';
    if (PHP_OS_FAMILY === 'Windows') {
        return $base . DIRECTORY_SEPARATOR . 'ai-localbase.ps1';
    }
    return $base . DIRECTORY_SEPARATOR . 'ai-localbase.sh';
}

function windowsShellArg(string $value): string
{
    if (preg_match('/^[A-Za-z0-9_\-\.\/\\\\:]+$/u', $value) === 1) {
        return $value;
    }
    return '"' . str_replace('"', '\"', $value) . '"';
}

function shellCommand(array $command): string
{
    $parts = [];
    foreach ($command as $index => $part) {
        $value = (string) $part;
        if (PHP_OS_FAMILY === 'Windows') {
            $parts[] = $index === 0 ? $value : windowsShellArg($value);
            continue;
        }
        $parts[] = escapeshellarg($value);
    }
    return implode(' ', $parts);
}

function runProcess(array $command, ?string $cwd = null): array
{
    $descriptorSpec = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];
    $commandLine = shellCommand($command);
    $process = proc_open($commandLine, $descriptorSpec, $pipes, $cwd);
    if (!is_resource($process)) {
        fail('cannot start process: ' . $commandLine);
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

function searchMemory(string $projectDir, string $query, int $topK, string $scriptPath): string
{
    if ($scriptPath === '' || !is_file($scriptPath)) {
        return '';
    }

    if (PHP_OS_FAMILY === 'Windows' || strtolower((string) pathinfo($scriptPath, PATHINFO_EXTENSION)) === 'ps1') {
        $command = [
            'powershell',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $scriptPath,
            'search',
            $query,
            $projectDir,
            (string) $topK,
        ];
    } else {
        $command = [
            $scriptPath,
            'search',
            $query,
            $projectDir,
            (string) $topK,
        ];
    }

    $result = runProcess($command, $projectDir);
    if ((int) $result['exitCode'] !== 0) {
        stderr('WARN: ai-localbase search failed: ' . normalizeText($result['stderr']));
        return '';
    }
    return extractMemoryText((string) $result['stdout']);
}

function extractMemoryText(string $output): string
{
    $jsonText = extractJsonFromMixedOutput($output);
    if ($jsonText === '') {
        return normalizeText($output);
    }

    $data = json_decode($jsonText, true);
    if (!is_array($data)) {
        return normalizeText($output);
    }

    $items = [];
    if (isset($data['structuredContent']['items']) && is_array($data['structuredContent']['items'])) {
        $items = $data['structuredContent']['items'];
    } elseif (isset($data['items']) && is_array($data['items'])) {
        $items = $data['items'];
    }

    $chunks = [];
    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }
        $name = isset($item['documentName']) && is_string($item['documentName']) ? $item['documentName'] : 'memory';
        $score = isset($item['score']) ? (string) $item['score'] : '';
        $text = isset($item['text']) && is_string($item['text']) ? normalizeText($item['text']) : '';
        if ($text === '') {
            continue;
        }
        $chunks[] = "### {$name}" . ($score !== '' ? " score={$score}" : '') . "\n" . $text;
    }

    if (count($chunks) === 0) {
        return normalizeText($output);
    }
    return implode("\n\n", $chunks);
}

function extractJsonFromMixedOutput(string $output): string
{
    $trimmed = trim($output);
    if ($trimmed === '') {
        return '';
    }
    $start = strrpos($trimmed, '{');
    while ($start !== false) {
        $candidate = substr($trimmed, $start);
        json_decode($candidate, true);
        if (json_last_error() === JSON_ERROR_NONE) {
            return $candidate;
        }
        $start = strrpos(substr($trimmed, 0, $start), '{');
    }
    return '';
}

function extractTitleFromText(string $taskDir, string $text): string
{
    if (preg_match('/任务名称\s*[|:：]\s*([^|\n]+)/u', $text, $m) === 1) {
        $title = normalizeText($m[1]);
        if ($title !== '' && !in_array($title, ['任务目录', '需求目录'], true)) {
            return $title;
        }
    }
    if (preg_match_all('/^#\s+(.+)$/mu', $text, $matches) !== false && isset($matches[1])) {
        foreach ($matches[1] as $match) {
            $title = normalizeText((string) $match);
            if ($title === '') {
                continue;
            }
            if (preg_match('/(文件改动记录|状态|测试报告|测试用例)$/u', $title) === 1) {
                continue;
            }
            if (strpos($title, 'Wrapped JSON Source:') === 0) {
                continue;
            }
            return $title;
        }
    }
    return $taskDir;
}

function extractCompletedItemsFromText(string $text): array
{
    $preferred = extractPreferredCompletedSections($text);
    if ($preferred !== '') {
        $preferredItems = extractListItems($preferred);
        if (count($preferredItems) > 0) {
            return array_slice($preferredItems, 0, 8);
        }
    }

    return extractListItems($text);
}

function extractPreferredCompletedSections(string $text): string
{
    $sections = [];
    $headings = ['交付内容', '核心能力', '任务'];
    foreach ($headings as $heading) {
        $pattern = '/^##\s+' . preg_quote($heading, '/') . '\s*\R(.+?)(?=^##\s+|\z)/msu';
        if (preg_match($pattern, $text, $match) === 1) {
            $sections[] = normalizeText($match[1]);
        }
    }
    return implode("\n", $sections);
}

function extractListItems(string $text): array
{
    $patterns = [
        '/^\s*[-*]\s+(.+)$/mu',
        '/^\s*\d+\.\s+(.+)$/mu',
        '/\|\s*([^|]+?)\s*\|\s*`?docs\/[^|]+`\s*\|[^|]*\|\s*已完成\s*\|/u',
    ];
    $items = [];
    foreach ($patterns as $pattern) {
        if (preg_match_all($pattern, $text, $matches) !== false && isset($matches[1])) {
            foreach ($matches[1] as $match) {
                $item = normalizeText((string) $match);
                if ($item !== '' && mb_strlen($item) >= 4 && !in_array($item, $items, true)) {
                    $items[] = $item;
                }
            }
        }
    }
    if (count($items) === 0) {
        $items[] = '检索项目知识库与任务文档，整理形成日报内容';
        $items[] = '按 Technical Writer 风格压缩信息，输出专业化工作记录';
    }
    return array_slice($items, 0, 8);
}

function normalizeCompletedItems(array $items, string $sourceText): array
{
    $clean = [];
    foreach ($items as $item) {
        $text = normalizeText((string) $item);
        if ($text !== '' && !in_array($text, $clean, true)) {
            $clean[] = $text;
        }
    }
    if (count($clean) > 0) {
        return $clean;
    }
    return extractCompletedItemsFromText($sourceText);
}

function renderMarkdown(
    string $aiCallTier,
    string $apiUsage,
    string $autoComposer,
    string $requirement,
    string $module,
    array $completedItems,
    string $mainPrompt,
    string $estimatedTime,
    string $aiDevTime
): string {
    $completedLines = [];
    foreach ($completedItems as $index => $item) {
        $completedLines[] = ($index + 1) . '. ' . $item;
    }

    return
        "今日AI调用百分比:\n" .
        "{$aiCallTier}\n" .
        "API用量：{$apiUsage}\n" .
        "Auto + Composer：{$autoComposer}\n\n\n" .
        "今日使用AI完成功能:\n" .
        "需求：{$requirement}\n" .
        "功能模块：{$module}\n" .
        "完成内容：\n" .
        implode("\n", $completedLines) . "\n\n\n" .
        "今日主要提示词:\n" .
        "{$mainPrompt}\n\n\n" .
        "今日AI提升工作效率:\n" .
        "需求：{$requirement}\n" .
        "功能模块：{$module}\n" .
        "初始评估时间：{$estimatedTime}、使用AI开发时间：{$aiDevTime}\n";
}

function localPolish(string $markdown): string
{
    $lines = preg_split('/\R/u', $markdown);
    if (!is_array($lines)) {
        return $markdown;
    }
    $clean = [];
    foreach ($lines as $line) {
        $clean[] = rtrim((string) $line);
    }
    return rtrim(implode("\n", $clean)) . "\n";
}

function normalizeAiUrl(string $url, string $endpoint): string
{
    $url = rtrim($url, "/ \t\n\r\0\x0B");
    if ($url === '') {
        return '';
    }
    if (preg_match('#/v1/chat/completions?$#u', $url) === 1) {
        return $url;
    }
    $endpoint = '/' . ltrim($endpoint === '' ? '/v1/chat/completions' : $endpoint, '/');
    return $url . $endpoint;
}

function shouldUseAi(array $options, string $url, string $model, string $key): bool
{
    if (hasFlag($options, 'no-ai')) {
        return false;
    }
    return $url !== '' || $model !== '' || $key !== '';
}

function polishWithOpenAi(string $markdown, string $sourceContext, string $url, string $model, string $key): string
{
    if ($url === '' || $model === '' || $key === '') {
        fail('AI polish requires ai-url, ai-model and ai-key');
    }

    $prompt = "请将以下日报润色为专业、简洁、开发者友好的中文日报。必须保留四个固定段落和字段名，不要添加新段落，不要输出解释。\n\n" .
        "【原始日报】\n{$markdown}\n\n【可参考上下文】\n" . mb_substr($sourceContext, 0, 9000);
    $payload = json_encode([
        'model' => $model,
        'messages' => [
            [
                'role' => 'system',
                'content' => '你是 Technical Writer，只输出润色后的日报 Markdown，保留固定格式。',
            ],
            [
                'role' => 'user',
                'content' => $prompt,
            ],
        ],
        'temperature' => 0.2,
    ], JSON_UNESCAPED_UNICODE);

    if (!is_string($payload)) {
        fail('cannot encode AI request payload');
    }

    $headers = [
        'Content-Type: application/json',
        'Authorization: Bearer ' . $key,
    ];
    $context = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => implode("\r\n", $headers),
            'content' => $payload,
            'timeout' => 90,
            'ignore_errors' => true,
        ],
    ]);
    $response = @file_get_contents($url, false, $context);
    if ($response === false) {
        fail("AI polish request failed: {$url}");
    }

    $statusLine = $http_response_header[0] ?? '';
    if (is_string($statusLine) && preg_match('/\s([45]\d\d)\s/u', $statusLine, $m) === 1) {
        fail("AI polish HTTP {$m[1]}: " . mb_substr(normalizeText($response), 0, 500));
    }

    $data = json_decode($response, true);
    if (!is_array($data)) {
        fail('AI polish response is not JSON');
    }
    $content = $data['choices'][0]['message']['content'] ?? '';
    if (!is_string($content) || normalizeText($content) === '') {
        fail('AI polish response missing choices[0].message.content');
    }
    return localPolish($content);
}

function validateReportFormat(string $content): void
{
    $required = [
        '今日AI调用百分比:',
        '今日使用AI完成功能:',
        '今日主要提示词:',
        '今日AI提升工作效率:',
    ];
    foreach ($required as $needle) {
        if (strpos($content, $needle) === false) {
            fail("report format missing section: {$needle}");
        }
    }
}

$options = getopt('', [
    'project-dir:',
    'list-dirs',
    'task-dir:',
    'memory-query:',
    'top-k:',
    'ai-localbase-script:',
    'session-text:',
    'session-file:',
    'output-dir:',
    'date:',
    'output-file:',
    'print',
    'ai-call-tier:',
    'api-usage:',
    'auto-composer:',
    'requirement:',
    'module:',
    'completed-item:',
    'main-prompt:',
    'estimated-time:',
    'ai-dev-time:',
    'ai-url:',
    'ai-model:',
    'ai-key:',
    'ai-endpoint:',
    'no-ai',
]);

if (!is_array($options)) {
    fail('invalid options');
}

loadScriptEnv();

$projectDir = resolveProjectDir(getOptionValue($options, 'project-dir'));
$dirs = listDocsRequirementDirs($projectDir);
if (hasFlag($options, 'list-dirs')) {
    printRequirementDirs($dirs);
    exit(0);
}

$taskDir = chooseTaskDir($options, $projectDir, $dirs);
$memoryQuery = pickFirst(getOptionValue($options, 'memory-query'), $taskDir);
$topKText = pickFirst(getOptionValue($options, 'top-k'), '8');
$topK = max(1, min(20, (int) $topKText));
$scriptPath = pickFirst(getOptionValue($options, 'ai-localbase-script'), defaultAiLocalbaseScript());

$memoryText = searchMemory($projectDir, $memoryQuery, $topK, $scriptPath);
$localText = collectLocalTaskText($projectDir, $taskDir);
$sessionText = pickFirst(getOptionValue($options, 'session-text'));
$sessionFile = getOptionValue($options, 'session-file');
if ($sessionFile !== '') {
    if (!is_file($sessionFile)) {
        fail("session file not found: {$sessionFile}");
    }
    $sessionText = normalizeText((string) file_get_contents($sessionFile));
}

$sourceContext = normalizeText(
    "【本地任务文档】\n{$localText}\n\n【知识库检索】\n{$memoryText}\n\n【会话补充】\n{$sessionText}"
);

$requirement = pickFirst(
    getOptionValue($options, 'requirement'),
    extractTitleFromText($taskDir, $localText . "\n" . $memoryText),
    $taskDir
);
$module = pickFirst(getOptionValue($options, 'module'), 'docs/' . $taskDir);
$completedSource = pickFirst($localText . "\n\n" . $sessionText, $memoryText);
$completedItems = normalizeCompletedItems(getOptionValues($options, 'completed-item'), $completedSource);
$mainPrompt = pickFirst(
    getOptionValue($options, 'main-prompt'),
    "围绕 docs/{$taskDir} 检索项目知识库，整理会话内容并生成日报"
);

$aiCallTier = pickFirst(getOptionValue($options, 'ai-call-tier'), '免费');
$apiUsage = pickFirst(getOptionValue($options, 'api-usage'), '0%');
$autoComposer = pickFirst(getOptionValue($options, 'auto-composer'), '0%');
$estimatedTime = pickFirst(getOptionValue($options, 'estimated-time'), '0.2天');
$aiDevTime = pickFirst(getOptionValue($options, 'ai-dev-time'), '0.05天');

$markdown = renderMarkdown(
    $aiCallTier,
    $apiUsage,
    $autoComposer,
    $requirement,
    $module,
    $completedItems,
    $mainPrompt,
    $estimatedTime,
    $aiDevTime
);

$aiUrl = pickFirst(getOptionValue($options, 'ai-url'), envValue('DAY_LOG_V2_AI_URL'));
$aiModel = pickFirst(getOptionValue($options, 'ai-model'), envValue('DAY_LOG_V2_AI_MODEL'));
$aiKey = pickFirst(getOptionValue($options, 'ai-key'), envValue('DAY_LOG_V2_AI_KEY'));
$aiEndpoint = pickFirst(getOptionValue($options, 'ai-endpoint'), envValue('DAY_LOG_V2_AI_ENDPOINT'), '/v1/chat/completions');

if (shouldUseAi($options, $aiUrl, $aiModel, $aiKey)) {
    $markdown = polishWithOpenAi($markdown, $sourceContext, normalizeAiUrl($aiUrl, $aiEndpoint), $aiModel, $aiKey);
} else {
    $markdown = localPolish($markdown);
}
validateReportFormat($markdown);

$dateText = pickFirst(getOptionValue($options, 'date'), date('Y-m-d'));
$outputFilename = pickFirst(getOptionValue($options, 'output-file'), "day_log-{$dateText}.md");
$outputDir = resolveOutputDir(getOptionValue($options, 'output-dir'), $projectDir);
if (!is_dir($outputDir) && !mkdir($outputDir, 0777, true) && !is_dir($outputDir)) {
    fail("cannot create output directory: {$outputDir}");
}

$outputPath = $outputDir . DIRECTORY_SEPARATOR . $outputFilename;
if (@file_put_contents($outputPath, $markdown) === false) {
    fail("cannot write output file: {$outputPath}");
}

echo $outputPath . PHP_EOL;
if (hasFlag($options, 'print')) {
    echo $markdown;
}
