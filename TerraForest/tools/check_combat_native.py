# SPDX-License-Identifier: 0BSD
"""Check combat storage and support rules in an isolated debug or release runtime."""
import argparse
import datetime
import hashlib
import json
import shutil
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release',action='store_true')
args=parser.parse_args()
config,_=parse_args([])
target='template_release' if args.release else 'template_debug'
project=ROOT/'.build'/('combat_'+target)
(project/'addons/player_runtime/bin').mkdir(parents=True,exist_ok=True)
(project/'tests').mkdir(exist_ok=True)
(project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Combat native check"\n')
library=f'player_runtime.windows.{target}.x86_64.dll'
shutil.copyfile(ROOT/'addons/player_runtime/bin'/library,project/'addons/player_runtime/bin'/library)
extension=(ROOT/'addons/player_runtime/player_runtime.gdextension').read_text()
(project/'addons/player_runtime/player_runtime.gdextension').write_text(extension.replace('template_debug',target))
shutil.copyfile(ROOT/'tests/combat_state.gd',project/'tests/combat_state.gd')
folder=ROOT/'reports/combat_native'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder.mkdir(parents=True)
command=[config.godot,'--headless','--path',str(project),'--script','res://tests/combat_state.gd','--log-file',str(folder/'engine.log'),'--','--native-only']
result=execute(command,folder,60,'COMBAT_STATE')
(folder/'run.json').write_text(json.dumps(dict(target=target,result=result,command=command,native_sha256=hashlib.sha256((project/'addons/player_runtime/bin'/library).read_bytes()).hexdigest(),**revision_metadata()),indent=2))
print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
raise SystemExit(0 if result['passed'] else 1)
