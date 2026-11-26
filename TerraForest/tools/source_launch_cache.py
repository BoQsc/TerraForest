# SPDX-License-Identifier: 0BSD
"""Reuse completed source preparation while its inputs and outputs are unchanged."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 1
SKIP_ROOTS = {'.git', '.godot', '.build', '.agents', '.codex', 'reports', 'dist', 'docs', 'issues', 'steam'}
SKIP_ANYWHERE = {'__pycache__', '.git'}
IMPORT_INDEX = ('global_script_class_cache.cfg', 'uid_cache.bin', 'extension_list.cfg')
BAKES = {'addons/player_runtime/art/item_icons.trtex', 'addons/player_runtime/art/item_icons.bake.json',
         'addons/player_runtime/art/shape_icons.trtex', 'addons/player_runtime/art/shape_icons.bake.json',
         'addons/player_runtime/art/drops/current_tools.bake.json'}
BAKES.update(f'addons/player_runtime/art/drops/{item}.res' for item in range(1, 7))


def stamp(path):
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
        raise ValueError(f'Linked preparation input requires full inspection: {path}')
    return [info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_ino]


def generated(name):
    return name in BAKES or name.endswith(('.import', '.uid')) or ('/bin/' in name and name.endswith(('.dll', '.so', '.dylib')))


def scan_tree(base, inputs, outputs, prefix=''):
    def visit(directory, relative=''):
        with os.scandir(directory) as listing:
            entries = sorted(listing, key=lambda item: item.name)
        for entry in entries:
            if entry.name in SKIP_ANYWHERE or (not relative and entry.name in SKIP_ROOTS):
                continue
            # Windows directory enumeration already supplies size and high-resolution
            # timestamps. Avoid opening every asset again just to retrieve them.
            info = entry.stat(follow_symlinks=False)
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
                raise ValueError(f'Linked preparation input requires full inspection: {entry.path}')
            name = relative + entry.name
            if stat.S_ISDIR(info.st_mode):
                visit(entry.path, name + '/')
            elif not entry.name.endswith(('.md', '.pyc')):
                (outputs if generated(name) else inputs)[prefix + name] = [info.st_size, info.st_mtime_ns, info.st_ctime_ns]
    visit(base)


def snapshot(root, engine):
    inputs = {'@engine_path': str(engine.resolve()), '@engine': stamp(engine)}
    outputs = {}
    scan_tree(root, inputs, outputs)
    scan_tree(root.parent / 'Launcher', inputs, outputs, '@launcher/')
    imported = root / '.godot/imported'
    if imported.is_dir():
        scan_tree(imported, outputs, outputs, '@imported/')
    for name in IMPORT_INDEX:
        path = root / '.godot' / name
        # Godot can rewrite unchanged indexes on exit. Compare their small contents.
        outputs['@index/' + name] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    return {'schema': SCHEMA, 'inputs': inputs, 'outputs': outputs}


def read_record(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None


def write_record(path, record):
    data = json.dumps(record, separators=(',', ':'), sort_keys=True)
    if len(data.encode('utf-8')) > 4 * 2**20:
        raise ValueError('Source preparation record exceeds its 4 MiB bound')
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.pending')
    temporary.write_text(data, encoding='utf-8')
    temporary.replace(path)


def check(root, engine, force=False):
    current = snapshot(root, engine)
    folder = root / 'reports/source_preparation'
    if not force and current == read_record(folder / 'ready.json') and all(current['outputs'].get('@index/' + name) for name in IMPORT_INDEX):
        return True
    # Only a completed pipeline may publish ready.json. Guard against source edits
    # during that pipeline; generated DLLs, bakes and import sidecars may change.
    # A failed forced check must not fall back to an older ready receipt on Retry.
    write_record(folder / 'ready.json', {'schema': SCHEMA, 'ready': False})
    write_record(folder / 'started.json', {'schema': SCHEMA, 'inputs': current['inputs']})
    return False


def record(root, engine):
    current = snapshot(root, engine)
    folder = root / 'reports/source_preparation'
    started = read_record(folder / 'started.json')
    if started != {'schema': SCHEMA, 'inputs': current['inputs']}:
        raise ValueError('Source files changed during preparation. Retry after edits have settled.')
    if not all(current['outputs'].get('@index/' + name) for name in IMPORT_INDEX):
        raise ValueError('Preparation did not produce all required import indexes')
    write_record(folder / 'ready.json', current)


def execute_action(root, engine, action, force=False):
    (root / 'reports').mkdir(exist_ok=True)
    guard = nullcontext()
    if os.name == 'nt':
        from cleanup_generation_copies import lease
        guard = lease(root / 'reports/native_build')
    # The fast path must respect the same native-build owner as full preparation.
    with guard:
        if action == 'check':
            return 0 if check(root, engine, force) else 2
        record(root, engine)
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check', 'record'))
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    try:
        code = execute_action(ROOT, args.engine, args.action, args.force)
        if args.action == 'check':
            print('SOURCE_PREPARATION ' + ('current' if code == 0 else 'required'))
        else:
            print('SOURCE_PREPARATION recorded')
        return code
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
