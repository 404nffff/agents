param(
  [Parameter(Position = 0)]
  [string]$Payload
)

$ErrorActionPreference = "Stop"

# Codex hooks 飞书通知 PowerShell 版：兼容 SessionStart / SubagentStart /
# PreToolUse / PermissionRequest / PostToolUse / PreCompact / PostCompact /
# UserPromptSubmit / SubagentStop / Stop。
#
# Windows hooks.json 配置可参考同目录 hooks_win.json。
# .env 可选配置：
#   FEISHU_CODEX_HOOK_TEMPLATE='blue'
#   FEISHU_CODEX_HOOK_FOOTER='由 Codex hooks 自动发送'
#   FEISHU_CODEX_HOOK_EVENTS=''          # 空表示全部；也可填 Stop,PostToolUse
#   FEISHU_CODEX_HOOK_INCLUDE_PAYLOAD='false'
#   FEISHU_CODEX_HOOK_MAX_CHARS='3000'
#   FEISHU_CODEX_HOOK_PAYLOAD_LOG_PATH=''
#   FEISHU_CODEX_HOOK_ENABLE_PUSH='false'   # true 时才发送飞书通知
#   FEISHU_CODEX_HOOK_UPDATE_SESSION_TITLE='false' # true 时用官方 app-server 更新会话标题
#   FEISHU_CODEX_HOOK_CODEX_APP_SERVER_DRAIN_SECONDS='0.5' # 写入后等待 app-server 处理
#
# Codex hooks stdin payload 字段说明（自动含义）：
# 1. SessionStart
#    - session_id: 当前会话 ID
#    - cwd: 当前工作目录
#    - transcript_path: 当前会话 transcript 路径
#    - hook_event_name: 固定为 SessionStart
#    - model: 当前模型名
#    - permission_mode: 当前权限模式
#    - source: 触发来源，通常是 startup / resume / clear
# 2. SubagentStart
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - agent_id: 子代理会话 ID
#    - agent_type: 子代理角色类型
# 3. PreToolUse
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - tool_name: 即将调用的工具名
#    - tool_input: 工具入参
#    - tool_use_id: 本次工具调用 ID
# 4. PermissionRequest
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - tool_name: 申请权限的工具名
#    - tool_input: 工具入参
# 5. PostToolUse
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - tool_name: 已调用完成的工具名
#    - tool_input: 工具入参
#    - tool_response: 工具返回结果
#    - tool_use_id: 本次工具调用 ID
# 6. PreCompact
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model
#    - trigger: 压缩触发来源，通常是 manual / auto
# 7. PostCompact
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model
#    - trigger: 压缩触发来源，通常是 manual / auto
# 8. UserPromptSubmit
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - prompt: 用户刚提交的提示词正文
# 9. SubagentStop
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - agent_id: 子代理会话 ID
#    - agent_type: 子代理角色类型
#    - last_assistant_message: 子代理最后一条回复
# 10. Stop
#    - session_id / turn_id / cwd / transcript_path / hook_event_name / model / permission_mode
#    - stop_hook_active: Stop hook 是否已经进入过一次继续链路。false 表示首次 Stop；
#      true 表示前一个 Stop hook 已经要求“继续一轮”后再次进入，常用于防止循环拦截。
#    - last_assistant_message: 当前回合最后一条助手回复

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultEnvFile = Join-Path $ScriptDir ".env"
$LegacyEnvFile = Join-Path $ScriptDir "feishu.env"
$TitleStatePath = if ($env:FEISHU_CODEX_HOOK_TITLE_STATE_PATH) {
  $env:FEISHU_CODEX_HOOK_TITLE_STATE_PATH
} else {
  Join-Path $ScriptDir "codex_hook_title_state.json"
}
$EnvFile = if ($env:FEISHU_ENV_FILE) {
  $env:FEISHU_ENV_FILE
} elseif ($env:FEISHU_BOT_ENV_FILE) {
  $env:FEISHU_BOT_ENV_FILE
} else {
  $DefaultEnvFile
}

