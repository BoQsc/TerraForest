# SPDX-License-Identifier: 0BSD
"""Create and verify a furnished gameplay checkpoint without replacing progress."""
import argparse
import datetime
import json
import os
import re
import uuid
import shutil
import time
from pathlib import Path
from clone_world import clone_once
from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute


def prepare(engine, worlds, folder, destination="combined_gameplay", layout="cottages", seed=1703, progress=None, cancel_requested=None, natural=False, terrain_fitted=False, ocean=True):
    if type(seed) is not int or not 0 <= seed <= 2147483647:
        raise ValueError("Seed must be an integer between 0 and 2147483647")
    if layout not in ('cottages', 'mixed', 'regional', 'poi', 'lakes', 'districts'):
        raise ValueError("Invalid settlement layout")
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', destination):
        raise ValueError("Invalid destination slot")
    if terrain_fitted and layout != 'districts':
        raise ValueError("Terrain-fitted worlds require the districts layout")
    if not ocean and not terrain_fitted:
        raise ValueError("Ocean selection requires terrain-fitted worlds")
    worlds.mkdir(parents=True, exist_ok=True)
    if (worlds / (destination + '.trw')).exists():
        print('Existing combined gameplay save retained; nothing regenerated.')
        return 0
    # A second preparation must not race the fixed destination or reports.
    lock = worlds / (destination + '.prepare.lock')
    with lock.open('x') as handle:
        handle.write(str(os.getpid()))
    try:
        slot = 'combined_stage_' + uuid.uuid4().hex
        folder.mkdir(parents=True)
        report = folder / 'checkpoint.json'
        base = [str(engine), '--path', str(ROOT), '--fullscreen', '--resolution',
                '1920x1080', '--max-fps', '60', '--script',
                'res://tools/prepare_terrain_world.gd' if terrain_fitted else 'res://tools/prepare_combined_world.gd', '--',
                '--world-slot=' + slot, '--world-generator=' + ('19' if terrain_fitted and ocean else '17' if terrain_fitted else '16' if natural and layout == 'districts' else '13' if layout == 'districts' else '12' if layout == 'lakes' else '11' if layout == 'poi' else '8' if layout == 'regional' else '4'), '--world-seed=' + str(seed),
                '--ground-cover', '--actors', '--vehicle-fleet', '--checkpoint-layout=' + layout, '--checkpoint-report=' + str(report),
                '--derived-cache=user://' + slot]
        metadata = dict(slot=slot, layout=layout, seed=seed, terrain_fitted=terrain_fitted, ocean=ocean if terrain_fitted else None, **revision_metadata(), phases=[])
        for phase in ('create', 'reopen'):
            if cancel_requested is not None and cancel_requested(): return 2
            phase_dir = folder / phase
            phase_dir.mkdir()
            command = base + (['--reopen-checkpoint', '--gameplay-construction', '--vehicle-fleet'] if phase == 'reopen' else [])
            if terrain_fitted:
                command += ['--central-market', '--regional-connection', '--preparation-output=' + str(folder), '--reopen-terrain-lots' if phase == 'reopen' else '--save-terrain-lots']
                if phase == 'reopen': command.append('--snapshot-readonly')
            if progress is not None: progress('creating' if phase == 'create' else 'verifying')
            print(f'{phase}: preparing the existing settlement workflow at 1920x1080 / cap 60.', flush=True)
            options = {'cancel_requested': cancel_requested} if cancel_requested is not None else {}
            result = execute(command, phase_dir, 540 if layout in ("lakes", "districts") and phase == "create" else 270, ('TERRAIN_LOT_REOPEN failures=0' if phase == 'reopen' else 'TERRAIN_LOT_WORLD_REVIEW failures=0') if terrain_fitted else 'COMBINED_PREPARATION failures=0', **options)
            metadata['phases'].append(dict(command=command, result=result))
            (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
            if result.get('cancelled', False): return 2
            if not result['passed']:
                print('Preparation failed; gameplay save not published. Evidence: ' + str(phase_dir))
                return 1
        if cancel_requested is not None and cancel_requested(): return 2
        if progress is not None: progress('publishing')
        if cancel_requested is not None and cancel_requested(): return 2
        metadata['publication'] = clone_once(worlds, slot, destination)
        # Derived presentation assets are bounded and never replace world data.
        try:
            identity_path = folder / 'generation_plan_identity.json'
            if identity_path.is_file():
                # Provenance is small derived metadata, not a replacement for saved edits.
                identity = json.loads(identity_path.read_text(encoding='utf-8'))
                metadata['generation_plan'] = identity
                target = worlds / (destination + '.generation.json')
                pending = target.with_suffix('.json.tmp')
                pending.write_text(json.dumps(identity), encoding='utf-8')
                pending.replace(target)
            preview = worlds / (destination + '.preview')
            captures = [name for name in ('north', 'road', 'market') if (folder / ('loading_' + name + '.png')).is_file()]
            if captures:
                preview.mkdir(exist_ok=True)
                for name in captures:
                    shutil.copy2(folder / ('loading_' + name + '.png'), preview / (name + '.png'))
            presentation = worlds / (destination + '.presentation.json')
            presentation.write_text(json.dumps({'created': int(time.time()), 'seed': seed, 'preview_count': len(captures)}), encoding='utf-8')
        except OSError as error:
            metadata["presentation_warning"] = str(error)
            print("World published; optional preview metadata could not be written: " + str(error))
        (folder / 'run.json').write_text(json.dumps(metadata, indent=2))
        print('Prepared and reopened slot ' + destination + '. Evidence: ' + str(folder))
        return 0
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--destination', default='combined_gameplay', help='Create only when this save slot is absent')
    parser.add_argument('--layout', choices=('cottages', 'mixed', 'regional', 'poi', 'lakes', 'districts'), default='cottages')
    parser.add_argument('--terrain-fitted', action='store_true', help='Prepare the terrain-fitted northern neighborhood and central market')
    parser.add_argument('--no-ocean', action='store_true', help='Disable surrounding ocean and beaches for a new terrain-fitted world')
    parser.add_argument('--natural', action='store_true', help='Use the new natural-region generator for districts')
    parser.add_argument('--seed', type=int, default=1703, help='Deterministic new-world seed (0..2147483647); existing saves are preserved')
    parser.add_argument('--status-file', type=Path, help='Optional browser completion status file')
    parser.add_argument('--cancel-file', type=Path, help='Cancel before publication when this request file appears')
    args = parser.parse_args()
    if not 0 <= args.seed <= 2147483647: parser.error('Seed must be between 0 and 2147483647')
    if (args.terrain_fitted or args.no_ocean) and args.layout != 'districts': parser.error('Terrain-fitted worlds require --layout districts')
    if args.no_ocean and not args.terrain_fitted: parser.error('--no-ocean requires --terrain-fitted')
    if args.natural and args.layout != 'districts': parser.error('--natural requires --layout districts')
    config, _ = parse_args(['--godot', args.godot] if args.godot else [])
    worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/combined_preparation' / stamp
    def status(state, reason=''):
        if args.status_file is None: return
        value = dict(state=state, slot=args.destination, report=str(folder), reason=reason)
        temporary = args.status_file.with_suffix('.tmp')
        temporary.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(json.dumps(value), encoding='utf-8')
        temporary.replace(args.status_file)
    status('running')
    try:
        code = prepare(config.godot, worlds, folder, args.destination, args.layout, args.seed, natural=args.natural, terrain_fitted=args.terrain_fitted, ocean=not args.no_ocean, progress=status, cancel_requested=(lambda: args.cancel_file.exists()) if args.cancel_file is not None else None)
    except Exception as error:
        status('failed', str(error))
        raise
    status('ready' if code == 0 else 'cancelled' if code == 2 else 'failed', '' if code == 0 else 'Preparation cancelled; no world published' if code == 2 else 'Generation or save verification failed')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
