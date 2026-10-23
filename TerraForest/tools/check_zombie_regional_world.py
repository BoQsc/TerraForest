"""Exercise autonomous zombie journeys in a prepared world opened read-only."""
# SPDX-License-Identifier: 0BSD
import argparse
import datetime
import hashlib
import json
import os
import re
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slot',required=True)
    parser.add_argument('--case',required=True,choices=['cave','tower'])
    parser.add_argument('--headless',action='store_true')
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,63}',args.slot):parser.error('Invalid slot identifier')
    source=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'/(args.slot+'.trw')
    if not source.is_file():parser.error('Prepared world does not exist')
    digest=lambda:hashlib.sha256(source.read_bytes()).hexdigest()
    before=digest()
    def source_data():
        files=[source]
        for suffix in ['.regions','.models','.water','.terrain']:
            directory=source.with_name(source.name+suffix)
            if directory.is_dir():files.extend(p for p in directory.rglob('*') if p.is_file() and not p.name.endswith('.lock'))
        result={}
        for path in files:
            with path.open('rb') as stream:result[str(path.relative_to(source.parent))]=hashlib.file_digest(stream,'sha256').hexdigest()
        return result
    before_data=source_data()
    config,_=parse_args([])
    folder=ROOT/'reports/checks'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    command=[str(config.godot),'--path',str(ROOT),'--log-file',str(folder/'engine.log'),
             *(['--headless'] if args.headless else ['--fullscreen','--resolution','1920x1080']),
             '--max-fps','60','--script','res://tests/zombie_regional_world.gd','--',
             '--snapshot-readonly','--world-slot='+args.slot,'--derived-cache=user://zombie_regional_'+folder.name,
             '--navigation-case='+args.case,'--gameplay-construction','--zombies']
    record=dict(command=command,source_archive_sha256=before,**revision_metadata())
    record['source_data_before']=before_data
    record['engine_sha256']=hashlib.sha256(Path(config.godot).read_bytes()).hexdigest()
    record['test_sha256']=hashlib.sha256((ROOT/'tests/zombie_regional_world.gd').read_bytes()).hexdigest()
    record['native_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted((ROOT/'addons').glob('*/bin/*.dll'))}
    (folder/'run.json').write_text(json.dumps(record,indent=2))
    record['result']=execute(command,folder,600,'ZOMBIE_REGIONAL_WORLD case='+args.case)
    record['source_archive_unchanged']=before==digest()
    after_data=source_data()
    record['source_data_unchanged']=before_data==after_data
    record['source_data_changed_paths']=sorted(k for k in before_data.keys()|after_data.keys() if before_data.get(k)!=after_data.get(k))
    (folder/'run.json').write_text(json.dumps(record,indent=2))
    ok=record['result']['passed'] and record['source_archive_unchanged'] and record['source_data_unchanged']
    print(('PASS ' if ok else 'FAIL ')+str(folder))
    return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