function Get-EnvOrDefault {
  param(
    [string]$Name,
    [string]$DefaultValue = ""
  )

  $value = [Environment]::GetEnvironmentVariable($Name, "Process")
  if ([string]::IsNullOrEmpty($value)) {
    return $DefaultValue
  }
  return $value
}

function Write-HookPayloadLog {
  param([string]$JsonLine)

  $logPath = Get-EnvOrDefault "FEISHU_CODEX_HOOK_PAYLOAD_LOG_PATH" (Join-Path $ScriptDir "codex_hook_payload.log")
  if ([string]::IsNullOrWhiteSpace($logPath)) {
    $logPath = Join-Path $ScriptDir "codex_hook_payload.log"
  }
  $logDir = Split-Path -Parent $logPath
  if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
  }
  Add-Content -LiteralPath $logPath -Value $JsonLine
}

function Trim-HookPayloadLog {
  param([int]$KeepLines = 50)

  $logPath = Get-EnvOrDefault "FEISHU_CODEX_HOOK_PAYLOAD_LOG_PATH" (Join-Path $ScriptDir "codex_hook_payload.log")
  if ([string]::IsNullOrWhiteSpace($logPath) -or -not (Test-Path -LiteralPath $logPath)) {
    return
  }

  $lines = @(Get-Content -LiteralPath $logPath -Tail $KeepLines -ErrorAction SilentlyContinue)
  if ($lines.Count -eq 0) {
    return
  }

  [System.IO.File]::WriteAllLines($logPath, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Get-TitleState {
  param(
    [string]$SessionId,
    [string]$TurnId
  )

  if ([string]::IsNullOrWhiteSpace($SessionId) -or [string]::IsNullOrWhiteSpace($TurnId) -or -not (Test-Path -LiteralPath $TitleStatePath)) {
    return ""
  }

  try {
    $state = Get-Content -LiteralPath $TitleStatePath -Raw | ConvertFrom-Json
    if (-not $state) {
      return ""
    }
    $key = "$SessionId`:$TurnId"
    $value = $state.PSObject.Properties[$key]
    if ($value -and $value.Value) {
      $titleProperty = $value.Value.PSObject.Properties["title"]
      if ($titleProperty -and $titleProperty.Value) {
        return [string]$titleProperty.Value
      }
    }
  } catch {}

  return ""
}

function Update-CodexSessionTitle {
  param([string]$RawPayload)

  if ([string]::IsNullOrWhiteSpace($RawPayload)) {
    return
  }
  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
  }
  if (-not $python) {
    return
  }
  $hookPy = Join-Path $ScriptDir "hook.py"
  if (-not (Test-Path -LiteralPath $hookPy)) {
    return
  }

  try {
    $env:FEISHU_CODEX_HOOK_TITLE_STATE_PATH = $TitleStatePath
    & $python.Source $hookPy $RawPayload | Out-Null
  } catch {}
}

function Load-FeishuEnvFile {
  param([string]$Path)

  if ($Path -eq $DefaultEnvFile -and -not (Test-Path -LiteralPath $Path) -and (Test-Path -LiteralPath $LegacyEnvFile)) {
    $Path = $LegacyEnvFile
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
      continue
    }
    if ($trimmed -notmatch "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$") {
      continue
    }

    $name = $Matches[1]
    $value = $Matches[2].Trim()
    if (($value.StartsWith("'") -and $value.EndsWith("'")) -or ($value.StartsWith('"') -and $value.EndsWith('"'))) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    # 外部传入的 FEISHU_* 环境变量优先，避免 .env 覆盖临时敏感值。
    if ($name.StartsWith("FEISHU_") -and [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name, "Process"))) {
      [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
}

function Read-HookPayload {
  if (-not [string]::IsNullOrWhiteSpace($Payload)) {
    return $Payload
  }

  $stdin = [Console]::In.ReadToEnd()
  return $stdin
}

function Invoke-FeishuJson {
  param(
    [string]$Uri,
    [object]$Body,
    [hashtable]$Headers = @{}
  )

  $jsonBody = $Body | ConvertTo-Json -Depth 40 -Compress
  # Windows PowerShell 字符串 Body 可能按本地编码传输，显式 UTF-8 避免中文变问号。
  $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
  $mergedHeaders = @{ "Content-Type" = "application/json; charset=utf-8" }
  foreach ($key in $Headers.Keys) {
    $mergedHeaders[$key] = $Headers[$key]
  }

  $response = Invoke-RestMethod -Method Post -Uri $Uri -Headers $mergedHeaders -Body $jsonBytes -TimeoutSec ([int](Get-EnvOrDefault "FEISHU_BOT_TIMEOUT" "30"))
  if ($null -ne $response.code -and [int]$response.code -ne 0) {
    throw "飞书返回错误 code=$($response.code): $($response.msg)"
  }
  return $response
}

function Get-TenantAccessToken {
  $appId = Get-EnvOrDefault "FEISHU_APP_ID"
  $appSecret = Get-EnvOrDefault "FEISHU_APP_SECRET"
  if ([string]::IsNullOrWhiteSpace($appId)) {
    throw "缺少 FEISHU_APP_ID"
  }
  if ([string]::IsNullOrWhiteSpace($appSecret)) {
    throw "缺少 FEISHU_APP_SECRET"
  }

  $response = Invoke-FeishuJson `
    -Uri "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" `
    -Body @{ app_id = $appId; app_secret = $appSecret }

  if ([string]::IsNullOrWhiteSpace($response.tenant_access_token)) {
    throw "飞书未返回 tenant_access_token"
  }
  return [string]$response.tenant_access_token
}

function Resolve-ReceiveTarget {
  param([string]$Token)

  $targets = @(@(
    @{ Type = "chat_id"; Value = Get-EnvOrDefault "FEISHU_CHAT_ID" },
    @{ Type = "open_id"; Value = Get-EnvOrDefault "FEISHU_OPEN_ID" },
    @{ Type = "user_id"; Value = Get-EnvOrDefault "FEISHU_USER_ID" },
    @{ Type = "email"; Value = Get-EnvOrDefault "FEISHU_EMAIL" },
    @{ Type = "mobile"; Value = Get-EnvOrDefault "FEISHU_MOBILE" }
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_["Value"]) })

  if ($targets.Count -ne 1) {
    throw "需要且只能配置一种接收者：FEISHU_CHAT_ID / FEISHU_OPEN_ID / FEISHU_USER_ID / FEISHU_EMAIL / FEISHU_MOBILE"
  }

  $target = $targets[0]
  if ($target["Type"] -in @("chat_id", "open_id", "user_id")) {
    return $target
  }

  if ($target["Type"] -eq "email") {
    $body = @{ emails = @($target["Value"]) }
  } else {
    $body = @{ mobiles = @($target["Value"]) }
  }

  $response = Invoke-FeishuJson `
    -Uri "https://open.feishu.cn/open-apis/contact/v3/users/batch_get_id?user_id_type=open_id" `
    -Headers @{ Authorization = "Bearer $Token" } `
    -Body $body

  $openId = ""
  if ($response.data.user_list -and $response.data.user_list.Count -gt 0) {
    $openId = [string]$response.data.user_list[0].open_id
  }
  if ([string]::IsNullOrWhiteSpace($openId)) {
    throw "未查到 open_id，请确认通讯录权限、邮箱/手机号和用户状态"
  }

  return @{ Type = "open_id"; Value = $openId }
}

function Get-PropertyText {
  param(
    [object]$Object,
    [string[]]$Names
  )

  if ($null -eq $Object) {
    return ""
  }
  foreach ($name in $Names) {
    $property = $Object.PSObject.Properties[$name]
    if ($null -eq $property -or $null -eq $property.Value) {
      continue
    }
    $text = [string]$property.Value
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      return $text
    }
  }
  return ""
}

function Get-ShortText {
  param(
    [object]$Value,
    [int]$MaxLength = 900
  )

  if ($null -eq $Value) {
    return ""
  }
  $text = if ($Value -is [string]) {
    $Value
  } else {
    $Value | ConvertTo-Json -Depth 30 -Compress
  }
  $text = $text.Trim()
  if ($text.Length -gt $MaxLength) {
    return $text.Substring(0, $MaxLength) + "`n...(已截断)"
  }
  return $text
}

