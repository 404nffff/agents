Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDirArg = ""
$AiUrlArg = ""
$AiModelArg = ""
$AiKeyArg = ""
$NoAi = $false
$RequireAi = $false
$DebugAiShape = $false

function Write-Usage {
    Write-Output "Usage: generate_commit_message.ps1 [-ProjectDir DIR] [-AiUrl URL] [-AiModel MODEL] [-AiKey KEY] [-NoAi] [-RequireAi] [-DebugAiShape]"
}

for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        { $_ -in @("-ProjectDir", "--project-dir") } {
            if ($index + 1 -ge $args.Count) { throw "--project-dir requires a value" }
            $ProjectDirArg = $args[++$index]
        }
        { $_ -in @("-AiUrl", "--ai-url") } {
            if ($index + 1 -ge $args.Count) { throw "--ai-url requires a value" }
            $AiUrlArg = $args[++$index]
        }
        { $_ -in @("-AiModel", "--ai-model") } {
            if ($index + 1 -ge $args.Count) { throw "--ai-model requires a value" }
            $AiModelArg = $args[++$index]
        }
        { $_ -in @("-AiKey", "--ai-key") } {
            if ($index + 1 -ge $args.Count) { throw "--ai-key requires a value" }
            $AiKeyArg = $args[++$index]
        }
        { $_ -in @("-NoAi", "--no-ai") } {
            $NoAi = $true
        }
        { $_ -in @("-RequireAi", "--require-ai") } {
            $RequireAi = $true
        }
        { $_ -in @("-DebugAiShape", "--debug-ai-shape") } {
            $DebugAiShape = $true
        }
        { $_ -in @("-h", "--help") } {
            Write-Usage
            exit 0
        }
        default {
            throw "unknown option: $($args[$index])"
        }
    }
}

function Fail([string]$Message, [int]$Code = 1) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit $Code
}

function Resolve-ProjectDir([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) {
        $Dir = (Get-Location).Path
    }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        Fail "project dir not found: $Dir"
    }
    return (Resolve-Path -LiteralPath $Dir).Path
}

function Invoke-Git([string[]]$GitArgs) {
    $output = & git -C $script:ProjectDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (($output | Out-String).Trim())
        if ($message.Length -gt 500) { $message = $message.Substring(0, 500) }
        Fail "git command failed: $message"
    }
    return ($output | Out-String).TrimEnd()
}

function Invoke-GitLog {
    & git -C $script:ProjectDir rev-parse --verify HEAD *> $null
    if ($LASTEXITCODE -ne 0) { return "" }
    $output = & git -C $script:ProjectDir log --oneline -10 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (($output | Out-String).Trim())
        if ($message.Length -gt 500) { $message = $message.Substring(0, 500) }
        Fail "git log failed: $message"
    }
    return ($output | Out-String).TrimEnd()
}

function Test-IgnoredLockFile([string]$Path) {
    $base = Get-GitPathBaseName $Path
    return $base -in @("pnpm-lock.yaml", "package-lock.json", "yarn.lock", "bun.lockb")
}

function Get-GitPathBaseName([string]$Path) {
    $normalized = ($Path -replace "\\", "/").Trim('"')
    $parts = @($normalized -split "/" | Where-Object { $_ })
    if ($parts.Count -eq 0) { return "" }
    return $parts[-1]
}

function Get-StagedFiles {
    $files = @(Invoke-Git @("diff", "--cached", "--name-only") -split "`r?`n" | Where-Object { $_ })
    return @($files | Where-Object { -not (Test-IgnoredLockFile $_) })
}

function Get-StagedDiff {
    return Invoke-Git @(
        "diff", "--cached", "--", ".",
        ":(exclude)pnpm-lock.yaml",
        ":(exclude)package-lock.json",
        ":(exclude)yarn.lock",
        ":(exclude)bun.lockb"
    )
}

