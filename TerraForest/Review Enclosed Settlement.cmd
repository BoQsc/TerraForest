@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Preparation preserves an existing review save and all normal gameplay saves.
python "%~dp0tools\prepare_combined_world.py" --destination combined_enclosed_review
if errorlevel 1 goto failed
python "%~dp0tools\run.py" --slot combined_enclosed_review --ground-cover --gameplay-construction --actors --vehicle-fleet %*
if errorlevel 1 goto failed
endlocal & exit /b 0
:failed
set "REVIEW_EXIT=%ERRORLEVEL%"
pause
endlocal & exit /b %REVIEW_EXIT%