function Get-CleanTitleSummary {
  param(
    [object]$Value,
    [int]$MaxLength = 40
  )

  if ($null -eq $Value) {
    return ""
  }
  $text = if ($Value -is [string]) {
    $Value
  } else {
    $Value | ConvertTo-Json -Depth 30 -Compress
  }
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($line in ($text -replace "`r", "`n" -split "`n")) {
    $cleanLine = $line.Trim()
    $cleanLine = [regex]::Replace($cleanLine, "^#{1,6}\s+", "")
    $cleanLine = [regex]::Replace($cleanLine, "^[-+*]\s+", "")
    $cleanLine = [regex]::Replace($cleanLine, "^\d+\.\s+", "")
    $cleanLine = [regex]::Replace($cleanLine, "^>\s+", "")
    if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
      $lines.Add($cleanLine)
    }
  }
  $text = ($lines -join " ").Trim()
  $text = [regex]::Replace($text, "[`*#>\[\]\(\)~]+", " ")
  $text = [regex]::Replace($text, "\s+", " ").Trim()
  if ($text.Length -gt $MaxLength) {
    $text = $text.Substring(0, $MaxLength).TrimEnd()
  }
  return $text
}

function Remove-ForwardedTitlePrefix {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  $text = $Value.Trim()
  $text = [regex]::Replace($text, "^\[[^\]]+\]\s+.+?\b\d{2}:\d{2}:\d{2}\s+", "", 1)
  $text = [regex]::Replace($text, "^[，,。:：;；、\-\s]+", "")
  return $text.Trim()
}

