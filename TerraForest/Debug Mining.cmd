@echo off
cd /d "%~dp0"
python tools\debug_mining_visual.py
echo.
echo The report path is printed above. FAIL means the mining gates failed.
pause
