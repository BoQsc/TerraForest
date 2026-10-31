# SPDX-License-Identifier: 0BSD
"""Exercise actual Windows Alt-Tab in an isolated temporary gameplay test.

Run while the test game can retain foreground. The fixture requests initial focus
before loading. Round trips never click or force activation, and keys are sent
only from the expected foreground game or the observed Alt-Tab destination.
"""
import argparse
import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import time

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("Requires the Windows desktop display driver")
    config, _ = parse_args([])
    engine = Path(config.godot).resolve()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_desktop_focus")
    folder.mkdir(parents=True)
    command, cache = command_for(engine, "focus_return", folder,
                                ["--gameplay-construction", "--no-zombies", "--desktop-focus-check"])
    details = dict(command=command, cache=cache, utc=stamp, **revision_metadata())
    if args.pack:
        verify_pack_native()
        pack = ROOT / "dist/TerraForest.pck"
        external = folder / "focus_return_external.gd"
        external.write_bytes((ROOT / "tests/focus_return.gd").read_bytes())
        command[command.index("--path") + 1] = str(ROOT / "dist")
        command[command.index("--script") + 1] = str(external)
        command[1:1] = ["--main-pack", str(pack)]
        details["pack_sha256"] = hashlib.sha256(pack.read_bytes()).hexdigest()
    details["engine_sha256"] = hashlib.sha256(engine.read_bytes()).hexdigest()
    details["test_sha256"] = hashlib.sha256((ROOT / "tests/focus_return.gd").read_bytes()).hexdigest()
    details["scope"] = "Fixture requests initial focus before loading; actual Windows task switching uses no click or forced activation. Temporary world."
    desktop = ctypes.WinDLL("user32", use_last_error=True)
    desktop.GetForegroundWindow.restype = wintypes.HWND
    desktop.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    desktop.keybd_event.argtypes = [wintypes.BYTE, wintypes.BYTE, wintypes.DWORD, ctypes.c_size_t]
    switches = []
    handled = 0

    def foreground():
        handle = desktop.GetForegroundWindow()
        pid = wintypes.DWORD()
        desktop.GetWindowThreadProcessId(handle, ctypes.byref(pid))
        return handle, pid.value

    def alt_tab():
        desktop.keybd_event(0x12, 0, 0, 0)
        try:
            desktop.keybd_event(0x09, 0, 0, 0)
            desktop.keybd_event(0x09, 0, 2, 0)
        finally:
            desktop.keybd_event(0x12, 0, 2, 0)

    def service_desktop():
        nonlocal handled
        log = (folder / "console.log").read_text(encoding="utf-8", errors="replace")
        markers = re.findall(r"DESKTOP_FOCUS_READY menu=(true|false) pid=(\d+)", log)
        if len(markers) <= handled:
            return False
        menu, expected_pid = markers[handled]
        before = foreground()
        if before[1] != int(expected_pid):
            return False  # The test times out; do not type into another app.
        handled += 1
        alt_tab()
        time.sleep(0.65)
        away = foreground()
        returned = away
        if away[0] and away[1] != int(expected_pid):
            # Return only if no intervening desktop activation changed the target.
            time.sleep(0.1)
            if foreground() == away:
                alt_tab()
                time.sleep(0.65)
                returned = foreground()
        switches.append(dict(menu=menu, before=before, away=away, returned=returned,
                             passed=away[1] != int(expected_pid) and returned[1] == int(expected_pid)))
        return False

    details["result"] = execute(command, folder, 150, "FOCUS_RETURN checks=42 failures=0", service_desktop)
    details["switches"] = switches
    details["result"]["passed"] &= len(switches) == 2 and all(row["passed"] for row in switches)
    (folder / "run.json").write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if details["result"]["passed"] else "FAIL ") + str(folder), flush=True)
    return 0 if details["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
