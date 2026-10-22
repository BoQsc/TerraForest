@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0..\..\tools\prepare_combined_world.py" --layout districts --destination generated_world_v4 %*
set "GENERATION_EXIT=%ERRORLEVEL%"
if not "%GENERATION_EXIT%"=="0" pause
endlocal & exit /b %GENERATION_EXIT%
