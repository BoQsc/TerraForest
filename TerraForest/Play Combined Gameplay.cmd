@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem First run copies the furnished editor world; later runs retain separate gameplay progress.
python "%~dp0tools\play_connected_world.py" --generated-furnished --actors --vehicle-fleet --gameplay-copy %*
set "CHECKPOINT_EXIT=%ERRORLEVEL%"
if not "%CHECKPOINT_EXIT%"=="0" pause
endlocal & exit /b %CHECKPOINT_EXIT%
