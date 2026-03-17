@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "DEFAULT_REMOTE_SOURCE=https://raw.githubusercontent.com/404nffff/agents/master/codex/AGENTS.md"
set "TARGET_USER_FILE=%USERPROFILE%\.codex\AGENTS.md"
set "SOURCE_MODE="
set "SOURCE_INPUT="
set "GITHUB_REPO="
set "GITHUB_REF=main"
set "GITHUB_FILE=AGENTS.md"
set "AUTO_YES=0"

if "%~1"=="" goto parse_done

:parse_loop
if "%~1"=="" goto parse_done
if /I "%~1"=="--source" (
  set "SOURCE_MODE=source"
  set "SOURCE_INPUT=%~2"
  shift
  shift
  goto parse_loop
)
if /I "%~1"=="--github" (
  set "SOURCE_MODE=github"
  set "GITHUB_REPO=%~2"
  shift
  shift
  goto parse_loop
)
if /I "%~1"=="--ref" (
  set "GITHUB_REF=%~2"
  shift
  shift
  goto parse_loop
)
if /I "%~1"=="--file" (
  set "GITHUB_FILE=%~2"
  shift
  shift
  goto parse_loop
)
if /I "%~1"=="--yes" (
  set "AUTO_YES=1"
  shift
  goto parse_loop
)
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

echo [ERROR] Unknown argument: %~1
goto usage

:parse_done
if /I "%SOURCE_MODE%"=="source" if "%SOURCE_INPUT%"=="" (
  echo [ERROR] --source requires a value.
  exit /b 1
)
if /I "%SOURCE_MODE%"=="github" if "%GITHUB_REPO%"=="" (
  echo [ERROR] --github requires a value.
  exit /b 1
)

set "TMP_SOURCE=%TEMP%\agents_source_%RANDOM%_%RANDOM%.md"

call :fetch_source "%TMP_SOURCE%"
if errorlevel 1 exit /b 1

echo Preparing AGENTS.md ...
call :install_target "%TARGET_USER_FILE%" "~/.codex/AGENTS.md" "%TMP_SOURCE%"
if errorlevel 1 goto cleanup

if "%AUTO_YES%"=="1" (
  call :install_target "%CD%\AGENTS.md" "current directory AGENTS.md" "%TMP_SOURCE%"
) else (
  call :confirm "Generate or update AGENTS.md in current directory?"
  if "!CONFIRM_RESULT!"=="Y" (
    call :install_target "%CD%\AGENTS.md" "current directory AGENTS.md" "%TMP_SOURCE%"
  ) else (
    echo Skipped current directory AGENTS.md
  )
)

echo Done.
set "EXIT_CODE=0"
goto cleanup

:usage
echo Usage:
echo   install_agents_windows.bat [--source ^<path_or_url^>]
echo   install_agents_windows.bat [--github ^<owner/repo^|https://github.com/owner/repo^>] [--ref ^<branch_or_tag^>] [--file ^<path_in_repo^>]
echo   install_agents_windows.bat [--yes]
echo.
echo Options:
echo   --source   Source AGENTS.md from local path or URL
echo   --github   GitHub repository source
echo   --ref      Branch/tag, default: main
echo   --file     File path in repository, default: AGENTS.md
echo   --yes      Non-interactive mode, auto replace when needed
exit /b 0

:fetch_source
set "OUT_FILE=%~1"

if /I "%SOURCE_MODE%"=="source" (
  echo %SOURCE_INPUT% | findstr /I /R "^https\?://" >nul
  if not errorlevel 1 (
    call :download_file "%SOURCE_INPUT%" "%OUT_FILE%"
    exit /b %ERRORLEVEL%
  )
  if not exist "%SOURCE_INPUT%" (
    echo [ERROR] Source file not found: %SOURCE_INPUT%
    exit /b 1
  )
  copy /Y "%SOURCE_INPUT%" "%OUT_FILE%" >nul
  exit /b 0
)

if /I "%SOURCE_MODE%"=="github" (
  set "REPO=%GITHUB_REPO%"
  set "REPO=!REPO:https://github.com/=!"
  set "REPO=!REPO:http://github.com/=!"
  if "!REPO:~-4!"==".git" set "REPO=!REPO:~0,-4!"
  set "RAW_URL=https://raw.githubusercontent.com/!REPO!/%GITHUB_REF%/%GITHUB_FILE%"
  call :download_file "!RAW_URL!" "%OUT_FILE%"
  exit /b %ERRORLEVEL%
)

echo No source specified, using default repository source: %DEFAULT_REMOTE_SOURCE%
call :download_file "%DEFAULT_REMOTE_SOURCE%" "%OUT_FILE%"
if errorlevel 1 (
  echo [ERROR] Unable to fetch default repository source.
  exit /b 1
)
exit /b 0

:download_file
set "URL=%~1"
set "OUT_FILE=%~2"

where curl.exe >nul 2>nul
if not errorlevel 1 (
  curl.exe -fsSL "%URL%" -o "%OUT_FILE%"
  if not errorlevel 1 exit /b 0
)

where powershell.exe >nul 2>nul
if not errorlevel 1 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%OUT_FILE%'; exit 0 } catch { exit 1 }"
  if not errorlevel 1 exit /b 0
)

echo [ERROR] Failed to download: %URL%
exit /b 1

:install_target
set "TARGET=%~1"
set "LABEL=%~2"
set "NEW_FILE=%~3"

for %%I in ("%TARGET%") do if not exist "%%~dpI" mkdir "%%~dpI" >nul 2>nul

if exist "%TARGET%" (
  echo %LABEL% exists: %TARGET%
  fc /b "%TARGET%" "%NEW_FILE%" >nul
  if not errorlevel 1 (
    echo Old and new files are identical. Skip replace %LABEL%.
    exit /b 0
  )
  call :preview_file "%TARGET%" "Old file preview"
  call :preview_file "%NEW_FILE%" "New file preview"

  if "%AUTO_YES%"=="1" (
    copy /Y "%NEW_FILE%" "%TARGET%" >nul
    echo Replaced %LABEL%: %TARGET%
    exit /b 0
  )

  call :confirm "Replace %LABEL%?"
  if "!CONFIRM_RESULT!"=="Y" (
    copy /Y "%NEW_FILE%" "%TARGET%" >nul
    echo Replaced %LABEL%: %TARGET%
  ) else (
    echo Skipped replace %LABEL%
  )
  exit /b 0
)

copy /Y "%NEW_FILE%" "%TARGET%" >nul
echo Created %LABEL%: %TARGET%
exit /b 0

:preview_file
set "FILE_PATH=%~1"
set "TITLE=%~2"
echo ----- %TITLE% (first 20 lines): %FILE_PATH% -----
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-Content -LiteralPath '%FILE_PATH%' -TotalCount 20"
echo -------------------------------------------
exit /b 0

:confirm
set "PROMPT=%~1"
set "CONFIRM_RESULT=N"
choice /C YN /N /M "%PROMPT% [Y/N]"
if errorlevel 2 set "CONFIRM_RESULT=N"
if errorlevel 1 set "CONFIRM_RESULT=Y"
echo.
exit /b 0

:cleanup
if exist "%TMP_SOURCE%" del /f /q "%TMP_SOURCE%" >nul 2>nul
if not defined EXIT_CODE set "EXIT_CODE=1"
exit /b %EXIT_CODE%
