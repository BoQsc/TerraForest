# SPDX-License-Identifier: 0BSD
"""Observe a fresh owned copy of the retained default world with normal rendering."""
import argparse
import datetime
import hashlib
import json
import os
import shutil
from pathlib import Path

from clone_world import clone_once
from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='StartupBench_FPS_20261109T073252')
    parser.add_argument('--label', default='arrival')
    parser.add_argument('--short', action='store_true')
    parser.add_argument('--uncapped', action='store_true')
    parser.add_argument('--without-trace', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--save', action='store_true', help='Capture one normal save during active gameplay')
    parser.add_argument('--gpu-profile', action='store_true', help='Retain engine GPU pass summaries in the console log')
    parser.add_argument('--light-abba', action='store_true', help='Compare unchanged versus redundantly submitted pooled lights in one stationary view')
    parser.add_argument('--executable', action='store_true')
    args = parser.parse_args()
    if not args.source.startswith('StartupBench_FPS_') or not args.label.isidentifier():
        parser.error('Use an owned FPS fixture and an identifier label')
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/performance_changes' / (stamp + '_' + args.label)
    folder.mkdir(parents=True)
    slot = 'StartupBench_FPS_' + stamp[:-1]
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    copied = clone_once(worlds, args.source, slot)
    for suffix in ('.preview', '.generation.json', '.presentation.json'):
        source, target = worlds / (args.source + suffix), worlds / (slot + suffix)
        if source.is_dir():
            shutil.copytree(source, target)
        elif source.is_file():
            shutil.copy2(source, target)
    native = verify_pack_native() if args.executable else None
    runtime = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')] if args.executable else []
    command = [str(ROOT / 'TerraForest.exe' if args.executable else config.godot), *runtime,
               '--path', str(ROOT / 'dist' if args.executable else ROOT), '--windowed', '--position', '-2400,-1600',
               '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(folder / 'engine.log'),
               '--script', str(ROOT / 'tests/frame_trace_world.gd'), '--', '--trace-world-slot=' + slot,
               '--trace-world-output=' + folder.as_posix()]
    if args.short:
        command += ['--trace-short']
    if args.save:
        command += ['--trace-save']
    if args.light_abba:
        command += ['--trace-light-abba']
    if args.verbose:
        command.insert(1, '--verbose')
    if args.gpu_profile:
        command.insert(1, '--gpu-profile')
    if args.uncapped:
        command += ['--trace-uncapped']
    if not args.without_trace:
        command += ['--frame-trace', '--frame-trace-dir=' + str(folder / 'traces')]
    record = dict(command=command, clone=copied, **revision_metadata())
    if args.executable:
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        record['pack_native_sha256'] = native
    record['native_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((ROOT / 'addons').glob('*/bin/*.dll'))}
    manifest = folder / 'run.json'
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    record['result'] = execute(command, folder, 300, 'FRAME_TRACE_WORLD ok=true')
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(('PASS ' if record['result']['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if record['result']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
