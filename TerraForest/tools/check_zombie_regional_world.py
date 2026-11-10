"""Exercise autonomous zombie journeys in a prepared world opened read-only."""
# SPDX-License-Identifier: 0BSD
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import time
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata
from maintain_performance_artifacts import archive_regional_cache, capacity
from resource_limits import require_free_space

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slot',required=True)
    parser.add_argument('--case',required=True,choices=['cave','tower'])
    parser.add_argument('--headless',action='store_true')
    parser.add_argument('--navigation-profile',action='store_true',help='Measure native query phases without changing movement or planning budgets')
    parser.add_argument('--point-water-queries',action='store_true',help='Diagnostic control: use the legacy per-point water provider')
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,63}',args.slot):parser.error('Invalid slot identifier')
    source=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'/(args.slot+'.trw')
    if not source.is_file():parser.error('Prepared world does not exist')
    # Reserve before output creation; post-run archival is outside measured play.
    require_free_space(ROOT, 512 * 2**20)
    capacity(ROOT)
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
             *(['--headless'] if args.headless else ['--windowed','--position','-2400,-1600','--resolution','1920x1080']),
             '--max-fps','60','--script','res://tests/zombie_regional_world.gd','--',
             '--snapshot-readonly','--world-slot='+args.slot,'--derived-cache=user://zombie_regional_'+folder.name,
             '--navigation-case='+args.case,'--gameplay-construction','--zombies']
    if args.navigation_profile:command.append('--navigation-profile')
    if args.point_water_queries:command.append('--point-water-queries')
    record=dict(command=command,source_archive_sha256=before,**revision_metadata())
    record['source_data_before']=before_data
    record['engine_sha256']=hashlib.sha256(Path(config.godot).read_bytes()).hexdigest()
    record['test_sha256']=hashlib.sha256((ROOT/'tests/zombie_regional_world.gd').read_bytes()).hexdigest()
    record['native_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted((ROOT/'addons').glob('*/bin/*.dll'))}
    (folder/'run.json').write_text(json.dumps(record,indent=2))
    started=time.time()
    record['result']=execute(command,folder,600,'ZOMBIE_REGIONAL_WORLD case='+args.case)
    evidence=ROOT/'reports/zombie_regional_world'/args.case
    if evidence.is_dir():
        for output in evidence.iterdir():
            # Headless runs leave older graphical evidence in the shared source
            # folder. Retain only files actually produced by this invocation.
            if output.is_file() and output.stat().st_mtime>=started:
                (folder/args.case).mkdir(exist_ok=True)
                shutil.copy2(output,folder/args.case/output.name)
    record['source_archive_unchanged']=before==digest()
    after_data=source_data()
    record['source_data_unchanged']=before_data==after_data
    record['source_data_changed_paths']=sorted(k for k in before_data.keys()|after_data.keys() if before_data.get(k)!=after_data.get(k))
    (folder/'run.json').write_text(json.dumps(record,indent=2))
    ok=record['result']['passed'] and record['source_archive_unchanged'] and record['source_data_unchanged']
    try:
        archive_regional_cache(folder/'run.json')
    except (ValueError, OSError) as error:
        (folder/'cache_retention.json').write_text(json.dumps(dict(error=str(error), retained=True),indent=2))
        print('RETENTION_FAILED: '+str(error),flush=True)
        ok=False
    print(('PASS ' if ok else 'FAIL ')+str(folder))
    return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
