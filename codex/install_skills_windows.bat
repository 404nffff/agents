@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "LOCAL_SKILLS_ROOT=%SCRIPT_DIR%\skills"
set "TARGET_ROOT=%USERPROFILE%\.codex\skills"

set "DEFAULT_GITHUB_REPO=404nffff/agents"
set "DEFAULT_GITHUB_REF=master"
set "DEFAULT_GITHUB_SKILLS_PATH=codex/skills"

set "SOURCE_MODE="
set "GITHUB_REPO="
set "GITHUB_REF=%DEFAULT_GITHUB_REF%"
set "GITHUB_SKILLS_PATH=%DEFAULT_GITHUB_SKILLS_PATH%"
set "AUTO_YES=0"
set "REF_SET=0"
set "SKILLS_PATH_SET=0"

set "SKILLS_ROOT="
set "SOURCE_LABEL="
set "TMP_FETCH_DIR="

set /a SKILL_COUNT=0

if "%~1"=="" goto parse_done

:parse_loop
if "%~1"=="" goto parse_done
if /I "%~1"=="--github" (
  if "%~2"=="" (
    echo [ERROR] --github requires value.
    exit /b 1
  )
  set "SOURCE_MODE=github"
  set "GITHUB_REPO=%~2"
  shift
  shift
  goto parse_loop
)
if /I "%~1"=="--ref" (
  if "%~2"=="" (
    echo [ERROR] --ref requires value.
    exit /b 1
  )
  set "GITHUB_REF=%~2"
  set "REF_SET=1"
  shift
  shift
  goto parse_loop
)
if /I "%~1"=="--skills-path" (
  if "%~2"=="" (
    echo [ERROR] --skills-path requires value.
    exit /b 1
  )
  set "GITHUB_SKILLS_PATH=%~2"
  set "SKILLS_PATH_SET=1"
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
if "%REF_SET%"=="1" set "SOURCE_MODE=github"
if "%SKILLS_PATH_SET%"=="1" set "SOURCE_MODE=github"
if /I "%SOURCE_MODE%"=="github" if "%GITHUB_REPO%"=="" set "GITHUB_REPO=%DEFAULT_GITHUB_REPO%"

call :resolve_skills_root
if errorlevel 1 goto cleanup_error

call :discover_skills
if errorlevel 1 goto cleanup_error

call :interactive_select
if errorlevel 1 goto cleanup_error

call :install_selected
if errorlevel 1 goto cleanup_error

echo Done.
goto cleanup_ok

:usage
echo Usage:
echo   install_skills_windows.bat
echo   install_skills_windows.bat [--github ^<owner/repo^|https://github.com/owner/repo^>] [--ref ^<branch_or_tag^>] [--skills-path ^<path_in_repo^>]
echo   install_skills_windows.bat [--yes]
echo.
echo Options:
echo   --github      GitHub repository source
echo   --ref         Branch/tag, default: master
echo   --skills-path Skills path in repository, default: codex/skills
echo   --yes         Non-interactive mode, overwrite existing selected skills
exit /b 0

:resolve_skills_root
if /I "%SOURCE_MODE%"=="github" (
  echo Using remote source: %GITHUB_REPO%@%GITHUB_REF%:%GITHUB_SKILLS_PATH%
  call :fetch_remote_skills "%GITHUB_REPO%" "%GITHUB_REF%" "%GITHUB_SKILLS_PATH%"
  exit /b %ERRORLEVEL%
)

if exist "%LOCAL_SKILLS_ROOT%" (
  set "SKILLS_ROOT=%LOCAL_SKILLS_ROOT%"
  set "SOURCE_LABEL=Local %SKILLS_ROOT%"
  exit /b 0
)

echo Local skills not found. Fallback to remote: %DEFAULT_GITHUB_REPO%@%DEFAULT_GITHUB_REF%:%DEFAULT_GITHUB_SKILLS_PATH%
call :fetch_remote_skills "%DEFAULT_GITHUB_REPO%" "%DEFAULT_GITHUB_REF%" "%DEFAULT_GITHUB_SKILLS_PATH%"
exit /b %ERRORLEVEL%

:normalize_repo
set "REPO=%~1"
set "REPO=%REPO:https://github.com/=%"
set "REPO=%REPO:http://github.com/=%"
if /I "%REPO:~-4%"==".git" set "REPO=%REPO:~0,-4%"
set "%~2=%REPO%"
exit /b 0

:fetch_remote_skills
set "IN_REPO=%~1"
set "IN_REF=%~2"
set "IN_PATH=%~3"

call :normalize_repo "%IN_REPO%" NORMALIZED_REPO

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found. Remote skills requires git.
  exit /b 1
)

set "TMP_FETCH_DIR=%TEMP%\skills_repo_%RANDOM%_%RANDOM%"
set "CLONE_URL=https://github.com/%NORMALIZED_REPO%.git"
git clone --depth 1 --branch "%IN_REF%" "%CLONE_URL%" "%TMP_FETCH_DIR%" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Failed to clone %NORMALIZED_REPO% branch %IN_REF%.
  exit /b 1
)

