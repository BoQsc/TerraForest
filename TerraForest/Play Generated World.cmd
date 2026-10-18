@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Run Prepare Generated World.cmd first on a fresh installation. Existing progress is retained.
python "%~dp0tools\play_connected_world.py" --slot generated_world_v4 %*
set "GENERATION_EXIT=%ERRORLEVEL%"
if not "%GENERATION_EXIT%"=="0" pause
endlocal & exit /b %GENERATION_EXIT%
