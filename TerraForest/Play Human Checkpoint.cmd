@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\play_checkpoint.py" %*
if errorlevel 1 pause
endlocal