set "SKILLS_ROOT=%TMP_FETCH_DIR%\%IN_PATH%"
if not exist "%SKILLS_ROOT%" (
  echo [ERROR] skills path not found in repo: %IN_PATH%
  exit /b 1
)

set "SOURCE_LABEL=Remote %NORMALIZED_REPO%@%IN_REF%:%IN_PATH%"
exit /b 0

:extract_field
set "%~3="
set "FIELD_VALUE="
for /f "usebackq tokens=1* delims=:" %%A in (`findstr /R /B /C:"%~2:" "%~1"`) do (
  set "FIELD_VALUE=%%B"
  goto extract_field_done
)

:extract_field_done
if defined FIELD_VALUE (
  if "!FIELD_VALUE:~0,1!"==" " set "FIELD_VALUE=!FIELD_VALUE:~1!"
  if "!FIELD_VALUE:~0,1!"=="'" set "FIELD_VALUE=!FIELD_VALUE:~1!"
  if "!FIELD_VALUE:~-1!"=="'" set "FIELD_VALUE=!FIELD_VALUE:~0,-1!"
  if "!FIELD_VALUE:~0,1!"=="^"" set "FIELD_VALUE=!FIELD_VALUE:~1!"
  if "!FIELD_VALUE:~-1!"=="^"" set "FIELD_VALUE=!FIELD_VALUE:~0,-1!"
  set "%~3=!FIELD_VALUE!"
)
set "FIELD_VALUE="
exit /b 0

:discover_skills
if not exist "%SKILLS_ROOT%" (
  echo [ERROR] skills root not found: %SKILLS_ROOT%
  exit /b 1
)

set /a SKILL_COUNT=0

for /d %%D in ("%SKILLS_ROOT%\*") do (
  set "SDIR=%%~fD"
  set "SFILE="
  if exist "!SDIR!\SKILL.md" set "SFILE=!SDIR!\SKILL.md"
  if not defined SFILE if exist "!SDIR!\skill.md" set "SFILE=!SDIR!\skill.md"
  if defined SFILE call :add_skill "!SDIR!" "!SFILE!"
)

if %SKILL_COUNT% LEQ 0 (
  echo [ERROR] No installable skills found in %SKILLS_ROOT%
  exit /b 1
)
exit /b 0

:add_skill
set "ADIR=%~1"
set "AFILE=%~2"
set "ANAME="
set "ADESC="
set "DUP=0"

call :extract_field "%AFILE%" "name" ANAME
call :extract_field "%AFILE%" "description" ADESC

if not defined ANAME (
  for %%N in ("%ADIR%") do set "ANAME=%%~nxN"
)
if not defined ADESC set "ADESC=(no description)"

for /L %%I in (1,1,%SKILL_COUNT%) do (
  call set "EXIST=%%SKILL_NAME_%%I%%"
  if /I "!EXIST!"=="!ANAME!" set "DUP=1"
)

