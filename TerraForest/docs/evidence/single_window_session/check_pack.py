# SPDX-License-Identifier: 0BSD
from pathlib import Path
import datetime,hashlib,json,sys
root=Path(__file__).resolve().parents[3];sys.path.insert(0,str(root/'tools'))
from run import parse_args
from run_godot_check import command_for,execute
from play_checkpoint import revision_metadata
cfg,_=parse_args([]);engine=Path(cfg.godot).resolve();test='window_generation_flow' if '--generation' in sys.argv else 'window_session_flow'
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');folder=root/'reports/checks'/(stamp+'_'+test+'_pack');folder.mkdir(parents=True)
source=(root/'tests'/f'{test}.gd').read_text()
if test=='window_generation_flow':
 base=(root/'tests/window_session_flow.gd').read_text().split('func run()->void:')[0]
 base=base[base.index('const Launch='):]
 source=source.replace('extends "res://tests/window_session_flow.gd"','extends SceneTree\n'+base)
external=folder/(test+'.gd');external.write_text(source,encoding='utf-8')
command,cache=command_for(engine,test,folder,['--session-evidence-dir='+str(folder/'captures')])
command[command.index('--path')+1]=str(root/'dist');command[command.index('--script')+1]=str(external)
pack=root/'dist/TerraForest.pck';command[1:1]=['--main-pack',str(pack)]
timeout=580 if test=='window_generation_flow' else 300
complete='WINDOW_GENERATION_FLOW checks=12 failures=0' if test=='window_generation_flow' else 'WINDOW_SESSION_FLOW checks=21 failures=0'
details=dict(command=command,cache=cache,timeout=timeout,required_text=complete,scope='External assertion only; session, scenes, task scripts, assets and native libraries resolve from exported PCK/dist. Test-owned unique worlds.',pack_sha256=hashlib.sha256(pack.read_bytes()).hexdigest(),engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),test_sha256=hashlib.sha256(external.read_bytes()).hexdigest(),**revision_metadata())
manifest=folder/'run.json';manifest.write_text(json.dumps(details,indent=2)+'\n')
details['result']=execute(command,folder,timeout,complete)
# Engine 4.7.2 adds a count to this warning; treat it as a cleanup failure too.
log=(folder/'console.log').read_text(errors='replace')
if 'instances were leaked' in log or 'Leaked instance:' in log:details['result']['passed']=False;details['result']['cleanup_warning']=True
manifest.write_text(json.dumps(details,indent=2)+'\n')
print(('PASS ' if details['result']['passed'] else 'FAIL ')+str(folder));raise SystemExit(0 if details['result']['passed'] else 1)
