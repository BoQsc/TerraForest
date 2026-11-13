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
from resource_limits import load_budgets, require_free_space
from maintain_performance_artifacts import capacity, maintain
from development_storage import admit
from maintain_performance_traces import maintain_traces


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='StartupBench_FPS_20261109T073252')
    parser.add_argument('--label', default='arrival')
    parser.add_argument('--human', action='store_true', help='Five minutes of normal human play; Ctrl+Shift+F11 finishes early')
    parser.add_argument('--combat-probe', action='store_true', help='Diagnostic close-combat hits and corpse creation in the owned world')
    parser.add_argument('--short', action='store_true')
    parser.add_argument('--uncapped', action='store_true')
    parser.add_argument('--without-trace', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--save', action='store_true', help='Capture one normal save during active gameplay')
    parser.add_argument('--legacy-structure-capture', action='store_true', help='Diagnostic control: serialize structures on the main thread during save')
    parser.add_argument('--gpu-profile', action='store_true', help='Retain engine GPU pass summaries in the console log')
    parser.add_argument('--render-stages', action='store_true', help='Diagnostic only: bounded completed-frame render-device CPU marker gaps')
    parser.add_argument('--render-gpu-stages', action='store_true', help='Diagnostic only: also retain bounded completed-frame GPU timestamp gaps')
    parser.add_argument('--quiet-render-stages', action='store_true', help='Diagnostic only: retain render markers while suppressing per-second engine profile printing')
    parser.add_argument('--require-native-process-profiles', action='store_true', help='Require current gameplay block/model/light callback samples')
    parser.add_argument('--script-profile', action='store_true', help='Diagnostic only: enable the engine script debugger profiler')
    parser.add_argument('--render-inventory', action='store_true', help='Inspect scene geometry/light candidates after all frame timings are saved')
    parser.add_argument('--render-partition', type=int, choices=[8,16], help='Stationary ABBA diagnostic of exact nearby cover draw partitions')
    parser.add_argument('--block-occlusion', action='store_true', help='Diagnostic only: compare exact nearby opaque block occluders in one stationary view')
    parser.add_argument('--occlusion-ignore-boulders', action='store_true', help='Diagnostic only: exclude boulder batches from occludee tests')
    parser.add_argument('--occlusion-control-off', action='store_true', help='Diagnostic only: keep viewport culling disabled for every comparison phase')
    parser.add_argument('--render-full-detail', action='store_true', help='Diagnostic only: disable automatic mesh LOD for every ABBA phase')
    parser.add_argument('--legacy-cover', action='store_true', help='Diagnostic only: use the prior 32 m cover layout before first admission')
    parser.add_argument('--outdoor-cover', action='store_true', help='Repeatable 16 m outdoor camera sweep with normal world services and quality')
    parser.add_argument('--grounded-walk', action='store_true', help='Use real grounded player movement during the outdoor route instead of fly-camera motion')
    parser.add_argument('--walk-seconds', type=float, default=1.5, help='Seconds per grounded walking leg, from 1 to 20 (two legs)')
    parser.add_argument('--normal-window', action='store_true', help='Use normal fullscreen/window preference and require foreground gameplay; no background-cap override')
    parser.add_argument('--destruction-load', action='store_true', help='Real three-barrel chain and full debris population in the owned default-world clone')
    parser.add_argument('--legacy-blast-batches', action='store_true', help='Diagnostic control: prior script block/damage batches, unchanged limits')
    parser.add_argument('--legacy-debris-nodes', action='store_true', help='Diagnostic control: create fragment nodes per hit instead of reusing the 96 slots')
    parser.add_argument('--pooled-debris', action='store_true', help='Qualify the experimental 96-slot fragment pool; ordinary gameplay is unchanged')
    parser.add_argument('--legacy-structure-retirement', action='store_true', help='Diagnostic control: retain obsolete building bodies in physics during shape retirement')
    parser.add_argument('--destruction-deadline', type=int, choices=[1,3,32,256], help='Strict next-physics-tick feasibility gate; incomplete publication intentionally fails')
    parser.add_argument('--legacy-owner-bounds', action='store_true', help='Diagnostic control: use original forest/boulder invalidation scans')
    parser.add_argument('--collision-piece-triangles', type=int, choices=[256, 512, 1024], help='Diagnostic only: configure exact terrain collision partitions before worker startup')
    parser.add_argument('--light-abba', action='store_true', help='Compare unchanged versus redundantly submitted pooled lights in one stationary view')
    parser.add_argument('--player-abba', action='store_true', help='Grounded stationary and turning comparisons of player feel on/off; restores the preference')
    parser.add_argument('--legacy-hidden-hud', action='store_true', help='Diagnostic control: rebuild the hidden developer HUD as before')
    parser.add_argument('--legacy-canopy-snapshot', action='store_true', help='Diagnostic control: traverse all forest dictionaries for each canopy snapshot')
    parser.add_argument('--render-thread', choices=['safe', 'separate'], help='Diagnostic engine rendering thread comparison')
    parser.add_argument('--rendering-driver', choices=['vulkan', 'd3d12'], help='Diagnostic graphics API comparison; keeps Forward+ quality and normal pacing')
    parser.add_argument('--without-gpu-timers', action='store_true', help='Avoid synchronous renderer timer queries; requires --without-trace')
    parser.add_argument('--executable', action='store_true')
    args = parser.parse_args()
    if args.human:
        args.normal_window = True
        if args.uncapped or args.without_trace:
            parser.error('Human baseline requires normal pacing and tracing')
    if args.pooled_debris and args.legacy_debris_nodes:
        parser.error('--pooled-debris and --legacy-debris-nodes are mutually exclusive')
    if args.destruction_deadline and (args.destruction_load or args.without_trace):
        parser.error('--destruction-deadline requires tracing and excludes --destruction-load')
    if args.grounded_walk and not args.outdoor_cover:
        parser.error('--grounded-walk requires --outdoor-cover')
    if not 1 <= args.walk_seconds <= 20 or (args.walk_seconds != 1.5 and not args.grounded_walk):
        parser.error('--walk-seconds requires grounded walking and a duration from 1 to 20')
    if args.without_gpu_timers and not args.without_trace:
        parser.error('--without-gpu-timers requires --without-trace')
    if args.require_native_process_profiles and args.without_trace:
        parser.error('--require-native-process-profiles requires the recorder')
    if args.render_stages and args.without_trace:
        parser.error('--render-stages requires the rolling recorder')
    if args.render_gpu_stages and not args.render_stages:
        parser.error('--render-gpu-stages requires --render-stages')
    if args.quiet_render_stages and (not args.render_stages or args.verbose):
        parser.error('--quiet-render-stages requires --render-stages and excludes --verbose')
    if args.render_full_detail and not args.render_partition:
        parser.error('--render-full-detail requires --render-partition')
    if not args.source.startswith('StartupBench_FPS_') or not args.label.isidentifier():
        parser.error('Use an owned FPS fixture and an identifier label')
    config, _ = parse_args([])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    clone_bytes = 0
    for suffix in ('.trw', '.trw.regions', '.trw.models', '.trw.water', '.trw.terrain',
                   '.trw.baselines', '.preview', '.generation.json', '.presentation.json'):
        source = worlds / (args.source + suffix)
        if source.is_dir():
            clone_bytes += sum(p.stat().st_size for p in source.rglob('*') if p.is_file())
        elif source.is_file():
            clone_bytes += source.stat().st_size
    # Preflight before creating a save clone or report folder. Reserve expected
    # capture space as well as the existing hard free-space floor; never lower it.
    report_bytes = (256 if not args.without_trace else 32) * 2**20
    require_free_space(worlds, clone_bytes + report_bytes)
    require_free_space(ROOT, clone_bytes + report_bytes)
    native = verify_pack_native() if args.executable else None
    retained_capacity = capacity(ROOT)
    maintain_traces(ROOT, apply=True)
    admit(ROOT, report_bytes=report_bytes)
    limits = load_budgets()
    storage = dict(source_clone_bytes=clone_bytes, planned_capture_bytes=report_bytes,
                   minimum_free_bytes=limits['minimum_free_bytes'],
                   free_space_warning_bytes=limits['free_space_warning_bytes'],
                   free_before=shutil.disk_usage(ROOT).free,
                   scope='Preflight before cloning; retained evidence/worlds are not automatically deleted')
    if storage['free_before'] < limits['free_space_warning_bytes']:
        print('STORAGE_WARNING: {:.2f} GiB free, below the existing {:.0f} GiB warning; '
              'review retained development artifacts before further batches.'.format(
                  storage['free_before'] / 2**30, limits['free_space_warning_bytes'] / 2**30), flush=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/performance_changes' / (stamp + '_' + args.label)
    folder.mkdir(parents=True)
    slot = 'StartupBench_FPS_' + stamp[:-1]
    copied = clone_once(worlds, args.source, slot)
    (worlds / (slot + '.diagnostic.json')).write_text(json.dumps({
        'owner': 'check_frame_trace_world', 'source': args.source,
        'report': str(folder), 'purpose': 'Isolated performance capture, explicit launch only'
    }, indent=2), encoding='utf-8')
    for suffix in ('.preview', '.generation.json', '.presentation.json'):
        source, target = worlds / (args.source + suffix), worlds / (slot + suffix)
        if source.is_dir():
            shutil.copytree(source, target)
        elif source.is_file():
            shutil.copy2(source, target)
    runtime = ['--main-pack', str(ROOT / 'dist/TerraForest.pck')] if args.executable else []
    command = [str(ROOT / 'TerraForest.exe' if args.executable else config.godot), *runtime,
               '--path', str(ROOT / 'dist' if args.executable else ROOT), '--windowed', '--position', '-2400,-1600',
               '--resolution', '1920x1080', '--max-fps', '60', '--log-file', str(folder / 'engine.log'),
               '--script', str(ROOT / 'tests/frame_trace_world.gd'), '--', '--trace-world-slot=' + slot,
               '--trace-world-output=' + folder.as_posix()]
    if args.normal_window:
        offset = command.index('--windowed')
        del command[offset:offset + 3]
        command += ['--trace-normal-window']
    if args.human:
        command += ['--trace-human']
    if args.combat_probe:
        command += ['--trace-combat-probe']
    if args.short:
        command += ['--trace-short']
    if args.save:
        command += ['--trace-save']
    if args.legacy_structure_capture:
        command += ['--trace-legacy-structure-capture']
    if args.light_abba:
        command += ['--trace-light-abba']
    if args.player_abba:
        command += ['--trace-player-abba']
    if args.legacy_hidden_hud:
        command += ['--trace-legacy-hidden-hud']
    if args.legacy_canopy_snapshot:
        command += ['--trace-legacy-canopy-snapshot']
    if args.render_thread:
        command[1:1] = ['--render-thread', args.render_thread]
    if args.rendering_driver:
        command[1:1] = ['--rendering-driver', args.rendering_driver]
        command += ['--trace-expected-driver=' + args.rendering_driver]
    if args.without_gpu_timers:
        command += ['--trace-without-gpu-timers']
    if args.verbose:
        command.insert(1, '--verbose')
    if args.gpu_profile or args.render_stages:
        command.insert(1, '--gpu-profile')
    if args.quiet_render_stages:
        command.insert(1, '--quiet')
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
    if args.grounded_walk:
        command += ['--trace-grounded-walk', '--trace-walk-seconds=' + str(args.walk_seconds)]
    if args.destruction_load:
        command += ['--trace-destruction-load']
    if args.legacy_blast_batches:
        command += ['--legacy-blast-batches']
    if args.legacy_debris_nodes:
        command += ['--legacy-debris-nodes']
    if args.pooled_debris:
        command += ['--pooled-debris']
    if args.render_gpu_stages:
        command += ['--frame-trace-render-gpu-stages']
    if args.legacy_structure_retirement:
        command += ['--legacy-structure-retirement']
    if args.destruction_deadline:
        command += ['--trace-destruction-deadline=' + str(args.destruction_deadline)]
    if args.legacy_owner_bounds:
        command += ['--trace-legacy-owner-bounds']
    if args.collision_piece_triangles:
        command += ['--trace-collision-piece-triangles=' + str(args.collision_piece_triangles)]
    if args.uncapped:
        command += ['--trace-uncapped']
    if not args.without_trace:
        command += ['--frame-trace', '--frame-trace-dir=' + str(folder / 'traces')]
    record = dict(command=command, clone=copied, storage_preflight=storage,
                  retention_capacity=retained_capacity, **revision_metadata())
    record['diagnostic_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in [ROOT/'tests/frame_trace_world.gd', ROOT/'tests/combat_cadence_probe.gd', ROOT/'tests/render_inventory.gd',
                                            ROOT/'tests/render_partition_probe.gd', ROOT/'tests/render_occlusion_probe.gd', ROOT/'tests/cover_outdoor_probe.gd', ROOT/'tests/destruction_load_probe.gd',
                                            ROOT/'addons/world_runtime/frame_trace.gd', ROOT/'addons/world_runtime/render_trace.gd', Path(__file__)]}
    if args.human or args.combat_probe:
        record['source_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                   for base in ('addons', 'demo') for p in sorted((ROOT / base).rglob('*'))
                                   if p.is_file() and p.suffix in ('.gd', '.tscn', '.gdshader')}
    if args.executable:
        record['pack_sha256'] = hashlib.sha256((ROOT / 'dist/TerraForest.pck').read_bytes()).hexdigest()
        record['pack_native_sha256'] = native
    record['native_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((ROOT / 'addons').glob('*/bin/*.dll'))}
    if args.destruction_load or args.destruction_deadline:
        record['destruction_source_sha256'] = {
            name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                'addons/player_runtime/combat_world.gd', 'addons/player_runtime/destruction_effects.gd',
                'addons/player_runtime/native/destruction_coordinator.cpp',
                'addons/player_runtime/native/destruction_coordinator.hpp',
                'addons/player_runtime/destruction_trace.gd', 'tests/destruction_deadline_probe.gd',
                'addons/player_runtime/structural_integrity.gd', 'addons/structures/structures_world.gd',
                'addons/world_ecosystem/ground_cover.gd', 'addons/world_ecosystem/world_ecosystem.gd',
                'addons/world_ecosystem/boulder_horizon.gd', 'addons/volumetric_water/lake_world.gd')}
    manifest = folder / 'run.json'
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print('CAPTURE ' + str(folder), flush=True)
    record['result'] = execute(command, folder, 600 if args.human else 300, '' if args.quiet_render_stages else 'FRAME_TRACE_WORLD ok=true')
    if args.quiet_render_stages:
        completion_path = folder / 'completion.json'
        try:
            completion = json.loads(completion_path.read_text(encoding='utf-8'))
        except (ValueError, OSError):
            completion = {}
        verified = completion == dict(schema=1, slot=slot, ok=True, shutdown_saved=True)
        record['result']['required_text_found'] = None
        record['result']['completion_file_verified'] = verified
        record['result']['passed'] &= verified
    if args.script_profile:
        record['result']['script_profiler_started'] = 'BEGIN PROFILING' in (folder / 'console.log').read_text(encoding='utf-8', errors='replace')
        record['result']['passed'] &= record['result']['script_profiler_started']
    if args.render_stages:
        available = any(row.get('render_markers', {}).get('available', False)
                        for path in (folder / 'traces').glob('trace_*.json')
                        for row in json.loads(path.read_text(encoding='utf-8')).get('frames', []))
        record['result']['render_markers_available'] = available
        record['result']['passed'] &= available
    if args.require_native_process_profiles:
        frames = {(row['frame'], row['at_us']): row
                  for path in (folder / 'traces').glob('trace_*.json')
                  for row in json.loads(path.read_text(encoding='utf-8')).get('frames', [])
                  if row.get('phase') == 'gameplay'}
        counts = {owner: sum(bool(row.get('native_world_process', {}).get(owner, {}).get('current'))
                             for row in frames.values())
                  for owner in ('blocks', 'model_horizon', 'resident_lights')}
        record['result']['native_process_current_frames'] = counts
        record['result']['passed'] &= all(counts.values())
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    # Outside gameplay: keep two recent worlds ready to open; older owned states
    # are reconstructed/hash-verified in the shared archive before retirement.
    try:
        retention = maintain(ROOT, worlds, apply=True)
        record['retention'] = {key:retention[key] for key in ('receipt','completed','errors','new_archive_bytes') if key in retention}
        record['trace_retention'] = maintain_traces(ROOT, apply=True)
    except (OSError, ValueError) as error:
        record['retention'] = {'errors': [str(error)]}
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(('PASS ' if record['result']['passed'] else 'FAIL ') + str(folder), flush=True)
    if record['retention'].get('errors'):
        print('RETENTION_FAILED: evidence/worlds preserved; inspect run.json', flush=True)
    return 0 if record['result']['passed'] and not record['retention'].get('errors') else 1


if __name__ == '__main__':
    raise SystemExit(main())
