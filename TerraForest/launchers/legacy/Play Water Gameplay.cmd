@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Separate persistent world. First visit creates a lake and provides a starter bucket.
python "%~dp0..\..\tools\run.py" --slot water_gameplay_v2 --gameplay-construction --water-gameplay %*
set "WATER_EXIT=%ERRORLEVEL%"
if not "%WATER_EXIT%"=="0" pause
endlocal & exit /b %WATER_EXIT%
