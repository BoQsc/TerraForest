@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\run.py" --generator 4 --seed 1703 --slot ground_cover_playtest --ground-cover %*
set "PLAYTEST_EXIT=%ERRORLEVEL%"
if not "%PLAYTEST_EXIT%"=="0" pause
endlocal & exit /b %PLAYTEST_EXIT%
