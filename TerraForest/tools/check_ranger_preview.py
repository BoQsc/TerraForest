# SPDX-License-Identifier: 0BSD
"""Render the Ranger in an offscreen, nonactivating window; retain dated evidence."""
import datetime
import json
import subprocess
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

config, _ = parse_args([])
folder = ROOT/'reports/ranger_preview_runs'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True)
command = [config.godot, '--path', str(ROOT), '--windowed', '--position', '-2400,-1600',
           '--resolution', '1280x720', '--max-fps', '60', '--script',
           'res://tools/preview_ranger_rifle.gd', '--log-file', str(folder/'engine.log'),
           '--', '--ranger-output='+folder.as_posix()]
original = subprocess.Popen


def nonactivating(*args, **kwargs):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 4
    kwargs['startupinfo'] = startup
    return original(*args, **kwargs)


subprocess.Popen = nonactivating
try:
    result = execute(command, folder, 60, 'RANGER_PREVIEW', require_resource_budget=True)
finally:
    subprocess.Popen = original
(folder/'run.json').write_text(json.dumps(dict(command=command, result=result, **revision_metadata()), indent=2))
print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
raise SystemExit(0 if result['passed'] else 1)
