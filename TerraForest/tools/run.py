"""Launch TerraForest with an existing Godot 4.7 executable; no installation required."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import json
import re

ROOT = Path(__file__).resolve().parents[1]
def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    steam = Path(r'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE') or shutil.which('godot') or (str(steam) if steam.is_file() else None))
    parser.add_argument('--renderer', choices=['forward_plus', 'mobile', 'gl_compatibility'], default='forward_plus')
    parser.add_argument('--temporary', action='store_true')
    parser.add_argument('--scene', choices=['world', 'structures'], default='world')
    parser.add_argument('--block-textures', choices=['original', 'terraforest'], help='Override the project block material set for this launch')
    parser.add_argument('--generator', type=int, choices=[1, 2, 3, 4], help='New worlds: 1 original, 2 mountains/caves, 3 ore veins, 4 ore veins and lakes')
    parser.add_argument('--seed', type=int, help='New-world seed; existing saves retain their generator and seed')
    parser.add_argument('--slot', help='Save slot; generated profiles automatically receive separate slots')
    parser.add_argument('--dry-run', action='store_true', help='Print launch settings without running Godot')
    args, extra = parser.parse_known_args(argv)
    if not args.godot:
        parser.error('Pass --godot PATH or set GODOT_EXE to an existing Godot executable')
    if args.seed is not None and not 0 <= args.seed <= 2147483647:
        parser.error('--seed must be between 0 and 2147483647')
    if args.slot is not None and not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,47}', args.slot):
        parser.error('--slot must be an identifier of at most 48 ASCII characters')
    # These flags have validated public equivalents; prevent forwarded overrides.
    if any(value.split('=', 1)[0] in ('--world-generator', '--world-seed', '--world-slot', '--block-textures') for value in extra):
        parser.error('Use --generator, --seed, --slot and --block-textures instead of raw flags')
    return args, extra


def launch_details(args, extra):
    engine = Path(args.godot)
    direct = engine.parent / 'godot.windows.opt.tools.64.exe'
    if direct.is_file():
        engine = direct
    generator = args.generator if args.generator is not None else 1
    seed = args.seed if args.seed is not None else 1703
    selected = args.generator is not None or args.seed is not None
    slot = args.slot or (f'generated_g{generator}_s{seed}' if selected else 'world')
    command = [str(engine), '--path', str(ROOT), '--rendering-method', args.renderer,
               '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
               f'res://demo/{args.scene}.tscn', '--', f'--world-generator={generator}',
               f'--world-seed={seed}', f'--world-slot={slot}',
               *([f'--block-textures={args.block_textures}'] if args.block_textures else []),
               *(['--temporary'] if args.temporary else []), *extra, '--max-fps=60']
    return {'slot': slot, 'new_world_generator': generator, 'new_world_seed': seed,
            'temporary': args.temporary, 'existing_save_takes_precedence': True, 'command': command}


def main(argv=None):
    args, extra = parse_args(argv)
    details = launch_details(args, extra)
    if args.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return subprocess.call(details['command'])


if __name__ == '__main__':
    raise SystemExit(main())
