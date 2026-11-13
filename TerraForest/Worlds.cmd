@echo off
rem SPDX-License-Identifier: 0BSD
rem Compatibility entry point; all preparation and UI belong to Godot.
"%~dp0TerraForest.exe" --path "%~dp0..\Launcher" -- %*
