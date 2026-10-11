@echo off
setlocal
cd /d "%~dp0"
python "%~dp0tools\prepare_water_world.py" %*
if errorlevel 1 pause
endlocal
