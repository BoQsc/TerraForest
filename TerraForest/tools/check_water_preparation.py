# SPDX-License-Identifier: 0BSD
"""Cold spawn preparation and warm reopen in two independent actual-game processes."""
import datetime, hashlib, json, os, uuid
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
engine=parse_args([])[0].godot
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
folder=ROOT/'reports/checks'/('prepare_'+stamp)
token=uuid.uuid4().hex
slot='check_'+token
shared=['--','--world-slot='+slot,'--derived-cache=user://water_prepare_'+token,'--water-gameplay','--gameplay-construction']
runs=[]
for phase,script,headless,marker in [('cold','tools/prepare_water_world',True,'"saved":true'),('warm','tests/water_prepared_reopen',False,'PREPARED_REOPEN failures=0')]:
    path=folder/phase;path.mkdir(parents=True)
    command=[engine,'--path',str(ROOT),'--log-file',str(path/'engine.log'),'--max-fps','60',*(['--headless'] if headless else ['--fullscreen','--resolution','1920x1080']),'--script','res://'+script+'.gd',*shared]
    result=execute(command,path,65,marker)
    result['command']=command
    runs.append(result)
    (folder/'run.json').write_text(json.dumps({'slot':slot,'runs':runs,'water_debug_sha256':hashlib.sha256((ROOT/'addons/volumetric_water/bin/volumetric_water.windows.template_debug.x86_64.dll').read_bytes()).hexdigest()},indent=2))
    if not result['passed']:
        print('FAIL '+str(path));raise SystemExit(1)
print('PASS '+str(folder))
base=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
for suffix in ('.trw','.trw.bak','.trw.lock'):
    path=base/(slot+suffix)
    if path.is_file():path.unlink()