if "!DUP!"=="1" (
  echo [WARN] Duplicate skill name "!ANAME!", skipped: %ADIR%
  exit /b 0
)

set /a SKILL_COUNT+=1
set "SKILL_NAME_%SKILL_COUNT%=!ANAME!"
set "SKILL_DESC_%SKILL_COUNT%=!ADESC!"
set "SKILL_DIR_%SKILL_COUNT%=!ADIR!"
set "SELECTED_%SKILL_COUNT%=0"
exit /b 0

:render_menu
echo.
echo Select skills to install ^(source: %SOURCE_LABEL%^) 
for /L %%I in (1,1,%SKILL_COUNT%) do (
  call set "NAME=%%SKILL_NAME_%%I%%"
  call set "DESC=%%SKILL_DESC_%%I%%"
  call set "SEL=%%SELECTED_%%I%%"
  if "!SEL!"=="1" (
    echo %%I. [x] !NAME!
  ) else (
    echo %%I. [ ] !NAME!
  )
  echo     !DESC!
)
echo.
echo Commands: numbers=toggle ^(support space/comma^), a=all, n=none, i=invert, d=install, q=quit
exit /b 0

:toggle_token
set "TOKEN=%~1"
if "%TOKEN%"=="" exit /b 0
for /f "delims=0123456789" %%X in ("%TOKEN%") do (
  if not "%%X"=="" (
    echo Invalid input: %TOKEN%
    exit /b 0
  )
)
set /a IDX=%TOKEN%
if %IDX% LSS 1 (
  echo Invalid index: %TOKEN%
  exit /b 0
)
if %IDX% GTR %SKILL_COUNT% (
  echo Invalid index: %TOKEN%
  exit /b 0
)
call set "CUR=%%SELECTED_%IDX%%%"
if "!CUR!"=="1" (
  set "SELECTED_%IDX%=0"
) else (
  set "SELECTED_%IDX%=1"
)
exit /b 0

:count_selected
set /a SELECTED_COUNT=0
for /L %%I in (1,1,%SKILL_COUNT%) do (
  call set "SEL=%%SELECTED_%%I%%"
  if "!SEL!"=="1" set /a SELECTED_COUNT+=1
)
exit /b 0

:interactive_select
:menu_loop
call :render_menu
set "INPUT="
set /p INPUT=^> 
if /I "%INPUT%"=="a" (
  for /L %%I in (1,1,%SKILL_COUNT%) do set "SELECTED_%%I=1"
  goto menu_loop
)
if /I "%INPUT%"=="n" (
  for /L %%I in (1,1,%SKILL_COUNT%) do set "SELECTED_%%I=0"
  goto menu_loop
)
if /I "%INPUT%"=="i" (
  for /L %%I in (1,1,%SKILL_COUNT%) do (
    call set "SEL=%%SELECTED_%%I%%"
    if "!SEL!"=="1" (set "SELECTED_%%I=0") else (set "SELECTED_%%I=1")
  )
  goto menu_loop
)
if /I "%INPUT%"=="d" (
  call :count_selected
  if %SELECTED_COUNT% LEQ 0 (
    echo Please select at least one skill.
    goto menu_loop
  )
  exit /b 0
)
if /I "%INPUT%"=="q" (
  echo Cancelled.
  exit /b 1
)

set "TOKENS=%INPUT:,= %"
for %%T in (!TOKENS!) do call :toggle_token "%%T"
goto menu_loop

:confirm
set "PROMPT=%~1"
set "CONFIRM_RESULT=N"
if "%AUTO_YES%"=="1" (
  set "CONFIRM_RESULT=Y"
  exit /b 0
)
choice /C YN /N /M "%PROMPT% [Y/N]"
if errorlevel 2 set "CONFIRM_RESULT=N"
if errorlevel 1 set "CONFIRM_RESULT=Y"
echo.
exit /b 0

