@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_worlds.ps1" %*
set "WORLD_EXIT=%ERRORLEVEL%"
if not "%WORLD_EXIT%"=="0" pause
endlocal & exit /b %WORLD_EXIT%
