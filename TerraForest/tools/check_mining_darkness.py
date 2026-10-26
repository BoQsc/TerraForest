import argparse
import hashlib
import json
import os
import shutil
import uuid
from pathlib import Path

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--slot', default='Wild_Ridge')
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    if not args.slot.isidentifier():
        parser.error('Slot must be an identifier')
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    source = worlds / (args.slot + '.trw')
    if not source.is_file():
        parser.error('Saved world not found')
    token = uuid.uuid4().hex[:16]
    slot = 'mining_darkness_' + token
    folder = ROOT / 'reports/mining_darkness' / token
    folder.mkdir(parents=True)
    entries = [source, *worlds.glob(args.slot + '.trw.*')]
    entries = [entry for entry in entries if entry.suffix not in ('.bak', '.lock')]
    files = []
    for entry in entries:
        files.extend(path for path in entry.rglob('*') if path.is_file() and path.suffix != '.lock') if entry.is_dir() else files.append(entry)
    before = hashes(files)
    for entry in entries:
        destination = worlds / (slot + entry.name[len(args.slot):])
        shutil.copytree(entry, destination, ignore=shutil.ignore_patterns('*.lock')) if entry.is_dir() else shutil.copy2(entry, destination)
    if before != hashes(files):
        raise RuntimeError('Save changed while copying; no diagnostic launched')
    command = [str(config.godot), '--path', str(ROOT), '--log-file', str(folder / 'engine.log'),
               '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
               '--script', 'res://tests/mining_darkness.gd', '--', '--temporary',
               '--snapshot-readonly', '--world-slot=' + slot, '--ground-cover', '--no-zombies',
               '--nearby-first', '--gameplay-construction', '--derived-cache=user://' + slot,
               '--darkness-evidence=' + str(folder)]
    if args.pack:
        command[1:1] = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')]
    result = execute(command, folder, 180, 'MINING_DARKNESS failures=0')
    unchanged = before == hashes(files)
    record = dict(result=result, source_unchanged=unchanged, source_files=before,
                  copied_slot=slot, command=command, **revision_metadata())
    record['native_sha256'] = hashes(sorted((ROOT / ('dist/addons' if args.pack else 'addons') / 'volumetric_terrain/bin').glob('*.dll')))
    record['test_sha256'] = hashes([ROOT / 'tests/mining_darkness.gd'])
    if args.pack:
        record['pack_sha256'] = hashes([ROOT / 'dist/TerraForest.pck'])
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(('PASS ' if result['passed'] and unchanged else 'FAIL ') + str(folder))
    return 0 if result['passed'] and unchanged else 1


if __name__ == '__main__':
    raise SystemExit(main())
