@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0..\..\tools\check_enclosed_cottage.py" --play
set "BUILDING_EXIT=%ERRORLEVEL%"
if not "%BUILDING_EXIT%"=="0" pause
endlocal & exit /b %BUILDING_EXIT%
