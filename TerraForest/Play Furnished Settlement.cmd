@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\play_connected_world.py" --furnished %*
set "FURNISHED_EXIT=%ERRORLEVEL%"
if not "%FURNISHED_EXIT%"=="0" pause
endlocal & exit /b %FURNISHED_EXIT%