function Get-StagedStat {
    return Invoke-Git @(
        "diff", "--cached", "--stat", "--", ".",
        ":(exclude)pnpm-lock.yaml",
        ":(exclude)package-lock.json",
        ":(exclude)yarn.lock",
        ":(exclude)bun.lockb"
    )
}

function Get-StagedNameStatus {
    return Invoke-Git @("diff", "--cached", "--name-status")
}

function Get-StagedNumStat {
    return Invoke-Git @("diff", "--cached", "--numstat")
}

function Add-SecretViolation([System.Collections.Generic.List[string]]$Violations, [string]$Message) {
    [void]$Violations.Add($Message)
}

function Test-StagedSecrets([string]$Diff) {
    $violations = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $script:StagedFiles) {
        $normalized = $file -replace "\\", "/"
        $base = (Get-GitPathBaseName $normalized).ToLowerInvariant()
        $lowerFile = $normalized.ToLowerInvariant()

        if (($base -eq ".env" -or $base.StartsWith(".env.")) -and $base -ne ".env.example" -and -not $base.EndsWith(".example")) {
            Add-SecretViolation $violations "敏感文件路径: $file"
        }
        if ($base -match "\.(pem|key|p12|pfx)$" -or $base -in @("id_rsa", "id_ed25519", "id_dsa", "id_ecdsa")) {
            Add-SecretViolation $violations "密钥文件路径: $file"
        }
        if ($lowerFile -match "credentials.*\.json$|service-account.*\.json$|service_account.*\.json$") {
            Add-SecretViolation $violations "凭证文件路径: $file"
        }
    }

    # 仅扫描新增行，命中后只输出规则名，避免泄露具体敏感值。
    $addedLines = @()
    foreach ($line in ($Diff -split "`r?`n")) {
        if ($line.StartsWith("+++") -or -not $line.StartsWith("+")) { continue }
        $addedLines += $line.Substring(1)
    }
    $addedText = $addedLines -join "`n"
    if ($addedText) {
        if ($addedText -match "-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----") {
            Add-SecretViolation $violations "新增行命中私钥块规则"
        }
        if ($addedText -match "AKIA[0-9A-Z]{16}") {
            Add-SecretViolation $violations "新增行命中 AWS Access Key 规则"
        }
        if ($addedText -match "(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}") {
            Add-SecretViolation $violations "新增行命中 GitHub Token 规则"
        }
        if ($addedText -match "sk-[A-Za-z0-9][A-Za-z0-9_-]{18,}") {
            Add-SecretViolation $violations "新增行命中 OpenAI 风格 Key 规则"
        }
        if ($addedText -match "xox[baprs]-[A-Za-z0-9-]{10,}") {
            Add-SecretViolation $violations "新增行命中 Slack Token 规则"
        }
        if ($addedText -match "(?i)(api[_-]?key|apikey|secret|token|password|passwd|pwd)\s*[:=]\s*[""']?[A-Za-z0-9_./+=:@%~-]{12,}") {
            Add-SecretViolation $violations "新增行命中密钥字段赋值规则"
        }
        if ($addedText -match "(?i)bearer\s+[A-Za-z0-9_./+=:@%~-]{20,}") {
            Add-SecretViolation $violations "新增行命中 Bearer Token 规则"
        }
    }

    if ($violations.Count -gt 0) {
        [Console]::Error.WriteLine("ERROR: staged changes may contain sensitive information:")
        $violations | Sort-Object -Unique | ForEach-Object { [Console]::Error.WriteLine("- $_") }
        [Console]::Error.WriteLine("Remove sensitive values from staged changes before generating commit message. Matched values are not printed.")
        exit 2
    }
}

