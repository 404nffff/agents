param(
  [Parameter(Position = 0)]
  [string]$Payload,

  [Alias("h")]
  [switch]$Help,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArguments
)

$ErrorActionPreference = "Stop"

# Codex hooks 通用入口：安装 hooks 配置，或把 stdin/file payload 交给 Python 事件层。
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyHook = Join-Path $ScriptDir "hook.py"

function Show-Usage {
  $scriptName = Split-Path -Leaf $MyInvocation.ScriptName
  @"
用法:
  .\$scriptName create [win]
  .\$scriptName [hook-json-file]
  .\$scriptName -h|--help

说明:
  通用 Codex hooks 入口。事件处理在 hook.py，通知渠道通过 plugins/ 插件调用。
  插件通过 CODEX_HOOK_EVENTS='事件:插件列表;事件:插件列表' 配置。

动作:
  create              生成 Windows PowerShell hooks 配置
  create win          同 create
  hook-json-file      从指定 JSON 文件读取 hook payload，便于本地调试

常用环境变量:
  CODEX_HOOK_EVENTS                  事件到插件路由，例如 Stop:feishu,xxxx;SessionStart:feishu
  CODEX_HOOK_PAYLOAD_LOG_PATH        脱敏 payload 日志路径
  FEISHU_CODEX_HOOK_ENABLE_PUSH      true 时由 feishu 插件发送飞书通知
"@
}

function New-HookCommand {
  $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "codex_hook.ps1"))
  return 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath
}

function Write-HooksJsonFile {
  param([string]$CommandText)

  $outputDir = Join-Path $HOME ".codex"
  $outputPath = Join-Path $outputDir "hooks.json"
  if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }

  $hookEvents = @(
    @{ Name = "SessionStart"; Matcher = $false },
    @{ Name = "SubagentStart"; Matcher = $false },
    @{ Name = "PreToolUse"; Matcher = $true },
    @{ Name = "PermissionRequest"; Matcher = $true },
    @{ Name = "PostToolUse"; Matcher = $true },
    @{ Name = "PreCompact"; Matcher = $false },
    @{ Name = "PostCompact"; Matcher = $false },
    @{ Name = "UserPromptSubmit"; Matcher = $false },
    @{ Name = "SubagentStop"; Matcher = $false },
    @{ Name = "Stop"; Matcher = $false }
  )

  $hooks = [ordered]@{}
  foreach ($hookEvent in $hookEvents) {
    $item = [ordered]@{
      hooks = @(
        [ordered]@{
          type = "command"
          command = $CommandText
        }
      )
    }
    if ($hookEvent.Matcher) {
      $item.matcher = "*"
    }
    $hooks[$hookEvent.Name] = @($item)
  }

  [ordered]@{ hooks = $hooks } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputPath -Encoding utf8
  Write-Output "已生成 win hooks 配置:"
  Write-Output "  $outputPath"
}

function New-HooksJsonFile {
  param([string]$Platform = "win")

  if ([string]::IsNullOrWhiteSpace($Platform)) {
    $Platform = "win"
  }
  if ($Platform -ne "win") {
    throw "PowerShell 版只支持 create win；Linux/macOS 请使用 codex_hook.sh create linux"
  }
  Write-HooksJsonFile -CommandText (New-HookCommand)
}

function Invoke-PythonHook {
  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
  }
  if (-not $python -or -not (Test-Path -LiteralPath $PyHook)) {
    return
  }

  try {
    if (-not [string]::IsNullOrWhiteSpace($Payload)) {
      & $python.Source $PyHook $Payload | Out-Null
      return
    }

    $stdin = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($stdin)) {
      return
    }
    $temp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($temp, $stdin, [System.Text.UTF8Encoding]::new($false))
    try {
      & $python.Source $PyHook $temp | Out-Null
    } finally {
      Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
  } catch {}
}

if ($Help -or $Payload -in @("--help", "help")) {
  Show-Usage
  exit 0
}

if ($Payload -eq "create") {
  $platform = if ($RemainingArguments.Count -ge 1) { [string]$RemainingArguments[0] } else { "win" }
  New-HooksJsonFile -Platform $platform
  exit 0
}

Invoke-PythonHook
exit 0
