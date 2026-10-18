@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\prepare_combined_world.py" --layout regional --destination generated_world %*
set "GENERATION_EXIT=%ERRORLEVEL%"
if not "%GENERATION_EXIT%"=="0" pause
endlocal & exit /b %GENERATION_EXIT%
