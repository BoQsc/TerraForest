@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0..\..\tools\play_terrain_neighborhood.py" --review-version 5 %*
set "REVIEW_EXIT=%ERRORLEVEL%"
if not "%REVIEW_EXIT%"=="0" pause
endlocal & exit /b %REVIEW_EXIT%
