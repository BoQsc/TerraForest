@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Creates a separate save only when absent; existing progress is preserved.
python "%~dp0tools\prepare_combined_world.py" --destination mixed_neighborhood_review --layout mixed
if errorlevel 1 goto failed
python "%~dp0tools\run.py" --slot mixed_neighborhood_review --ground-cover --gameplay-construction --actors --vehicle-fleet %*
if errorlevel 1 goto failed
endlocal & exit /b 0
:failed
set "REVIEW_EXIT=%ERRORLEVEL%"
pause
endlocal & exit /b %REVIEW_EXIT%
