@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\check_enclosed_cottage.py" --tower --play
set "TOWER_EXIT=%ERRORLEVEL%"
if not "%TOWER_EXIT%"=="0" pause
endlocal & exit /b %TOWER_EXIT%
