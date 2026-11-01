# SPDX-License-Identifier: 0BSD
"""Run the combat journey in a nonactivating temporary world with rendered evidence."""
import datetime
import json
import hashlib
import subprocess
import uuid
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

config, _ = parse_args([])
folder = ROOT / 'reports/combat_world' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True)
token = uuid.uuid4().hex
native_hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'addons/player_runtime/bin').glob('*.dll')}
base = [config.godot, '--path', str(ROOT), '--windowed', '--position', '-2400,-1600', '--resolution', '1280x720', '--max-fps', '60']
original = subprocess.Popen
def nonactivating(*args, **kwargs):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 4
    kwargs['startupinfo'] = startup
    return original(*args, **kwargs)
subprocess.Popen = nonactivating
try:
    results=[]
    for phase in ['create','restore']:
        destination=folder/phase;destination.mkdir()
        command=base+['--log-file',str(destination/'engine.log'),'--script','res://tests/combat_world.gd','--','--zombies','--world-slot=Combat_'+token,'--derived-cache=user://combat_'+token,'--combat-output='+folder.as_posix(),'--combat-save-check']
        if phase=='restore':command.append('--combat-restore')
        result = execute(command, destination, 150, 'COMBAT_WORLD')
        results.append(dict(phase=phase,command=command,result=result))
        (folder/'run.json').write_text(json.dumps(dict(slot='Combat_'+token,native_sha256=native_hashes,results=results,**revision_metadata()),indent=2))
        if not result['passed']:break
finally:
    subprocess.Popen = original
print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
raise SystemExit(0 if result['passed'] else 1)
