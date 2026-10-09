@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\play_connected_world.py" %*
set "CONNECTED_EXIT=%ERRORLEVEL%"
if not "%CONNECTED_EXIT%"=="0" pause
endlocal & exit /b %CONNECTED_EXIT%
