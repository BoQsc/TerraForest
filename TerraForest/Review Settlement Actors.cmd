@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\run_settlement_actor_authoring.py" --play
set "ACTOR_EXIT=%ERRORLEVEL%"
if not "%ACTOR_EXIT%"=="0" pause
endlocal & exit /b %ACTOR_EXIT%
