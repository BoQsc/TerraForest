@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\play_checkpoint.py" %*
set "PLAYTEST_EXIT=%ERRORLEVEL%"
if not "%PLAYTEST_EXIT%"=="0" pause
endlocal & exit /b %PLAYTEST_EXIT%
