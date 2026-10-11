@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Disposable dense woodland patch. No saved-world edits are written.
python "%~dp0tools\play_woodland.py" %*
set "WOODLAND_EXIT=%ERRORLEVEL%"
if not "%WOODLAND_EXIT%"=="0" pause
endlocal & exit /b %WOODLAND_EXIT%