:backup_config_env
set "BCFG_SRC=%~1"
set "BCFG_BAK=%~2"
set "BCFG_COUNT=0"
for /f "usebackq delims=" %%C in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$src=$env:BCFG_SRC;$bak=$env:BCFG_BAK;$c=0;if(Test-Path -LiteralPath $src){Get-ChildItem -LiteralPath $src -Recurse -File -Filter 'config.env' | ForEach-Object {$rel=$_.FullName.Substring($src.Length).TrimStart('\');$to=Join-Path $bak $rel;$dir=Split-Path -Parent $to;if(!(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};Copy-Item -LiteralPath $_.FullName -Destination $to -Force;$c++}};Write-Output $c"`) do (
  set "BCFG_COUNT=%%C"
)
set "%~3=%BCFG_COUNT%"
exit /b 0

:restore_config_env
set "RCFG_BAK=%~1"
set "RCFG_DST=%~2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$bak=$env:RCFG_BAK;$dst=$env:RCFG_DST;if(Test-Path -LiteralPath $bak){Get-ChildItem -LiteralPath $bak -Recurse -File -Filter 'config.env' | ForEach-Object {$rel=$_.FullName.Substring($bak.Length).TrimStart('\');$to=Join-Path $dst $rel;$dir=Split-Path -Parent $to;if(!(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};Copy-Item -LiteralPath $_.FullName -Destination $to -Force}}"
exit /b 0

:copy_skill_overlay
set "SRC=%~1"
set "DST=%~2"
set "KEEP_COUNT=0"
set "CFG_BAK=%TEMP%\skill_cfg_%RANDOM%_%RANDOM%"
mkdir "%CFG_BAK%" >nul 2>nul

if exist "%DST%" (
  call :backup_config_env "%DST%" "%CFG_BAK%" KEEP_COUNT
)

if not exist "%DST%" mkdir "%DST%" >nul 2>nul
xcopy "%SRC%\*" "%DST%\" /E /I /Y >nul

if %KEEP_COUNT% GTR 0 (
  call :restore_config_env "%CFG_BAK%" "%DST%"
)

rmdir /S /Q "%CFG_BAK%" >nul 2>nul
exit /b 0

:install_selected
if not exist "%TARGET_ROOT%" mkdir "%TARGET_ROOT%" >nul 2>nul

set /a INSTALLED=0
set /a OVERWRITTEN=0
set /a SKIPPED=0

echo.
echo Installing to: %TARGET_ROOT%

for /L %%I in (1,1,%SKILL_COUNT%) do (
  call set "SEL=%%SELECTED_%%I%%"
  if "!SEL!"=="1" (
    call set "NAME=%%SKILL_NAME_%%I%%"
    call set "SRC=%%SKILL_DIR_%%I%%"
    set "DST=%TARGET_ROOT%\!NAME!"

    if exist "!DST!" (
      call :confirm "Skill !NAME! exists. Overwrite?"
      if /I "!CONFIRM_RESULT!"=="Y" (
        call :copy_skill_overlay "!SRC!" "!DST!"
        if !KEEP_COUNT! GTR 0 (
          echo Overwritten: !NAME! ^(preserved local config.env^)
        ) else (
          echo Overwritten: !NAME!
        )
        set /a OVERWRITTEN+=1
      ) else (
        echo Skipped: !NAME!
        set /a SKIPPED+=1
      )
    ) else (
      call :copy_skill_overlay "!SRC!" "!DST!"
      echo Installed: !NAME!
      set /a INSTALLED+=1
    )
  )
)

echo.
echo Completed: installed !INSTALLED!, overwritten !OVERWRITTEN!, skipped !SKIPPED!.
exit /b 0

:cleanup_ok
if defined TMP_FETCH_DIR if exist "%TMP_FETCH_DIR%" rmdir /S /Q "%TMP_FETCH_DIR%" >nul 2>nul
exit /b 0

:cleanup_error
if defined TMP_FETCH_DIR if exist "%TMP_FETCH_DIR%" rmdir /S /Q "%TMP_FETCH_DIR%" >nul 2>nul
exit /b 1
