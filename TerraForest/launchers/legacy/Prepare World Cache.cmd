@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0..\..\tools\prepare_world_cache.py" %*
set "PREPARE_EXIT=%ERRORLEVEL%"
if not "%PREPARE_EXIT%"=="0" pause
endlocal & exit /b %PREPARE_EXIT%
