# SPDX-License-Identifier: 0BSD
from pathlib import Path
import datetime, hashlib, json, sys
root=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(root/'tools'))
from run_godot_check import command_for,execute
from run import parse_args
from play_checkpoint import revision_metadata
config,_=parse_args([])
engine=Path(config.godot).resolve()
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder=root/'reports/checks'/(stamp+'_resource_gain_feed_pack');folder.mkdir(parents=True)
pack=root/'dist/TerraForest.pck'
base=(root/'tests/combined_resource_route.gd').read_text().split('func run()')[0]
base=base[base.index('var game:'):]
source=(root/'tests/resource_gain_feed.gd').read_text().replace('extends "res://tests/combined_resource_route.gd"','extends SceneTree\n'+base)
external=folder/'resource_gain_feed_external.gd';external.write_text(source.expandtabs(1),encoding='utf-8')
command,cache=command_for(engine,'resource_gain_feed',folder,['--gameplay-construction','--no-zombies','--gain-evidence-dir='+str(folder/'captures')])
command[command.index('--path')+1]=str(root/'dist')
command[command.index('--script')+1]=str(external)
command[1:1]=['--main-pack',str(pack)]
details=dict(command=command,cache=cache,utc=stamp,timeout=140,required_text='RESOURCE_GAIN_FEED failures=0',scope='External assertion helper; game scenes/scripts/assets resolve from exported PCK/dist. Temporary world, fresh derived cache.',engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),pack_sha256=hashlib.sha256(pack.read_bytes()).hexdigest(),test_sha256=hashlib.sha256(external.read_bytes()).hexdigest(),native_sha256={str(p.relative_to(root/'dist')):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'dist/addons').glob('*/bin/*.dll'))},**revision_metadata())
manifest=folder/'run.json';manifest.write_text(json.dumps(details,indent=2)+'\n',encoding='utf-8')
details['result']=execute(command,folder,140,details['required_text'])
manifest.write_text(json.dumps(details,indent=2)+'\n',encoding='utf-8')
print(('PASS ' if details['result']['passed'] else 'FAIL ')+str(folder),flush=True)
raise SystemExit(0 if details['result']['passed'] else 1)
