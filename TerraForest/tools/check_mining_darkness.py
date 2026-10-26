import argparse
import hashlib
import json
import os
import re
import shutil
import uuid
from pathlib import Path

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata, verify_pack_native


def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--slot', default='Wild_Ridge')
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--backup', action='store_true', help='Inspect the previous .trw.bak root using a separate copied slot')
    parser.add_argument('--camera-from', type=Path, help='Use a previous diagnostic scene.json camera without changing the saved world')
    args = parser.parse_args()
    native = verify_pack_native() if args.pack else None
    if not args.slot.isidentifier():
        parser.error('Slot must be an identifier')
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source = worlds / (args.slot + '.trw')
    selected_root = source.with_name(source.name + '.bak') if args.backup else source
    if not selected_root.is_file():
        parser.error('Saved world not found')
    token = uuid.uuid4().hex[:16]
    slot = 'mining_darkness_' + token
    folder = ROOT / 'reports/mining_darkness' / token
    folder.mkdir(parents=True)
    entries = [entry for entry in worlds.glob(args.slot + '.trw.*') if entry.is_dir() and entry.suffix in ('.models', '.regions', '.terrain', '.water')]
    files = list(dict.fromkeys([selected_root, source]))
    for entry in entries:
        files.extend(path for path in entry.rglob('*') if path.is_file() and path.suffix != '.lock')
    before = hashes(files)
    shutil.copy2(selected_root, worlds / (slot + '.trw'))
    for entry in entries:
        destination = worlds / (slot + entry.name[len(args.slot):])
        shutil.copytree(entry, destination, ignore=shutil.ignore_patterns('*.lock'))
    if before != hashes(files):
        raise RuntimeError('Save changed while copying; no diagnostic launched')
    command = [str(config.godot), '--path', str(ROOT), '--log-file', str(folder / 'engine.log'),
               '--minimized', '--resolution', '1920x1080', '--max-fps', '60',
               '--script', 'res://tests/mining_darkness.gd', '--', '--temporary',
               '--snapshot-readonly', '--world-slot=' + slot, '--ground-cover', '--no-zombies',
               '--nearby-first', '--gameplay-construction', '--derived-cache=user://' + slot,
               '--darkness-evidence=' + str(folder)]
    if args.camera_from:
        camera = json.loads(args.camera_from.read_text(encoding='utf-8'))['camera']
        components = re.findall(r'[-+]?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?', camera)
        if len(components) != 12:
            parser.error('Diagnostic camera must have twelve numeric components')
        command.append('--darkness-camera=' + ','.join(components))
    if args.pack:
        command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
    result = execute(command, folder, 180, 'MINING_DARKNESS failures=0')
    unchanged = before == hashes(files)
    record = dict(result=result, source_unchanged=unchanged, source_files=before,
                  copied_slot=slot, selected_root=str(selected_root), command=command, matching_pack_native=native, **revision_metadata())
    if args.camera_from:
        record['camera_source_sha256'] = hashes([args.camera_from])
    record['native_sha256'] = hashes(sorted((ROOT / ('dist/addons' if args.pack else 'addons') / 'volumetric_terrain/bin').glob('*.dll')))
    record['test_sha256'] = hashes([ROOT / 'tests/mining_darkness.gd'])
    if args.pack:
        record['pack_sha256'] = hashes([ROOT / 'dist/TerraForest.pck'])
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ') + str(folder))
    return 0 if result['passed'] and unchanged else 1


if __name__ == '__main__':
    raise SystemExit(main())
