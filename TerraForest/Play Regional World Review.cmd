@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Separate editable copy; frame-spike investigation remains open.
python "%~dp0tools\play_regional_review.py" %*
set "REVIEW_EXIT=%ERRORLEVEL%"
if not "%REVIEW_EXIT%"=="0" pause
endlocal & exit /b %REVIEW_EXIT%
