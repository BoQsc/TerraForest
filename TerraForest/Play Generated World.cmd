@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\run.py" --generator 3 --seed 1703 %*
if errorlevel 1 pause
endlocal
