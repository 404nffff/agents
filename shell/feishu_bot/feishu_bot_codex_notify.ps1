param(
  [Parameter(Position = 0)]
  [string]$Payload
)

$ErrorActionPreference = "Stop"

# Codex notify hook (PowerShell/Windows)：仅处理 agent-turn-complete，并发送飞书 Markdown 卡片。
#
# Codex 配置示例：
#   notify = ["powershell", "-ExecutionPolicy", "Bypass", "-File", "C:\\path\\to\\shell\\feishu_bot\\feishu_bot_codex_notify.ps1"]
#
# .env 配置示例：复制 shell/feishu_bot/.env.example 为同目录 .env 后填写真实值。
#   FEISHU_APP_ID=''
#   FEISHU_APP_SECRET=''
#   FEISHU_CHAT_ID=''
#   # FEISHU_OPEN_ID=''
#   # FEISHU_USER_ID=''
#   # FEISHU_EMAIL=''
#   # FEISHU_MOBILE=''
#   FEISHU_BOT_TIMEOUT='30'
#   FEISHU_CODEX_NOTIFY_TITLE='Codex 任务完成'
#   FEISHU_CODEX_NOTIFY_STATUS='已完成'
#   FEISHU_CODEX_NOTIFY_TEMPLATE='green'
#   FEISHU_CODEX_NOTIFY_FOOTER='由 Codex notify 自动发送'
#   FEISHU_CODEX_NOTIFY_MAX_CHARS='3500'
#   FEISHU_CODEX_NOTIFY_LOG_PATH=''
#
# 接收者配置规则：
#   FEISHU_CHAT_ID / FEISHU_OPEN_ID / FEISHU_USER_ID / FEISHU_EMAIL / FEISHU_MOBILE 只能启用一种。
#   FEISHU_EMAIL / FEISHU_MOBILE 需要应用开通 contact:user.id:readonly 权限。
#   FEISHU_CODEX_NOTIFY_LOG_PATH 为空时默认写入脚本目录 codex_notify.log。

$ScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultEnvFile = Join-Path $ScriptDir ".env"
$LegacyEnvFile = Join-Path $ScriptDir "feishu.env"
$EnvFile = if ($env:FEISHU_ENV_FILE) {
  $env:FEISHU_ENV_FILE
} elseif ($env:FEISHU_BOT_ENV_FILE) {
  $env:FEISHU_BOT_ENV_FILE
} else {
  $DefaultEnvFile
}

function Write-NotifyLog {
  param([string]$Message)

  $logPath = Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_LOG_PATH" (Join-Path $ScriptDir "codex_notify.log")
  if ([string]::IsNullOrWhiteSpace($logPath)) {
    $logPath = Join-Path $ScriptDir "codex_notify.log"
  }
  $logDir = Split-Path -Parent $logPath
  if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
  }
  Add-Content -LiteralPath $logPath -Value ("[{0}] {1}" -f (Get-Date -Format "o"), $Message)
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

function Invoke-FeishuJson {
  param(
    [string]$Uri,
    [object]$Body,
    [hashtable]$Headers = @{}
  )

  $jsonBody = $Body | ConvertTo-Json -Depth 30 -Compress
  # Windows PowerShell 直接发送字符串 Body 时中文可能按非 UTF-8 编码传输，飞书端会显示问号。
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

  # PowerShell 单元素管道会退化为 Hashtable，需强制包成数组，否则 Count 会变成键数量。
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

function Build-MarkdownFromPayload {
  param([object]$Event)

  if ([string]$Event.type -ne "agent-turn-complete") {
    return $null
  }

  $maxChars = [int](Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_MAX_CHARS" "3500")
  $status = Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_STATUS" "已完成"
  $footer = Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_FOOTER" "由 Codex notify 自动发送"
  $threadId = [string]$Event.'thread-id'
  $turnId = [string]$Event.'turn-id'
  $cwd = [string]$Event.cwd
  $lastMessage = ([string]$Event.'last-assistant-message').Trim()

  if ($lastMessage.Length -gt $maxChars) {
    $lastMessage = $lastMessage.Substring(0, $maxChars) + "`n`n...(已截断)"
  }
  if ([string]::IsNullOrWhiteSpace($lastMessage)) {
    $lastMessage = "_无最终回复内容_"
  }

  $cwdText = if ([string]::IsNullOrWhiteSpace($cwd)) { "-" } else { $cwd }
  $threadText = if ([string]::IsNullOrWhiteSpace($threadId)) { "-" } else { $threadId }
  $turnText = if ([string]::IsNullOrWhiteSpace($turnId)) { "-" } else { $turnId }

  return @(
    "**状态**：$status",
    "",
    "**工作目录**",
    "``$cwdText``",
    "",
    "**会话信息**",
    "- Thread：``$threadText``",
    "- Turn：``$turnText``",
    "",
    "---",
    "",
    "**最终回复**",
    "",
    $lastMessage,
    "",
    "---",
    "",
    $footer
  ) -join "`n"
}

function Get-NotifyTitle {
  param([string]$Cwd)

  $baseTitle = Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_TITLE" "Codex 任务完成"
  $normalizedCwd = $Cwd.Trim() -replace "[\\/]+$", ""
  $pushTime = Get-Date -Format "HH:mm:ss"
  if ([string]::IsNullOrWhiteSpace($normalizedCwd)) {
    return "{0} {1}" -f $baseTitle, $pushTime
  }

  # 兼容 Windows 和 Unix 路径，取工作目录最后一级作为通知标题前缀。
  $projectName = ($normalizedCwd -split "[\\/]+")[-1]
  if ([string]::IsNullOrWhiteSpace($projectName)) {
    return "{0} {1}" -f $baseTitle, $pushTime
  }
  return "[{0}] {1} {2}" -f $projectName, $baseTitle, $pushTime
}

function Send-MarkdownCard {
  param(
    [string]$Token,
    [hashtable]$Target,
    [string]$Markdown,
    [string]$Title
  )

  $title = if ([string]::IsNullOrWhiteSpace($Title)) { Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_TITLE" "Codex 任务完成" } else { $Title }
  $template = Get-EnvOrDefault "FEISHU_CODEX_NOTIFY_TEMPLATE" "green"
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
      title = @{ tag = "plain_text"; content = $title }
      template = $template
      padding = "12px 12px 12px 12px"
    }
  }

  $content = $card | ConvertTo-Json -Depth 30 -Compress
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
  if ([string]::IsNullOrWhiteSpace($Payload)) {
    throw "缺少 Codex notify payload"
  }

  Load-FeishuEnvFile -Path $EnvFile
  $event = $Payload | ConvertFrom-Json
  $markdown = Build-MarkdownFromPayload -Event $event
  if ($null -eq $markdown) {
    exit 0
  }

  $token = Get-TenantAccessToken
  $target = Resolve-ReceiveTarget -Token $token
  $title = Get-NotifyTitle -Cwd ([string]$event.cwd)
  Send-MarkdownCard -Token $token -Target $target -Markdown $markdown -Title $title
  Write-NotifyLog "sent"
} catch {
  Write-NotifyLog ("send_error=" + ($_.Exception.Message -replace "`r?`n", " "))
}

# notify hook 不应阻断 Codex 主流程。
exit 0
