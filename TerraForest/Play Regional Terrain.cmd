@echo off
setlocal
rem SPDX-License-Identifier: 0BSD
rem Optional: set GODOT_EXE to a compatible Godot 4.7 executable.
if not defined GODOT_EXE set "GODOT_EXE=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if not exist "%GODOT_EXE%" (
    echo Godot was not found at "%GODOT_EXE%".
    echo Set GODOT_EXE to your Godot 4.7 executable and try again.
    pause
    exit /b 1
)
if not exist "%~dp0reports" mkdir "%~dp0reports"
echo Starting regional terrain: 1920x1080 fullscreen, V-Sync, 60 FPS cap.
echo Temporary playtest: world edits will NOT be saved.
echo Engine log: "%~dp0reports\regional-playtest.log"
"%GODOT_EXE%" --path "%~dp0." --rendering-method forward_plus --fullscreen --resolution 1920x1080 --log-file "%~dp0reports\regional-playtest.log" res://demo/world.tscn -- --region-terrain --temporary --human-playtest --max-fps=60
if errorlevel 1 (
    echo The playtest exited with an error. See the engine log above.
    pause
    exit /b 1
)
endlocal
