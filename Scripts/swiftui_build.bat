@echo off
setlocal

set SCRIPT_DIR=%~dp0
set ROOT_DIR=%SCRIPT_DIR%..

where bash >nul 2>nul
if %ERRORLEVEL% neq 0 (
  echo bash was not found in PATH. Please install Git Bash or WSL and retry.
  exit /b 1
)

bash "%ROOT_DIR%\Scripts\swiftui_build.sh" %*
exit /b %ERRORLEVEL%