function Get-Gitmoji([string]$Joined, [string]$Diff) {
    if ($Diff -match "(?m)^new file mode") { return ":sparkles:" }
    if ($Joined -match "(?i)(^|/)(README|docs/|.*\.md$)") { return ":memo:" }
    if ($Joined -match "(?i)(^|/)(tests?|__tests__)/|\.test\.|\.spec\.") { return ":white_check_mark:" }
    if ($Joined -match "(?i)(^|/)(Dockerfile|docker|docker-compose\.ya?ml)") { return ":whale:" }
    if ($Joined -match "(?i)(^|/)(AGENTS\.md|\.env\.example|.*\.ya?ml$|.*\.json$)") { return ":wrench:" }
    if ($Diff -match "(?m)^deleted file mode") { return ":fire:" }
    return ":sparkles:"
}

function Get-ModuleName {
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $script:StagedFiles) {
        $parts = @($file -replace "\\", "/" -split "/" | Where-Object { $_ })
        if ($parts.Count -eq 0) { continue }
        if ($parts[0].StartsWith(".")) { continue }
        if ($parts.Count -ge 2) {
            [void]$candidates.Add("$($parts[0])/$($parts[1])")
            continue
        }
        [void]$candidates.Add($parts[0])
    }
    $unique = @($candidates | Select-Object -Unique)
    if ($unique.Count -ge 3) { return "多模块工具链" }
    if ($unique.Count -eq 2) { return ($unique -join " 与 ") }
    if ($unique.Count -eq 1) { return $unique[0] }
    return "暂存变更"
}

function Get-LocalCommitTitle([string]$Diff) {
    $joined = $script:StagedFiles -join "`n"
    $emoji = Get-Gitmoji $joined $Diff
    $module = Get-ModuleName

    if ($joined -match "shell/codex_hook/plugins/sdlc_watch" -and $joined -match "skills/low-model-search-code-explorer" -and $joined -match "skills/taste-skill") {
        return "$emoji 完善 sdlc_watch Web 客户端、代码探索技能与前端审美技能集"
    }
    if ($joined -match "skills/git-commit-helper") {
        return "$emoji 增强 git-commit-helper 暂存敏感信息检查与 PowerShell 入口"
    }
    if ($Diff -match "(?m)^new file mode") {
        return "$emoji 新增 $module 相关能力与配套说明"
    }
    if ($Diff -match "(?m)^deleted file mode") {
        return "$emoji 清理 $module 过时文件与无效实现"
    }
    return "$emoji 更新 $module 相关实现与文档说明"
}

function Read-DotEnvFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { continue }
        $key = $line.Substring(0, $line.IndexOf("=")).Trim()
        $value = $line.Substring($line.IndexOf("=") + 1).Trim()
        if ($key -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") { continue }
        if (Test-Path "Env:$key") { continue }
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        Set-Item -Path "Env:$key" -Value $value
    }
}

function First-NonEmpty([string[]]$Values) {
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return ""
}

function Normalize-AiUrl([string]$Url) {
    $trimmed = $Url.TrimEnd("/")
    if (-not $trimmed) { return "" }
    if ($trimmed -match "/v1/chat/completions?$") { return $trimmed }
    return "$trimmed/v1/chat/completions"
}

