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
    parser.add_argument('--legacy-structure-capture', action='store_true', help='Diagnostic control: serialize structures on the main thread during save')
    parser.add_argument('--gpu-profile', action='store_true', help='Retain engine GPU pass summaries in the console log')
    parser.add_argument('--render-stages', action='store_true', help='Diagnostic only: bounded completed-frame render-device CPU marker gaps')
    parser.add_argument('--script-profile', action='store_true', help='Diagnostic only: enable the engine script debugger profiler')
    parser.add_argument('--render-inventory', action='store_true', help='Inspect scene geometry/light candidates after all frame timings are saved')
    parser.add_argument('--render-partition', type=int, choices=[8,16], help='Stationary ABBA diagnostic of exact nearby cover draw partitions')
    parser.add_argument('--block-occlusion', action='store_true', help='Diagnostic only: compare exact nearby opaque block occluders in one stationary view')
    parser.add_argument('--occlusion-ignore-boulders', action='store_true', help='Diagnostic only: exclude boulder batches from occludee tests')
    parser.add_argument('--occlusion-control-off', action='store_true', help='Diagnostic only: keep viewport culling disabled for every comparison phase')
    parser.add_argument('--render-full-detail', action='store_true', help='Diagnostic only: disable automatic mesh LOD for every ABBA phase')
    parser.add_argument('--legacy-cover', action='store_true', help='Diagnostic only: use the prior 32 m cover layout before first admission')
    parser.add_argument('--outdoor-cover', action='store_true', help='Repeatable 16 m outdoor camera sweep with normal world services and quality')
    parser.add_argument('--light-abba', action='store_true', help='Compare unchanged versus redundantly submitted pooled lights in one stationary view')
    parser.add_argument('--executable', action='store_true')
    args = parser.parse_args()
    if args.render_stages and args.without_trace:
        parser.error('--render-stages requires the rolling recorder')
    if args.render_full_detail and not args.render_partition:
        parser.error('--render-full-detail requires --render-partition')
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
    if args.legacy_structure_capture:
        command += ['--trace-legacy-structure-capture']
    if args.light_abba:
        command += ['--trace-light-abba']
    if args.verbose:
        command.insert(1, '--verbose')
    if args.gpu_profile or args.render_stages:
        command.insert(1, '--gpu-profile')
    if args.render_stages:
        command += ['--frame-trace-render-stages']
    if args.script_profile:
        command[1:1] = ['--debug', '--ignore-error-breaks', '--profiling']
    if args.render_inventory:
        command += ['--trace-render-inventory']
    if args.render_partition:
        command += ['--trace-render-partition=' + str(args.render_partition)]
    if args.block_occlusion:
        command += ['--trace-block-occlusion']
    if args.occlusion_ignore_boulders:
        command += ['--trace-occlusion-ignore-boulders']
    if args.occlusion_control_off:
        command += ['--trace-occlusion-control-off']
    if args.render_full_detail:
        command += ['--trace-render-full-detail']
    if args.legacy_cover:
        command += ['--trace-legacy-cover']
    if args.outdoor_cover:
        command += ['--trace-outdoor-cover']
    if args.uncapped:
        command += ['--trace-uncapped']
    if not args.without_trace:
        command += ['--frame-trace', '--frame-trace-dir=' + str(folder / 'traces')]
    record = dict(command=command, clone=copied, **revision_metadata())
    record['diagnostic_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in [ROOT/'tests/frame_trace_world.gd', ROOT/'tests/render_inventory.gd',
                                            ROOT/'tests/render_partition_probe.gd', ROOT/'tests/render_occlusion_probe.gd', ROOT/'tests/cover_outdoor_probe.gd',
                                            ROOT/'addons/world_runtime/frame_trace.gd', ROOT/'addons/world_runtime/render_trace.gd', Path(__file__)]}
    if args.executable:
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        record['pack_native_sha256'] = native
    record['native_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((ROOT / 'addons').glob('*/bin/*.dll'))}
    manifest = folder / 'run.json'
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    record['result'] = execute(command, folder, 300, 'FRAME_TRACE_WORLD ok=true')
    if args.script_profile:
        record['result']['script_profiler_started'] = 'BEGIN PROFILING' in (folder / 'console.log').read_text(encoding='utf-8', errors='replace')
        record['result']['passed'] &= record['result']['script_profiler_started']
    if args.render_stages:
        available = any(row.get('render_markers', {}).get('available', False)
                        for path in (folder / 'traces').glob('trace_*.json')
                        for row in json.loads(path.read_text(encoding='utf-8')).get('frames', []))
        record['result']['render_markers_available'] = available
        record['result']['passed'] &= available
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(('PASS ' if record['result']['passed'] else 'FAIL ') + str(folder), flush=True)
    return 0 if record['result']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
