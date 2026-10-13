@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Disposable normal world; no player saves are loaded or changed.
python "%~dp0tools\run.py" --temporary --slot water_bucket_review --gameplay-construction --water-gameplay --water-bucket-review %*
set "WATER_EXIT=%ERRORLEVEL%"
if not "%WATER_EXIT%"=="0" pause
endlocal & exit /b %WATER_EXIT%