function Get-LastPromptSegment {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  $segments = @(
    $Value -split "[`n。！？!?]+" |
    ForEach-Object { $_.Trim(" ，,。:：;；、-".ToCharArray()) } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  if ($segments.Count -gt 0) {
    return [string]$segments[-1]
  }
  return $Value.Trim()
}

function Format-CodeText {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "``-``"
  }
  return "``$Value``"
}

function Get-ProjectName {
  param([string]$Cwd)

  $normalized = $Cwd.Trim() -replace "[\\/]+$", ""
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return ""
  }
  return ($normalized -split "[\\/]+")[-1]
}

function ConvertTo-RedactedPayload {
  param([object]$Value)

  $sensitiveKeywords = @("token", "secret", "password", "passwd", "authorization", "cookie", "session", "api_key", "apikey", "access_key", "private_key")

  if ($Value -is [System.Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $keyText = [string]$key
      $normalized = $keyText.ToLowerInvariant().Replace("-", "_")
      $isSensitive = $false
      foreach ($keyword in $sensitiveKeywords) {
        if ($normalized.Contains($keyword)) {
          $isSensitive = $true
          break
        }
      }
      $result[$keyText] = if ($isSensitive) { "***REDACTED***" } else { ConvertTo-RedactedPayload $Value[$key] }
    }
    return $result
  }

  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $map = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
      $map[$property.Name] = $property.Value
    }
    return ConvertTo-RedactedPayload $map
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Value) {
      $items.Add((ConvertTo-RedactedPayload $item))
    }
    return @($items)
  }

  if ($Value -is [string]) {
    $lower = $Value.ToLowerInvariant()
    if ($lower.StartsWith("bearer ") -or $lower.Contains("authorization:") -or $lower.Contains("cookie:")) {
      return "***REDACTED***"
    }
  }

  return $Value
}

