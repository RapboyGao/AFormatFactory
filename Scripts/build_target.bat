@echo off
setlocal

set SCRIPT_DIR=%~dp0
set ROOT_DIR=%SCRIPT_DIR%..
set TARGET=%1
if "%TARGET%"=="" set TARGET=tauri

where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
  echo node was not found in PATH.
  exit /b 1
)

node "%ROOT_DIR%\Scripts\build_target.mjs" %TARGET%
exit /b %ERRORLEVEL%
