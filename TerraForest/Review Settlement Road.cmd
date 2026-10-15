@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
python "%~dp0tools\run_settlement_road_trip.py" --play
set "TRIP_EXIT=%ERRORLEVEL%"
if not "%TRIP_EXIT%"=="0" pause
endlocal & exit /b %TRIP_EXIT%
