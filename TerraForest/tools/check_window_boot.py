# SPDX-License-Identifier: 0BSD
"""Observe native Windows startup in both saved modes using isolated APPDATA."""
import argparse
import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

from run import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Native Windows window sampling is required')
    folder = ROOT / 'reports/window_boot' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    environment = dict(os.environ, APPDATA=str(folder / 'appdata'))
    config = folder / 'appdata/Godot/app_userdata/TerraForest/graphics.cfg'
    writer = folder / 'save.gd'
    writer.write_text('''# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var policy=load("res://addons/presentation/fullscreen_policy.gd")
 quit(policy.save_fullscreen_preference("--fullscreen-preference" in OS.get_cmdline_user_args()))
''', encoding='utf-8')
    base = [str(ROOT / 'TerraForest.exe'), '--path', str(ROOT)]
    if args.pack:
        base += ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
    user32 = ctypes.windll.user32
    user32.SetProcessDPIAware()
    user32.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.GetWindowLongW.restype = ctypes.c_long
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    results = []
    for preference in (False, True, None):
        label = 'default' if preference is None else ('fullscreen' if preference else 'windowed')
        if preference is None:
            config.unlink(missing_ok=True)
        else:
            save = subprocess.run(base + ['--headless', '--script', str(writer), '--'] +
                                  (['--fullscreen-preference'] if preference else []),
                                  env=environment, cwd=ROOT, capture_output=True, text=True, timeout=30)
            (folder / (label + '_save.log')).write_text(save.stdout + save.stderr, encoding='utf-8')
            if save.returncode or 'ERROR:' in save.stdout + save.stderr:
                raise RuntimeError('Could not persist isolated preference; see ' + str(folder))
        command = base + ['--max-fps', '60', '--quit-after', '120', '--log-file', str(folder / (label + '.log'))]
        observations = []
        expected_caption = preference is False
        with (folder / (label + '_console.log')).open('w', encoding='utf-8') as output:
            process = subprocess.Popen(command, env=environment, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            started = time.monotonic()
            captured = False
            try:
                while process.poll() is None and time.monotonic() - started < 30:
                    def visit(hwnd, _):
                        pid = wintypes.DWORD()
                        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                        if pid.value == process.pid and user32.IsWindowVisible(hwnd):
                            rect = wintypes.RECT()
                            user32.GetWindowRect(hwnd, ctypes.byref(rect))
                            style = user32.GetWindowLongW(hwnd, -16) & 0xffffffff
                            observations.append(dict(seconds=round(time.monotonic() - started, 4),
                                                     caption=style & 0x00c00000 == 0x00c00000,
                                                     rect=[rect.left, rect.top, rect.right, rect.bottom]))
                        return True
                    user32.EnumWindows(callback_type(visit), 0)
                    if observations and not captured and observations[-1]['seconds'] - observations[0]['seconds'] > 1.5:
                        from PIL import ImageGrab
                        ImageGrab.grab(bbox=tuple(observations[-1]['rect'])).save(folder / (label + '.png'))
                        captured = True
                    time.sleep(.005)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        diagnostics = (folder / (label + '_console.log')).read_text(errors='replace') + (folder / (label + '.log')).read_text(errors='replace')
        errors = [line for line in diagnostics.splitlines() if line.startswith(('SCRIPT ERROR', 'ERROR:', 'WARNING: ObjectDB'))]
        mismatches = sum(row['caption'] != expected_caption for row in observations)
        passed = process.returncode == 0 and bool(observations) and mismatches == 0 and not errors
        results.append(dict(label=label, command=command, samples=len(observations), mismatches=mismatches,
                            passed=passed, errors=errors, observations=observations, exit_code=process.returncode))
        print(f'{"PASS" if passed else "FAIL"} {label}: {len(observations)} samples, {mismatches} wrong-mode samples', flush=True)
    metadata = dict(pack=args.pack, results=results, appdata=environment['APPDATA'],
                    exe_sha256=hashlib.sha256((ROOT / 'TerraForest.exe').read_bytes()).hexdigest())
    if args.pack:
        metadata['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
    (folder / 'run.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(folder)
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
