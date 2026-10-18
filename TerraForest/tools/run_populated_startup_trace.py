# SPDX-License-Identifier: 0BSD
"""Short startup attribution on a disposable copy of a populated world."""
import argparse
import datetime
import hashlib
import json
import os
import uuid
from pathlib import Path
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',default='populated_review_20261016')
    args=parser.parse_args()
    import re
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}',args.source):parser.error('Invalid source slot')
    worlds=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    source=worlds/(args.source+'.trw');before=hashlib.sha256(source.read_bytes()).hexdigest()
    slot='startup_trace_'+uuid.uuid4().hex
    copied=clone_once(worlds,args.source,slot)
    folder=ROOT/'reports/populated_startup_trace'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    config,_=parse_args([])
    command=[config.godot,'--path',str(ROOT),'--fullscreen','--resolution','1920x1080','--max-fps','60','--script','res://tests/populated_startup_trace.gd','--','--world-slot='+slot,'--ground-cover','--actors','--vehicle-fleet','--gameplay-construction']
    result=execute(command,folder,60,'POPULATED_STARTUP_TRACE failures=0')
    unchanged=hashlib.sha256(source.read_bytes()).hexdigest()==before
    details=dict(copy=copied,command=command,result=result,source_unchanged=unchanged,**revision_metadata())
    details['native_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'addons').glob('*/bin/*.dll')}
    (folder/'run.json').write_text(json.dumps(details,indent=2))
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ')+str(folder))
    return 0 if result['passed'] and unchanged else 1

if __name__=='__main__':raise SystemExit(main())
