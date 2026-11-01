#!/usr/bin/env pythonw
"""Windowed launcher for install_to_steam: no console, approval and bar in Tk.

Double-click it (or run it with pythonw) and the Tk window explains that TerraForest is
added as a non-Steam game and that Steam must restart, then shows the same progress bar
the console build draws. Command-line flags still work: pythonw install_to_steam.pyw
--last-world --artwork. Output goes to steam/logs/gui.log, never to a command prompt.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE/'lib')]

if __name__ == '__main__':
    import steam_gui
    raise SystemExit(steam_gui.launch('install_to_steam', sys.argv[1:]))
