# SPDX-License-Identifier: 0BSD
"""Verify a generated cellar chest deposit across two processes using a disposable save clone."""
from pathlib import Path
import os, json, datetime, argparse
from clone_world import clone_once
from run_godot_check import execute
from run import ROOT, parse_args

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='market_cellar_42_20261022')
    parser.add_argument('--godot')
    args=parser.parse_args()
    engine=parse_args(['--godot',args.godot] if args.godot else [])[0].godot
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    slot='cellar_persist_'+stamp
    folder=ROOT/'reports/cellar_storage_reopen'/stamp;folder.mkdir(parents=True)
    worlds=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    metadata={'clone':clone_once(worlds,args.source,slot),'phases':[]}
    base=[engine,'--path',str(ROOT),'--fullscreen','--resolution','1920x1080','--max-fps','60','--script','res://tests/market_cellar_connected_access.gd','--','--world-slot='+slot,'--world-generator=19','--world-seed=42','--ground-cover','--gameplay-construction','--cellar-record='+str(folder/'expected.bin')]
    for phase in ['save','reopen']:
        output=folder/phase;output.mkdir()
        result=execute(base+(['--cellar-reopen','--snapshot-readonly'] if phase=='reopen' else []),output,180,'MARKET_CELLAR_CONNECTED_ACCESS failures=0')
        metadata['phases'].append({'phase':phase,**result})
        (folder/'run.json').write_text(json.dumps(metadata,indent=2))
        print(phase,result,flush=True)
        if not result['passed']:return 1
    print(folder);return 0
if __name__=='__main__':raise SystemExit(main())
