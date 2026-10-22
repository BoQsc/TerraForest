@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0..\..\tools\prepare_natural_cave.py"
if errorlevel 1 goto failed
python "%~dp0..\..\tools\run.py" --generator 6 --seed 1703 --slot natural_cave_gameplay --ground-cover --gameplay-construction %*
if errorlevel 1 goto failed
endlocal & exit /b 0
:failed
set "CAVE_EXIT=%ERRORLEVEL%"
pause
endlocal & exit /b %CAVE_EXIT%
