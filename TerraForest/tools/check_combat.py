# SPDX-License-Identifier: 0BSD
"""Run the combat journey in a nonactivating private saved world with rendered evidence."""
import argparse
import datetime
import json
import hashlib
import subprocess
import uuid
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pack', action='store_true', help='Check the exported PCK with matching native libraries')
parser.add_argument('--executable', action='store_true', help='Use the existing root TerraForest.exe with the exported PCK; never replace it')
options = parser.parse_args()
pack = options.pack or options.executable
config, _ = parse_args([])
def sha256(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream, 'sha256').hexdigest()
native_hashes = verify_pack_native() if pack else {p.relative_to(ROOT).as_posix():sha256(p) for p in sorted((ROOT/'addons').glob('*/bin/*.dll'))}
project = ROOT/'dist' if pack else ROOT
engine = ROOT/'TerraForest.exe' if options.executable else config.godot
metadata = dict(pack=pack, executable=options.executable, native_sha256=native_hashes, script_sha256=sha256(ROOT/'tests/combat_world.gd'), **revision_metadata())
if pack:metadata['pack_sha256']=sha256(ROOT/'dist/TerraForest.pck')
if options.executable:metadata['executable_sha256']=sha256(engine)
folder = ROOT / 'reports/combat_world' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True)
token = uuid.uuid4().hex
base = [str(engine), '--path', str(project), '--windowed', '--position', '-2400,-1600', '--resolution', '1280x720', '--max-fps', '60']
if pack:base[1:1]=['--main-pack',str(ROOT/'dist/TerraForest.pck')]
driver = str(ROOT/'tests/combat_world.gd') if pack else 'res://tests/combat_world.gd'
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
        command=base+['--log-file',str(destination/'engine.log'),'--script',driver,'--','--zombies','--world-slot=Combat_'+token,'--derived-cache=user://combat_'+token,'--combat-output='+folder.as_posix(),'--combat-save-check']
        if phase=='restore':command.append('--combat-restore')
        result = execute(command, destination, 150, 'COMBAT_WORLD', require_resource_budget=True)
        results.append(dict(phase=phase,command=command,result=result))
        (folder/'run.json').write_text(json.dumps(dict(slot='Combat_'+token,results=results,**metadata),indent=2))
        if not result['passed']:break
finally:
    subprocess.Popen = original
print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
raise SystemExit(0 if result['passed'] else 1)
