@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\prepare_geology_world.py" %*
set "CHECKPOINT_EXIT=%ERRORLEVEL%"
if not "%CHECKPOINT_EXIT%"=="0" pause
endlocal & exit /b %CHECKPOINT_EXIT%
