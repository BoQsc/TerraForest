# SPDX-License-Identifier: 0BSD
"""Native landform laboratory: bounded captures, no world/export/project copy.

Reuse completed runs by input hash. Keep at most two unpinned ready runs; archive
their exact receipt-owned outputs after exit. Pins and player saves are excluded.
An interactive session keeps this launcher alive until its window is closed.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import os
import re
from development_storage import admit
from maintain_performance_artifacts import no_game_processes
from retained_artifacts import Store, archive, confined, digest, retire
from cleanup_generation_copies import lease
from run import ROOT, parse_args
from run_godot_check import execute
from landform_inspector import inspect
from launch_recipe_playtest import gameplay_arguments

FAMILY = ROOT/'reports/generation_lab'
INPUTS = ['tests/fixtures/landform_v1.lfp', 'tests/fixtures/landform_v1.json', 'addons/world_runtime/assets/landform_library.json', 'addons/world_runtime/bin/world_runtime.windows.template_debug.x86_64.dll', 'tests/generation_lab.gd', 'tests/island_ecology.gd', 'demo/generation_lab.gd', 'demo/generation_lab.tscn', 'tools/run_generation_lab.py', 'tools/landform_inspector.py', 'tools/launch_recipe_playtest.py']


def world_identity(slot):
    if not re.fullmatch(r'Island_1703_[0-9a-f]{8}', slot):
        raise ValueError('Choose the existing island playtest save')
    worlds=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    if not (worlds/(slot+'.trw')).is_file():raise ValueError('Existing save is missing')
    result={}
    for member in worlds.glob(slot+'.*'):
        if member.name==slot+'.trw.lock':continue
        for path in member.rglob('*') if member.is_dir() else [member]:
            if path.is_file():result[path.relative_to(worlds).as_posix()]=digest(confined(path,worlds))
    return result


def maintain():
    ready = []
    for path in sorted(FAMILY.glob('*/run.json')):
        record = json.loads(path.read_text())
        if record.get('purpose') != 'native-landform-lab-v1' or not record.get('completed'):
            continue
        folder = confined(path.parent, FAMILY)
        if any((folder/name).exists() for name in ('.retain', 'RETAIN_READY', 'outputs.archive.json')):
            continue
        ready.append((folder, record))
    for folder, record in ready[:-2]:
        members = record.get('owned_outputs', {})
        if not members:
            continue
        for name, expected in members.items():
            if digest(confined(folder/name, folder)) != expected:
                raise ValueError('Changed lab evidence retained: '+str(folder/name))
        store_root = ROOT/'reports/retained_artifacts'
        with lease(store_root/'writer'):
            store = Store(store_root/'chunks')
            manifest = archive(folder, sorted(members), folder/'outputs.archive.json', store,
                               {'kind':'native-landform-lab-v1', 'receipt_sha256':digest(folder/'run.json')})
            retire(manifest, store, folder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interactive', action='store_true')
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--ecology-slot', help='Read-only grass-presence regression on the protected island; no copied/new world')
    parser.add_argument('--godot')
    args = parser.parse_args()
    if sum(bool(v) for v in (args.interactive,args.capture,args.ecology_slot))>1:
        parser.error('Choose the interactive session or the automated capture')
    no_game_processes()
    maintain()
    inputs = {name:digest(ROOT/name) for name in INPUTS}
    before=world_identity(args.ecology_slot) if args.ecology_slot else {}
    inputs.update({'save/'+name:value for name,value in before.items()})
    mode = 'ecology' if args.ecology_slot else 'interactive' if args.interactive else 'capture' if args.capture else 'checks'
    key = hashlib.sha256(json.dumps([mode, inputs], sort_keys=True).encode()).hexdigest()
    for path in FAMILY.glob('*/run.json'):
        record = json.loads(path.read_text())
        if mode!='interactive' and record.get('input_hash')==key and record.get('passed') and not (path.parent/'outputs.archive.json').exists():
            if all(digest(confined(path.parent/name,path.parent))==value for name,value in record['owned_outputs'].items()):
                print('REUSED '+str(path.parent));return 0
    admission = admit(ROOT, report_bytes=(8 if args.capture or args.ecology_slot else 4)*2**20, world_bytes=0)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = FAMILY/(stamp+'_'+mode);folder.mkdir(parents=True)
    record = {'purpose':'native-landform-lab-v1', 'inputs':inputs, 'input_hash':key,
              'mode':mode, 'admission':admission, 'new_worlds':0, 'completed':False}
    engine = Path(parse_args(['--godot',args.godot] if args.godot else [])[0].godot)
    direct = engine.parent/'godot.windows.opt.tools.64.exe'
    if direct.is_file():engine=direct
    command = [str(engine),'--path',str(ROOT),'--log-file',str(folder/'engine.log')]
    if args.interactive:
        command += ['--windowed','--resolution','1280x800','--max-fps','60','res://demo/generation_lab.tscn']
        record['command']=command
        with (folder/'console.log').open('w') as log:
            process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            record['pid']=process.pid;(folder/'run.json').write_text(json.dumps(record,indent=2))
            print(json.dumps({'pid':process.pid,'report':str(folder),'status':'laboratory started'}),flush=True)
            record['exit_code']=process.wait()
        record['passed']=record['exit_code']==0
    else:
        rendered=args.capture or bool(args.ecology_slot)
        command += (['--windowed','--resolution','1920x1080' if args.ecology_slot else '1280x800','--max-fps','60'] if rendered else ['--headless'])
        command += ['--script','res://tests/island_ecology.gd' if args.ecology_slot else 'res://tests/generation_lab.gd','--','--check-evidence-dir='+folder.as_posix()]
        if args.capture:command.append('--capture-lab')
        if args.ecology_slot:command += gameplay_arguments(args.ecology_slot)+['--snapshot-readonly','--temporary','--no-derived-cache']
        record['command']=command;(folder/'run.json').write_text(json.dumps(record,indent=2))
        record['result']=execute(command,folder,300 if args.ecology_slot else 180,'ISLAND_ECOLOGY checks=' if args.ecology_slot else 'GENERATION_LAB checks=',isolated_render=rendered)
        record['passed']=record['result']['passed']
        if args.ecology_slot:
            record['source_save_unchanged']=before==world_identity(args.ecology_slot)
            record['passed']=record['passed'] and record['source_save_unchanged']
        for path in folder.glob('*.lfp'):
            inspected=inspect(path.read_bytes())
            (folder/(path.stem+'_program.json')).write_text(json.dumps(inspected,indent=2))
    record['completed']=True
    record['owned_outputs']={p.relative_to(folder).as_posix():digest(p) for p in folder.rglob('*') if p.is_file() and p.name!='run.json'}
    (folder/'run.json').write_text(json.dumps(record,indent=2))
    try:maintain()
    except (OSError,ValueError) as error:print('Retention pending; evidence preserved: '+str(error))
    print(('PASS ' if record['passed'] else 'FAIL ')+str(folder),flush=True)
    return int(not record['passed'])


if __name__=='__main__':
    raise SystemExit(main())
