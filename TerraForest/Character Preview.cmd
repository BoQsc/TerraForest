@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
pushd "%~dp0"
python tools\run.py --temporary --gameplay-construction --zombies %*
set "CHARACTER_EXIT=%ERRORLEVEL%"
popd
if not "%CHARACTER_EXIT%"=="0" pause
endlocal & exit /b %CHARACTER_EXIT%
