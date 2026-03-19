#!/usr/bin/env php
<?php
declare(strict_types=1);

function stderr(string $message): void
{
    fwrite(STDERR, $message . PHP_EOL);
}

function fail(string $message, int $exitCode = 1): void
{
    stderr("ERROR: " . $message);
    exit($exitCode);
}

function decodeEscapedNewline(string $value): string
{
    return str_replace("\\n", "\n", $value);
}

function normalizeText(string $value): string
{
    return trim(decodeEscapedNewline($value));
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
        if (count($value) === 0) {
            return '';
        }
        $value = end($value);
    }
    if (!is_string($value)) {
        return '';
    }
    return normalizeText($value);
}

function getOptionValues(array $options, string $key): array
{
    if (!array_key_exists($key, $options)) {
        return [];
    }
    $value = $options[$key];
    if (is_array($value)) {
        $result = [];
        foreach ($value as $item) {
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
    if (!is_string($value)) {
        return [];
    }
    $text = normalizeText($value);
    return $text === '' ? [] : [$text];
}

function readSessionText(array $options): string
{
    $sessionText = getOptionValue($options, 'session-text');
    if ($sessionText !== '') {
        return $sessionText;
    }

    $sessionFile = getOptionValue($options, 'session-file');
    if ($sessionFile !== '') {
        if (!is_file($sessionFile)) {
            fail("session file not found: {$sessionFile}");
        }
        $content = @file_get_contents($sessionFile);
        if ($content === false) {
            fail("cannot read session file: {$sessionFile}");
        }
        return trim((string) $content);
    }

    if (!stdinIsTty()) {
        $stdin = stream_get_contents(STDIN);
        return trim((string) $stdin);
    }

    return '';
}

function pickFirst(string ...$values): string
{
    foreach ($values as $value) {
        $text = normalizeText($value);
        if ($text !== '') {
            return $text;
        }
    }
    return '未提供';
}

function extractLastUserMessage(string $sessionText): string
{
    if ($sessionText === '') {
        return '';
    }

    $parts = preg_split('/\b(?:user|用户)\s*[:：]/iu', $sessionText);
    if (is_array($parts) && count($parts) >= 2) {
        $last = end($parts);
        if (is_string($last)) {
            return trim($last);
        }
    }

    $lines = preg_split('/\R/u', $sessionText);
    if (!is_array($lines)) {
        return '';
    }

    $clean = [];
    foreach ($lines as $line) {
        $text = trim((string) $line);
        if ($text !== '') {
            $clean[] = $text;
        }
    }
    foreach ($clean as $line) {
        if (!preg_match('/^[-*]\s+/u', $line) && !preg_match('/^\d+\.\s+/u', $line)) {
            return $line;
        }
    }
    return $clean[0] ?? '';
}

function extractModule(string $sessionText): string
{
    if ($sessionText === '') {
        return '';
    }

    $pattern = '/(?:[A-Za-z0-9_\-\.\/]+(?:\.[A-Za-z0-9_]+)+)(?:\s*->\s*[A-Za-z0-9_]+)?/u';
    $matches = [];
    preg_match_all($pattern, $sessionText, $matches);
    if (!isset($matches[0]) || !is_array($matches[0])) {
        return '';
    }

    $unique = [];
    foreach ($matches[0] as $item) {
        $text = trim((string) $item);
        if ($text === '' || in_array($text, $unique, true)) {
            continue;
        }
        $unique[] = $text;
    }
    if (count($unique) === 0) {
        return '';
    }
    return implode('；', array_slice($unique, 0, 3));
}

function extractCompletedItems(string $sessionText): array
{
    if ($sessionText === '') {
        return [];
    }
    $lines = preg_split('/\R/u', $sessionText);
    if (!is_array($lines)) {
        return [];
    }

    $items = [];
    foreach ($lines as $line) {
        $text = trim((string) $line);
        if ($text === '') {
            continue;
        }
        if (preg_match('/^[-*]\s+(.+)$/u', $text, $m)) {
            $items[] = trim($m[1]);
            continue;
        }
        if (preg_match('/^\d+\.\s+(.+)$/u', $text, $m)) {
            $items[] = trim($m[1]);
        }
    }

    $unique = [];
    foreach ($items as $item) {
        if ($item === '' || in_array($item, $unique, true)) {
            continue;
        }
        $unique[] = $item;
    }
    return array_slice($unique, 0, 8);
}

function ensureItems(array $userItems, string $sessionText): array
{
    $clean = [];
    foreach ($userItems as $item) {
        $text = normalizeText((string) $item);
        if ($text !== '') {
            $clean[] = $text;
        }
    }
    if (count($clean) > 0) {
        return $clean;
    }

    $extracted = extractCompletedItems($sessionText);
    if (count($extracted) > 0) {
        return $extracted;
    }
    return ['根据当前会话整理并输出日报文档'];
}

function renderMarkdown(
    string $aiCallTier,
    string $apiUsage,
    string $autoComposer,
    string $requirement,
    string $module,
    array $completedItems,
    string $mainPrompt,
    string $efficiencyRequirement,
    string $efficiencyModule,
    string $estimatedTime,
    string $aiDevTime
): string {
    $completedLines = [];
    foreach ($completedItems as $index => $item) {
        $completedLines[] = ($index + 1) . '. ' . $item;
    }
    $completedText = implode("\n", $completedLines);

    return
        "今日AI调用百分比:\n" .
        "{$aiCallTier}\n" .
        "API用量：{$apiUsage}\n" .
        "Auto + Composer：{$autoComposer}\n\n\n" .
        "今日使用AI完成功能:\n" .
        "需求：{$requirement}\n" .
        "功能模块：{$module}\n" .
        "完成内容：\n" .
        "{$completedText}\n\n\n" .
        "今日主要提示词:\n" .
        "{$mainPrompt}\n\n\n" .
        "今日AI提升工作效率:\n" .
        "需求：{$efficiencyRequirement}\n" .
        "功能模块：{$efficiencyModule}\n" .
        "初始评估时间：{$estimatedTime}、使用AI开发时间：{$aiDevTime}\n";
}

function resolveOutputDir(string $outputDir): string
{
    if ($outputDir === '') {
        $outputDir = '.';
    }
    if (preg_match('/^(?:\/|[A-Za-z]:[\/\\\\])/u', $outputDir) !== 1) {
        $cwd = getcwd();
        if ($cwd === false) {
            fail('cannot resolve current working directory');
        }
        $outputDir = $cwd . DIRECTORY_SEPARATOR . $outputDir;
    }
    return rtrim($outputDir, "/\\");
}

$options = getopt('', [
    'session-text:',
    'session-file:',
    'output-dir:',
    'date:',
    'output-file:',
    'ai-call-tier:',
    'api-usage:',
    'auto-composer:',
    'requirement:',
    'module:',
    'completed-item:',
    'main-prompt:',
    'efficiency-requirement:',
    'efficiency-module:',
    'estimated-time:',
    'ai-dev-time:',
]);

if (!is_array($options)) {
    fail('invalid options');
}

$sessionText = readSessionText($options);
$lastUserMessage = extractLastUserMessage($sessionText);
$autoModule = extractModule($sessionText);

$requirement = pickFirst(
    getOptionValue($options, 'requirement'),
    $lastUserMessage
);
$module = pickFirst(
    getOptionValue($options, 'module'),
    $autoModule
);
$completedItems = ensureItems(
    getOptionValues($options, 'completed-item'),
    $sessionText
);
$mainPrompt = pickFirst(
    getOptionValue($options, 'main-prompt'),
    $lastUserMessage
);

$efficiencyRequirement = pickFirst(
    getOptionValue($options, 'efficiency-requirement'),
    $requirement
);
$efficiencyModule = pickFirst(
    getOptionValue($options, 'efficiency-module'),
    $module
);

$aiCallTier = pickFirst(getOptionValue($options, 'ai-call-tier'), '免费');
$apiUsage = pickFirst(getOptionValue($options, 'api-usage'), '0%');
$autoComposer = pickFirst(getOptionValue($options, 'auto-composer'), '0%');
$estimatedTime = pickFirst(getOptionValue($options, 'estimated-time'), '未提供');
$aiDevTime = pickFirst(getOptionValue($options, 'ai-dev-time'), '未提供');

$dateText = pickFirst(getOptionValue($options, 'date'), date('Y-m-d'));
$outputFilename = getOptionValue($options, 'output-file');
if ($outputFilename === '') {
    $outputFilename = "day_log-{$dateText}.md";
}

$outputDir = resolveOutputDir(getOptionValue($options, 'output-dir'));
if (!is_dir($outputDir)) {
    if (!mkdir($outputDir, 0777, true) && !is_dir($outputDir)) {
        fail("cannot create output directory: {$outputDir}");
    }
}

$content = renderMarkdown(
    $aiCallTier,
    $apiUsage,
    $autoComposer,
    $requirement,
    $module,
    $completedItems,
    $mainPrompt,
    $efficiencyRequirement,
    $efficiencyModule,
    $estimatedTime,
    $aiDevTime
);

$outputPath = $outputDir . DIRECTORY_SEPARATOR . $outputFilename;
$result = @file_put_contents($outputPath, $content);
if ($result === false) {
    fail("cannot write output file: {$outputPath}");
}

echo $outputPath . PHP_EOL;