function Get-SanitizedTitle([string]$Title) {
    $text = [string]$Title
    $text = $text -replace "^\s*```[A-Za-z0-9_-]*\s*(`r`n|`n|`r)", ""
    $text = $text -replace "(`r`n|`n|`r)\s*```\s*$", ""
    $line = ($text -split "(`r`n|`n|`r)" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $line) { return "" }
    return ($line.Trim(" `"`'") -replace "\s+", " ")
}

function Test-ExplanatoryTitle([string]$Title) {
    return $Title -match "(?i)^(based on|here'?s|commit message|suggestion|this commit)"
}

function Assert-UsefulTitle([string]$Title) {
    $plain = $Title -replace "^:[a-z0-9_+-]+:\s*", ""
    if (Test-ExplanatoryTitle $Title) {
        Fail "AI commit title is explanatory text; expected only one commit subject"
    }
    if ($plain.Length -lt 16) {
        Fail "AI commit title is too short; expected a concrete title with module and change intent"
    }
    if ($Title.Length -gt 90) {
        Fail "AI commit title is too long; keep it as one concise commit subject"
    }
}

function Invoke-OpenAiRequest([string]$Prompt, [string]$Url, [string]$Model, [string]$Key) {
    $payload = @{
        model = $Model
        messages = @(
            @{ role = "system"; content = "只输出一行中文 Git commit subject。禁止解释。禁止 Markdown。禁止英文说明。" },
            @{ role = "user"; content = $Prompt }
        )
        temperature = 0.1
    } | ConvertTo-Json -Depth 8
    try {
        $rawResponse = Invoke-WebRequest -Method Post -Uri $Url -Headers @{ Authorization = "Bearer $Key" } -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -UseBasicParsing
    } catch {
        Fail "AI title polish request failed: $Url"
    }
    $responseText = $rawResponse.Content
    if ($rawResponse.RawContentStream) {
        $stream = $rawResponse.RawContentStream
        if ($stream.CanSeek) { $stream.Position = 0 }
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        $responseText = $reader.ReadToEnd()
        $reader.Dispose()
    }
    try {
        return ($responseText | ConvertFrom-Json)
    } catch {
        Fail "AI title polish response is not valid JSON"
    }
}

function Read-AiTitleContent($Response) {
    $content = ""
    $propertyNames = @($Response.PSObject.Properties.Name)
    if ($propertyNames -contains "choices" -and $Response.choices.Count -gt 0) {
        $choice = $Response.choices[0]
        $choiceProperties = @($choice.PSObject.Properties.Name)
        if ($choiceProperties -contains "message") {
            $messageProperties = @($choice.message.PSObject.Properties.Name)
            if ($messageProperties -contains "content") {
                $content = [string]$choice.message.content
            }
        }
        if (-not $content -and $choiceProperties -contains "delta") {
            $deltaProperties = @($choice.delta.PSObject.Properties.Name)
            if ($deltaProperties -contains "content") {
                $content = [string]$choice.delta.content
            }
        }
        if (-not $content -and $choiceProperties -contains "text") {
            $content = [string]$choice.text
        }
    }
    if (-not $content -and $propertyNames -contains "content") {
        $content = [string]$Response.content
    }
    if ($script:DebugAiShape) {
        Write-Output ("AI_TOP_KEYS=" + ($propertyNames -join ","))
        if ($propertyNames -contains "code") {
            Write-Output ("AI_ERROR_CODE=" + [string]$Response.code)
        }
        if ($propertyNames -contains "message") {
            Write-Output ("AI_ERROR_MESSAGE=" + [string]$Response.message)
        }
        if ($propertyNames -contains "choices" -and $Response.choices.Count -gt 0) {
            $choice = $Response.choices[0]
            $choiceProperties = @($choice.PSObject.Properties.Name)
            Write-Output ("AI_CHOICE_KEYS=" + ($choiceProperties -join ","))
            if ($choiceProperties -contains "message") {
                $messageProperties = @($choice.message.PSObject.Properties.Name)
                Write-Output ("AI_MESSAGE_KEYS=" + ($messageProperties -join ","))
                if ($messageProperties -contains "content") {
                    Write-Output ("AI_MESSAGE_CONTENT_LENGTH=" + ([string]$choice.message.content).Length)
                }
            }
            if ($choiceProperties -contains "delta") {
                $deltaProperties = @($choice.delta.PSObject.Properties.Name)
                Write-Output ("AI_DELTA_KEYS=" + ($deltaProperties -join ","))
                if ($deltaProperties -contains "content") {
                    Write-Output ("AI_DELTA_CONTENT_LENGTH=" + ([string]$choice.delta.content).Length)
                }
            }
        }
        if ($propertyNames -contains "content") {
            Write-Output ("AI_TOP_CONTENT_LENGTH=" + ([string]$Response.content).Length)
        }
        Write-Output ("AI_SELECTED_CONTENT_LENGTH=" + ([string]$content).Length)
    }
    return $content
}

function Invoke-OpenAiPolish([string]$LocalTitle, [string]$Stat, [string]$Diff, [string]$Log, [string]$Url, [string]$Model, [string]$Key) {
    if (-not $Url -or -not $Model -or -not $Key) {
        Fail "AI title polish requires API_URL, MODEL and API_KEY"
    }
    $files = $script:StagedFiles -join "`n"
    $prompt = @"
请基于暂存区变更润色 Git 提交标题。
只允许输出一行提交标题本身，禁止输出解释、前缀说明、列表、Markdown 代码块。
标题必须以 GitMoji 代码开头，例如 :sparkles:。
标题必须是中文，且覆盖主要模块和具体变更意图；长度建议 18-72 个中文字符。

【本地初稿】
$LocalTitle

【暂存文件】
$files

【变更统计】
$Stat

【关键 diff】
$Diff

【最近提交】
$Log
"@
    if ($prompt.Length -gt 18000) { $prompt = $prompt.Substring(0, 18000) }
    $response = Invoke-OpenAiRequest $prompt $Url $Model $Key
    $content = Read-AiTitleContent $response
    $title = Get-SanitizedTitle $content
    if (-not $title) { Fail "AI title polish response did not contain a usable title" }
    if (Test-ExplanatoryTitle $title) {
        $retryPrompt = @"
把下面内容改写成一行中文 Git commit subject。
必须只输出标题本身。
必须以 :sparkles:、:memo:、:wrench:、:bug: 之一开头。
禁止输出 Based on、Here's、suggestion、解释、列表、代码块。

本地初稿：$LocalTitle
暂存文件摘要：
$($script:StagedFiles -join "`n")
"@
        if ($retryPrompt.Length -gt 6000) { $retryPrompt = $retryPrompt.Substring(0, 6000) }
        $response = Invoke-OpenAiRequest $retryPrompt $Url $Model $Key
        $content = Read-AiTitleContent $response
        $title = Get-SanitizedTitle $content
        if (-not $title) { Fail "AI title polish response did not contain a usable title" }
    }
    Assert-UsefulTitle $title
    return $title
}

$script:ProjectDir = Resolve-ProjectDir $ProjectDirArg

$script:StagedFiles = @(Get-StagedFiles)
if ($script:StagedFiles.Count -eq 0) {
    Fail "no staged files found; run git add first"
}

$diff = Get-StagedDiff
Test-StagedSecrets $diff

$stat = Get-StagedStat
if ($stat.Length -gt 4000) { $stat = $stat.Substring(0, 4000) }
$diffForPrompt = "name-status:`n$(Get-StagedNameStatus)`n`nnumstat:`n$(Get-StagedNumStat)"
if ($diffForPrompt.Length -gt 12000) { $diffForPrompt = $diffForPrompt.Substring(0, 12000) }
$log = Invoke-GitLog
$title = Get-LocalCommitTitle $diff

if ($NoAi -and $RequireAi) {
    Fail "-NoAi and -RequireAi cannot be used together"
}

if (-not $NoAi) {
    Read-DotEnvFile (Join-Path $ScriptDir ".env")
    $aiUrl = First-NonEmpty @($AiUrlArg, $env:API_URL)
    $aiModel = First-NonEmpty @($AiModelArg, $env:MODEL)
    $aiKey = First-NonEmpty @($AiKeyArg, $env:API_KEY)
    if ($RequireAi -and (-not $aiUrl -or -not $aiModel -or -not $aiKey)) {
        Fail "AI title polish requires API_URL, MODEL and API_KEY"
    }
    if ($aiUrl -or $aiModel -or $aiKey) {
        $title = Invoke-OpenAiPolish $title $stat $diffForPrompt $log (Normalize-AiUrl $aiUrl) $aiModel $aiKey
    }
}

Write-Output (Get-SanitizedTitle $title)
