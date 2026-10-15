@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\run.py" --scene worlds %*
set "WORLD_EXIT=%ERRORLEVEL%"
if not "%WORLD_EXIT%"=="0" pause
endlocal & exit /b %WORLD_EXIT%
