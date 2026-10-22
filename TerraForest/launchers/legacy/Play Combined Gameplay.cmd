@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Default retains combined gameplay progress. --slot NAME opens an existing save directly.
python "%~dp0..\..\tools\play_connected_world.py" --generated-furnished --actors --vehicle-fleet --gameplay-copy %*
set "CHECKPOINT_EXIT=%ERRORLEVEL%"
if not "%CHECKPOINT_EXIT%"=="0" pause
endlocal & exit /b %CHECKPOINT_EXIT%
