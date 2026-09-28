"""Sequential 1080p fullscreen collision profiles; preserve each exact worst piece."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True, type=Path)
parser.add_argument('--sizes', nargs='+', type=int, default=[1024, 512, 256])
args = parser.parse_args()
if any(size < 256 or size > 1024 for size in args.sizes):
    parser.error('Piece sizes must be 256..1024')
engine = args.godot
direct = engine.parent / 'godot.windows.opt.tools.64.exe'
if direct.exists():
    engine = direct
reports = root / 'reports'
reports.mkdir(exist_ok=True)
for index, size in enumerate(args.sizes):
    result = subprocess.run([str(engine), '--path', str(root), '--script',
        'res://tests/terrain_collision_profile.gd', '--', f'--collision-piece-triangles={size}'],
        capture_output=True, text=True, timeout=120)
    log = result.stdout + '\n' + result.stderr
    stem = f'terrain_collision_profile_{index}_{size}'
    (reports / (stem + '.log')).write_text(log, encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR' in log or 'ERROR:' in log or 'FAIL ' in log:
        raise SystemExit(log)
    report = json.loads((reports / 'terrain_collision_profile.json').read_text())
    if not report['pass'] or report['configured_piece_triangles'] != size:
        raise SystemExit('Invalid profile report')
    shutil.copy2(reports / 'terrain_collision_profile.json', reports / (stem + '.json'))
    shutil.copy2(reports / 'terrain_collision_worst.faces', reports / (stem + '.faces'))
    print(json.dumps({key: report[key] for key in ['configured_piece_triangles',
        'ready_ms', 'resident_tiles', 'resident_shapes', 'runtime_cook',
        'engine_static_bytes', 'scene_nodes', 'steady_frame_intervals',
        'steady_physics_monitor']}), flush=True)
