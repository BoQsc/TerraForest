# SPDX-License-Identifier: 0BSD
"""Retire published generation work copies only after native destination verification."""
import argparse
from contextlib import ExitStack, contextmanager
import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from cleanup_report_imports import ordinary

ROOT = Path(__file__).resolve().parents[1]
STAGE = re.compile(r'combined_stage_[0-9a-f]{32}\Z')
SLOT = re.compile(r'[A-Za-z_][A-Za-z0-9_]{0,47}\Z')


def digest(path):
    ordinary(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def candidates(userdata):
    ordinary(userdata, True)
    worlds = userdata / 'worlds'
    ordinary(worlds, True)
    ordinary(userdata / 'generation_reports', True)
    records = []
    for report in (userdata / 'generation_reports').glob('*/run.json'):
        ordinary(report.parent, True)
        ordinary(report)
        try:
            row = json.loads(report.read_text())
        except (ValueError, OSError):
            continue
        stage, destination = row.get('stage', ''), row.get('destination', '')
        publication = row.get('publication', {})
        if not STAGE.fullmatch(stage) or not SLOT.fullmatch(destination) or STAGE.fullmatch(destination):
            continue
        if not publication.get('ok') or not publication.get('created') or publication.get('slot') != destination:
            continue
        if not (worlds / (stage + '.trw')).is_file() or not (worlds / (destination + '.trw')).is_file():
            continue
        if (worlds / (stage + '.trw.tmp')).exists():
            continue
        records.append(dict(stage=stage, destination=destination, seed=row['seed'], generator=row['generator'],
                            options=row.get('world_options', {}), report=str(report), report_sha256=digest(report)))
    return records


@contextmanager
def lease(path):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                  wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateFileW(str(path) + '.lock', 0xC0000000, 0, None, 4, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        raise OSError('World is in use: ' + str(path))
    try:
        yield
    finally:
        kernel.CloseHandle(handle)


def retire(worlds, row):
    ordinary(worlds, True)
    if not STAGE.fullmatch(row['stage']) or not SLOT.fullmatch(row['destination']) or STAGE.fullmatch(row['destination']):
        raise ValueError('Invalid working-copy identity')
    source = worlds / (row['stage'] + '.trw')
    target = worlds / (row['destination'] + '.trw')
    if source.resolve().parent != worlds.resolve() or target.resolve().parent != worlds.resolve():
        raise ValueError('World path escapes verified directory')
    for path in (source, target):
        ordinary(path)
        lock = Path(str(path) + '.lock')
        if lock.exists():
            ordinary(lock)
    with ExitStack() as locks:
        locks.enter_context(lease(source))
        locks.enter_context(lease(target))
        if digest(source) != row['source_sha256'] or digest(target) != row['destination_sha256']:
            raise ValueError('World changed since native verification')
        if digest(Path(row['report'])) != row['report_sha256']:
            raise ValueError('Publication receipt changed')
        if Path(str(source) + '.tmp').exists():
            raise ValueError('Working copy has unfinished save data')
        selected = []
        total = 0
        for suffix in ('.regions', '.models', '.water', '.terrain', '.baselines', '.bak', ''):
            path = Path(str(source) + suffix)
            if not path.exists():
                continue
            if path.parent != worlds or path.resolve().parent != worlds.resolve():
                raise ValueError('Cleanup target escapes verified directory')
            ordinary(path, path.is_dir())
            selected.append(path)
            if path.is_dir():
                for folder, directories, files in os.walk(path, followlinks=False):
                    for name in directories:
                        ordinary(Path(folder) / name, True)
                    for name in files:
                        total += ordinary(Path(folder) / name).st_size
            else:
                total += path.stat().st_size
        for path in selected:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
        return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    if args.apply and not args.offline:
        parser.error('Close Godot and pass --offline to retire work copies')
    userdata = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest'
    worlds = userdata / 'worlds'
    rows = candidates(userdata)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report = ROOT / 'reports' / ('generation_retention_' + stamp + '.json')
    report.write_text(json.dumps(dict(root=str(worlds), candidates=rows), indent=2))
    subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--log-file', str(report) + '.log', '--script',
        'res://tools/verify_retired_generation.gd', '--', '--retention-input=' + str(report)], check=True,
        timeout=900, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    verified = json.loads(Path(str(report) + '.verified.json').read_text())
    result = dict(scope='Verified published generation work copies only; destination worlds and evidence preserved',
                  verification=str(report) + '.verified.json', removed=[], failures=[], apply=args.apply)
    receipt = Path(str(report) + '.cleanup.json')
    receipt.write_text(json.dumps(result, indent=2))
    try:
        if args.apply:
            for row in verified['verified']:
                try:
                    amount = retire(worlds, row)
                    result['removed'].append(dict(stage=row['stage'], destination=row['destination'], bytes=amount))
                except (ValueError, OSError) as error:
                    result['failures'].append(dict(stage=row['stage'], reason=str(error)))
    finally:
        receipt.write_text(json.dumps(result, indent=2))
    print(json.dumps(dict(verified=len(verified['verified']), retained=len(verified['rejected']),
        removed=len(result['removed']), removed_bytes=sum(row['bytes'] for row in result['removed']),
        failures=result['failures'], receipt=str(receipt)), indent=2))


if __name__ == '__main__':
    main()
