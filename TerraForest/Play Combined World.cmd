@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Opens the existing generated furnished world with actors, interactive ground cover and bounded vehicle fleet enabled.
python "%~dp0tools\play_connected_world.py" --generated-furnished --actors --vehicle-fleet %*
set "CHECKPOINT_EXIT=%ERRORLEVEL%"
if not "%CHECKPOINT_EXIT%"=="0" pause
endlocal & exit /b %CHECKPOINT_EXIT%
