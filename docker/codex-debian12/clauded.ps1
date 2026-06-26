$ErrorActionPreference = "Stop"

$Container = $env:CLAUDE_DOCKER_CONTAINER
$HostRoot = $env:CLAUDE_HOST_ROOT
$ContainerRoot = $env:CLAUDE_CONTAINER_ROOT
$InstallPath = $false
$PrintPath = $false
$DryRun = $false
$ClaudeArgs = @()

$index = 0
while ($index -lt $args.Count) {
  $arg = [string]$args[$index]
  switch -Exact ($arg) {
    "-Container" {
      $index++
      if ($index -ge $args.Count) { throw "-Container 需要容器名" }
      $Container = [string]$args[$index]
    }
    "-HostRoot" {
      $index++
      if ($index -ge $args.Count) { throw "-HostRoot 需要宿主根目录" }
      $HostRoot = [string]$args[$index]
    }
    "-ContainerRoot" {
      $index++
      if ($index -ge $args.Count) { throw "-ContainerRoot 需要容器根目录" }
      $ContainerRoot = [string]$args[$index]
    }
    "-InstallPath" {
      $InstallPath = $true
    }
    "-PrintPath" {
      $PrintPath = $true
    }
    "-DryRun" {
      $DryRun = $true
    }
    "--" {
      for ($rest = $index + 1; $rest -lt $args.Count; $rest++) {
        $ClaudeArgs += [string]$args[$rest]
      }
      $index = $args.Count
      continue
    }
    default {
      $ClaudeArgs += $arg
    }
  }
  $index++
}

if ([string]::IsNullOrWhiteSpace($Container)) {
  $Container = "codex"
}
if ([string]::IsNullOrWhiteSpace($HostRoot)) {
  $HostRoot = "D:\www"
}
if ([string]::IsNullOrWhiteSpace($ContainerRoot)) {
  $ContainerRoot = "/workspace"
}

function Normalize-WindowsPath {
  param([string]$Path)

  try {
    return (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd("\")
  } catch {
    throw "路径不存在: $Path"
  }
}

function Add-DirectoryToUserPath {
  param([string]$Directory)

  $resolvedDirectory = Normalize-WindowsPath $Directory
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ([string]::IsNullOrWhiteSpace($userPath)) {
    $userPath = ""
  }

  $items = @()
  foreach ($item in ($userPath -split ";")) {
    if (-not [string]::IsNullOrWhiteSpace($item)) {
      $items += $item.Trim()
    }
  }

  $dedupedItems = @()
  foreach ($item in $items) {
    try {
      if ((Normalize-WindowsPath $item).ToLowerInvariant() -eq $resolvedDirectory.ToLowerInvariant()) {
        continue
      }
      $dedupedItems += $item
    } catch {
      $dedupedItems += $item
    }
  }

  $newItems = @($resolvedDirectory) + $dedupedItems
  $newPath = if ($newItems.Count -gt 0) {
    ($newItems -join ";")
  } else {
    $resolvedDirectory
  }

  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  $env:Path = $resolvedDirectory + ";" + $env:Path
  Write-Output "已加入用户 PATH 最前面: $resolvedDirectory"
  Write-Output "新终端生效；当前终端可临时执行: `$env:Path = '$resolvedDirectory;' + `$env:Path"
}

function ConvertTo-ContainerPath {
  param(
    [string]$CurrentPath,
    [string]$ResolvedHostRoot,
    [string]$TargetRoot
  )

  $rootWithSlash = $ResolvedHostRoot.TrimEnd("\") + "\"
  $currentLower = $CurrentPath.ToLowerInvariant()
  $rootLower = $ResolvedHostRoot.ToLowerInvariant()
  $rootWithSlashLower = $rootWithSlash.ToLowerInvariant()

  if ($currentLower -eq $rootLower) {
    return $TargetRoot.TrimEnd("/")
  }

  if (-not $currentLower.StartsWith($rootWithSlashLower)) {
    return $null
  }

  $relativePath = $CurrentPath.Substring($rootWithSlash.Length).Replace("\", "/")
  return ($TargetRoot.TrimEnd("/") + "/" + $relativePath)
}

function Quote-Sh {
  param([string]$Value)

  return "'" + ($Value -replace "'", "'`"`"'") + "'"
}

function Invoke-DockerText {
  param([string[]]$DockerArgs)

  $output = & docker @DockerArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker 命令失败: docker $($DockerArgs -join ' ')"
  }
  return ($output | Select-Object -First 1)
}

function Find-ContainerPathByName {
  param(
    [string]$DirectoryName,
    [string]$TargetRoot
  )

  $quotedRoot = Quote-Sh $TargetRoot
  $quotedName = Quote-Sh $DirectoryName
  $script = "find $quotedRoot -maxdepth 4 -type d -name $quotedName -print -quit 2>/dev/null"
  return Invoke-DockerText @("exec", $Container, "sh", "-lc", $script)
}

if ($InstallPath) {
  Add-DirectoryToUserPath $PSScriptRoot
  exit 0
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "未找到 docker 命令，请先安装 Docker 或把 docker 加入 PATH。"
}

$running = (& docker inspect -f "{{.State.Running}}" $Container 2>$null)
if ($LASTEXITCODE -ne 0) {
  throw "容器不存在: $Container，可用 CLAUDE_DOCKER_CONTAINER 指定容器名。"
}
if ($running -ne "true") {
  throw "容器未运行: $Container"
}

$currentPath = Normalize-WindowsPath (Get-Location).ProviderPath
$resolvedHostRoot = Normalize-WindowsPath $HostRoot
$containerPath = ConvertTo-ContainerPath $currentPath $resolvedHostRoot $ContainerRoot

if ([string]::IsNullOrWhiteSpace($containerPath)) {
  $containerPath = Find-ContainerPathByName (Split-Path -Leaf $currentPath) $ContainerRoot
}

if ([string]::IsNullOrWhiteSpace($containerPath)) {
  throw "无法把当前目录映射到 $ContainerRoot：$currentPath"
}

$quotedContainerPath = Quote-Sh $containerPath
$existsScript = "[ -d $quotedContainerPath ]"
& docker exec $Container sh -lc $existsScript | Out-Null
if ($LASTEXITCODE -ne 0) {
  $fallbackPath = Find-ContainerPathByName (Split-Path -Leaf $currentPath) $ContainerRoot
  if (-not [string]::IsNullOrWhiteSpace($fallbackPath)) {
    $containerPath = $fallbackPath
    $quotedContainerPath = Quote-Sh $containerPath
  } else {
    throw "容器内目录不存在: $containerPath"
  }
}

if ($PrintPath) {
  Write-Output $containerPath
  exit 0
}

$quotedArgs = @()
foreach ($arg in $ClaudeArgs) {
  $quotedArgs += (Quote-Sh $arg)
}

$claudeCommand = "cd $quotedContainerPath && exec claude --dangerously-skip-permissions"
if ($quotedArgs.Count -gt 0) {
  $claudeCommand += " " + ($quotedArgs -join " ")
}

if ($DryRun) {
  Write-Output ("docker exec {0} zsh -ic {1}" -f $Container, (Quote-Sh $claudeCommand))
  exit 0
}

$execArgs = @("exec")
if (-not [Console]::IsInputRedirected) {
  $execArgs += "-i"
}
if (-not [Console]::IsOutputRedirected) {
  $execArgs += "-t"
}
$execArgs += @($Container, "zsh", "-ic", $claudeCommand)

& docker @execArgs
exit $LASTEXITCODE