function Build-HookPayloadLogEntry {
  param([object]$Event)

  $eventName = Get-PropertyText $Event @("hook_event_name", "hookEventName", "event_name", "eventName", "type")
  $entry = [ordered]@{
    logged_at = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    event = $eventName
    cwd = Get-PropertyText $Event @("cwd")
    payload = ConvertTo-RedactedPayload $Event
  }
  return $entry | ConvertTo-Json -Depth 40 -Compress
}

function Build-HookMarkdown {
  param([object]$Event)

  $supportedEvents = @(
    "SessionStart",
    "SubagentStart",
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "UserPromptSubmit",
    "SubagentStop",
    "Stop"
  )
  $eventZh = @{
    SessionStart = "会话开始"
    SubagentStart = "子代理开始"
    PreToolUse = "工具调用前"
    PermissionRequest = "权限请求"
    PostToolUse = "工具调用后"
    PreCompact = "压缩前"
    PostCompact = "压缩后"
    UserPromptSubmit = "用户提交提示"
    SubagentStop = "子代理结束"
    Stop = "回合结束"
  }

  $eventName = Get-PropertyText $Event @("hook_event_name", "hookEventName", "event_name", "eventName", "type")
  if ($eventName -notin $supportedEvents) {
    return @{ Skip = $true; Reason = "unsupported_event:$eventName" }
  }

  $maxChars = [int](Get-EnvOrDefault "FEISHU_CODEX_HOOK_MAX_CHARS" "3000")
  $footer = Get-EnvOrDefault "FEISHU_CODEX_HOOK_FOOTER" "由 Codex hooks 自动发送"
  $includePayload = (Get-EnvOrDefault "FEISHU_CODEX_HOOK_INCLUDE_PAYLOAD" "false").ToLowerInvariant() -in @("1", "true", "yes", "on")

  $cwd = Get-PropertyText $Event @("cwd")
  $sessionId = Get-PropertyText $Event @("session_id", "sessionId")
  $turnId = Get-PropertyText $Event @("turn_id", "turnId")
  $model = Get-PropertyText $Event @("model")
  $permissionMode = Get-PropertyText $Event @("permission_mode", "permissionMode")
  $transcriptPath = Get-PropertyText $Event @("transcript_path", "transcriptPath")
  $toolName = Get-PropertyText $Event @("tool_name", "toolName")
  $toolUseId = Get-PropertyText $Event @("tool_use_id", "toolUseId", "call_id", "callId")
  $trigger = Get-PropertyText $Event @("trigger")
  $source = Get-PropertyText $Event @("source")
  $prompt = Get-PropertyText $Event @("prompt")
  $lastAssistantMessage = Get-PropertyText $Event @("last_assistant_message", "lastAssistantMessage")
  $stopHookActive = Get-PropertyText $Event @("stop_hook_active", "stopHookActive")
  $agentId = Get-PropertyText $Event @("agent_id", "agentId")
  $agentType = Get-PropertyText $Event @("agent_type", "agentType")
  $toolInputProperty = $Event.PSObject.Properties["tool_input"]
  $toolInput = if ($toolInputProperty) { $toolInputProperty.Value } else { $null }
  $subagentProperty = $Event.PSObject.Properties["subagent"]
  if ($subagentProperty -and $subagentProperty.Value) {
    if ([string]::IsNullOrWhiteSpace($agentId)) {
      $agentId = Get-PropertyText $subagentProperty.Value @("agent_id", "agentId")
    }
    if ([string]::IsNullOrWhiteSpace($agentType)) {
      $agentType = Get-PropertyText $subagentProperty.Value @("agent_type", "agentType")
    }
  }

  $commandText = ""
  if ($null -ne $toolInput) {
    $commandText = Get-PropertyText $toolInput @("cmd", "command")
  }

  $toolSummary = if ([string]::IsNullOrWhiteSpace($commandText)) { $toolName } else { $commandText }
  $titleSummary = switch ($eventName) {
    "PreToolUse" { Get-CleanTitleSummary $toolSummary 40; break }
    "PostToolUse" { Get-CleanTitleSummary $toolSummary 40; break }
    "PermissionRequest" { Get-CleanTitleSummary $toolName 32; break }
    "UserPromptSubmit" { Get-CleanTitleSummary (Get-LastPromptSegment (Remove-ForwardedTitlePrefix $prompt)) 40; break }
    "Stop" { Get-CleanTitleSummary $lastAssistantMessage 24; break }
    "SubagentStart" { Get-CleanTitleSummary $agentType 32; break }
    "SubagentStop" { Get-CleanTitleSummary $agentType 32; break }
    default { "" }
  }

  $allowedRaw = Get-EnvOrDefault "FEISHU_CODEX_HOOK_EVENTS" ""
  $allowed = @($allowedRaw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($allowed.Count -gt 0 -and $eventName -notin $allowed) {
    return @{
      Skip = $true
      Reason = "filtered_event:$eventName"
      Event = $eventName
      Project = Get-ProjectName $cwd
      TitleSummary = $titleSummary
      SessionId = $sessionId
      TurnId = $turnId
    }
  }

  $details = New-Object System.Collections.Generic.List[string]
  if ($source) { $details.Add("- Source：" + (Format-CodeText $source)) }
  if ($trigger) { $details.Add("- Trigger：" + (Format-CodeText $trigger)) }
  if ($toolName) { $details.Add("- Tool：" + (Format-CodeText $toolName)) }
  if ($toolUseId) { $details.Add("- Tool Use ID：" + (Format-CodeText $toolUseId)) }
  if ($stopHookActive) { $details.Add("- Stop Hook Active：" + (Format-CodeText $stopHookActive)) }
  if ($agentId -or $agentType) {
    $details.Add("- Agent ID：" + (Format-CodeText $agentId))
    $details.Add("- Agent Type：" + (Format-CodeText $agentType))
  }

  $messageBlocks = New-Object System.Collections.Generic.List[string]
  if ($eventName -eq "UserPromptSubmit" -and $prompt) {
    $messageBlocks.Add("**用户提示**")
    $messageBlocks.Add("")
    $messageBlocks.Add((Get-ShortText $prompt ([Math]::Min($maxChars, 1200))))
  } elseif ($eventName -eq "Stop" -and $lastAssistantMessage) {
    $messageBlocks.Add("**最终回复**")
    $messageBlocks.Add("")
    $messageBlocks.Add((Get-ShortText $lastAssistantMessage $maxChars))
  }

  if ($includePayload) {
    $payloadExcerpt = Get-ShortText $Event ([Math]::Min($maxChars, 1600))
    if ($payloadExcerpt) {
      $messageBlocks.Add("")
      $messageBlocks.Add("---")
      $messageBlocks.Add("")
      $messageBlocks.Add("**Payload 摘要**")
      $messageBlocks.Add("")
      $messageBlocks.Add("```json`n$payloadExcerpt`n```")
    }
  }

  $parts = New-Object System.Collections.Generic.List[string]
  $parts.Add("**事件**：$eventName（$($eventZh[$eventName])）")
  $parts.Add("")
  $parts.Add("**工作目录**")
  $parts.Add((Format-CodeText $cwd))
  $parts.Add("")
  $parts.Add("**基础信息**")
  $parts.Add("- Session：" + (Format-CodeText $sessionId))
  $parts.Add("- Turn：" + (Format-CodeText $turnId))
  $parts.Add("- Model：" + (Format-CodeText $model))
  $parts.Add("- Permission：" + (Format-CodeText $permissionMode))
  $parts.Add("- Transcript：" + (Format-CodeText $transcriptPath))

  if ($details.Count -gt 0) {
    $parts.Add("")
    $parts.Add("**事件详情**")
    foreach ($item in $details) { $parts.Add($item) }
  }

  if ($messageBlocks.Count -gt 0) {
    $parts.Add("")
    $parts.Add("---")
    $parts.Add("")
    foreach ($item in $messageBlocks) { $parts.Add($item) }
  }

  $parts.Add("")
  $parts.Add("---")
  $parts.Add("")
  $parts.Add($footer)

  return @{
    Skip = $false
    Event = $eventName
    Project = Get-ProjectName $cwd
    TitleSummary = $titleSummary
    SessionId = $sessionId
    TurnId = $turnId
    Markdown = ($parts -join "`n")
  }
}

function Send-MarkdownCard {
  param(
    [string]$Token,
    [hashtable]$Target,
    [string]$Title,
    [string]$Markdown
  )

  $template = Get-EnvOrDefault "FEISHU_CODEX_HOOK_TEMPLATE" (Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_TEMPLATE" "blue")
  $card = @{
    schema = "2.0"
    config = @{ update_multi = $true }
    body = @{
      direction = "vertical"
      padding = "12px 12px 12px 12px"
      elements = @(
        @{
          tag = "markdown"
          content = $Markdown
          text_align = "left"
          text_size = "normal_v2"
        }
      )
    }
    header = @{
      title = @{ tag = "plain_text"; content = $Title }
      template = $template
      padding = "12px 12px 12px 12px"
    }
  }

  $content = $card | ConvertTo-Json -Depth 40 -Compress
  $body = @{
    receive_id = $Target["Value"]
    msg_type = "interactive"
    content = $content
  }

  Invoke-FeishuJson `
    -Uri ("https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type={0}" -f $Target["Type"]) `
    -Headers @{ Authorization = "Bearer $Token" } `
    -Body $body | Out-Null
}

try {
  Load-FeishuEnvFile -Path $EnvFile
  $raw = Read-HookPayload
  if ([string]::IsNullOrWhiteSpace($raw)) {
    exit 0
  }

  $event = $raw | ConvertFrom-Json
  try {
    Write-HookPayloadLog (Build-HookPayloadLogEntry -Event $event)
  } catch {}
  $eventName = Get-PropertyText $event @("hook_event_name", "hookEventName", "event_name", "eventName", "type")
  if ($eventName -eq "Stop") {
    try { Trim-HookPayloadLog -KeepLines 50 } catch {}
  }
  $parsed = Build-HookMarkdown -Event $event
  $sessionId = [string]$parsed["SessionId"]
  $turnId = [string]$parsed["TurnId"]
  $titleSummary = [string]$parsed["TitleSummary"]
  if ($eventName -eq "UserPromptSubmit") {
    Update-CodexSessionTitle -RawPayload $raw
  }
  if ($parsed["Skip"]) {
    exit 0
  }

  $promptTitle = Get-TitleState -SessionId $sessionId -TurnId $turnId
  $title = if ([string]::IsNullOrWhiteSpace($promptTitle)) {
    if ([string]::IsNullOrWhiteSpace($titleSummary)) { [string]$parsed["Event"] } else { $titleSummary }
  } else {
    $promptTitle
  }
  if ($eventName -eq "Stop") {
    Update-CodexSessionTitle -RawPayload $raw
  }
  $project = [string]$parsed["Project"]
  if (-not [string]::IsNullOrWhiteSpace($project) -and -not $title.StartsWith("[$project]")) {
    $title = "[{0}] {1}" -f $project, $title
  }
  $title = "{0} {1}" -f $title, (Get-Date -Format "HH:mm:ss")

  $pushEnabled = (Get-EnvOrDefault "FEISHU_CODEX_HOOK_ENABLE_PUSH" "false").ToLowerInvariant()
  if ($pushEnabled -in @("1", "true", "yes", "on")) {
    $token = Get-TenantAccessToken
    $target = Resolve-ReceiveTarget -Token $token
    Send-MarkdownCard -Token $token -Target $target -Title $title -Markdown $parsed["Markdown"]
  }
} catch {}

# Codex hooks 不应因通知失败阻断主流程，也不应向 stdout 输出内容注入模型上下文。
exit 0
