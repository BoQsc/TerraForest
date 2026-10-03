"""Exercise the existing publication path in a clean headless release project."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--worker', action='store_true', help='Drive public stream edits through the real worker')
parser.add_argument('--snapshot-terrain', action='store_true', help='Use candidate snapshot geometry in the real worker')
parser.add_argument('--brick-terrain', action='store_true', help='Use vertically bounded terrain in the real worker and stream')
parser.add_argument('--region-terrain', action='store_true', help='Use locally replaceable Surface Nets regions')
parser.add_argument('--transition', action='store_true', help='Exercise native mixed-cut coverage transitions')
parser.add_argument('--density', action='store_true', help='Exercise bounded density query backend jobs')
parser.add_argument('--density-stream', action='store_true', help='Exercise stream-side density reply freshness')
parser.add_argument('--density-latency', action='store_true', help='Measure query latency behind meshing')
parser.add_argument('--geometry-cache', action='store_true', help='Exercise native content cache through the real backend and restart')
args = parser.parse_args()
test = 'terrain_density_backend_probe' if args.density else ('terrain_transition_probe' if args.transition else ('terrain_worker_publication_probe' if args.worker else 'terrain_publication_probe'))
if args.density_stream: test='terrain_density_stream_probe'
if args.density_latency: test='terrain_density_latency_probe'
if args.geometry_cache: test='terrain_geometry_cache_probe'
source = ROOT / 'addons/volumetric_terrain'
files = list(source.glob('*.gd')) + [ROOT / 'tests/terrain_publication_probe.gd']
if args.geometry_cache:
    files += [ROOT / 'tests/terrain_geometry_cache_probe.gd', source / 'native/geometry_content_key.hpp', source / 'native/terrain_binding.cpp', source / 'native/core.cpp']
if args.density:
    files.append(ROOT / 'tests/terrain_density_backend_probe.gd')
if args.density_stream:
    files.append(ROOT / 'tests/terrain_density_stream_probe.gd')
if args.density_latency:
    files.append(ROOT / 'tests/terrain_density_latency_probe.gd')
if args.worker or args.transition:
    files.append(ROOT / 'tests/terrain_worker_publication_probe.gd')
if args.transition:
    files.append(ROOT / 'tests/terrain_transition_probe.gd')
library = source / 'bin/terrain_core.windows.template_release.x86_64.dll'
files += [library, Path(__file__).resolve()]
with tempfile.TemporaryDirectory(prefix='publication_', dir=ROOT / '.build') as temporary:
    project = Path(temporary)
    addon = project / 'addons/volumetric_terrain'
    (addon / 'bin').mkdir(parents=True)
    for script in source.glob('*.gd'):
        shutil.copy2(script, addon / script.name)
    shutil.copy2(library, addon / 'bin' / library.name)
    (addon / 'terrain_core.gdextension').write_text('''[configuration]
entry_symbol = "terrain_library_init"
compatibility_minimum = "4.7"
[libraries]
windows.debug.x86_64 = "res://addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll"
windows.release.x86_64 = "res://addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll"
''')
    (project / 'tests').mkdir()
    shutil.copy2(ROOT / 'tests/terrain_publication_probe.gd', project / 'tests/terrain_publication_probe.gd')
    if args.geometry_cache:
        shutil.copy2(ROOT / 'tests/terrain_geometry_cache_probe.gd', project / 'tests/terrain_geometry_cache_probe.gd')
    if args.density:
        shutil.copy2(ROOT / 'tests/terrain_density_backend_probe.gd', project / 'tests/terrain_density_backend_probe.gd')
    if args.density_stream:
        shutil.copy2(ROOT / 'tests/terrain_density_stream_probe.gd', project / 'tests/terrain_density_stream_probe.gd')
    if args.density_latency:
        shutil.copy2(ROOT / 'tests/terrain_density_latency_probe.gd', project / 'tests/terrain_density_latency_probe.gd')
    if args.worker or args.transition:
        shutil.copy2(ROOT / 'tests/terrain_worker_publication_probe.gd', project / 'tests/terrain_worker_publication_probe.gd')
    if args.transition:
        shutil.copy2(ROOT / 'tests/terrain_transition_probe.gd', project / 'tests/terrain_transition_probe.gd')
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Terrain publication probe"\n')
    result = subprocess.run([args.godot, '--headless', '--path', str(project), '--script',
                             f'res://tests/{test}.gd'] + (['--', '--region-terrain', '--profile-owned-regions'] if args.region_terrain else (['--', '--brick-terrain'] if args.brick_terrain else (['--', '--snapshot-terrain'] if args.snapshot_terrain else []))), capture_output=True, text=True, timeout=90)
    log = result.stdout + '\n' + result.stderr
    reports = ROOT / 'reports'
    reports.mkdir(exist_ok=True)
    report_name = test + ('_regions' if args.region_terrain else ('_bricks' if args.brick_terrain else ('_snapshot' if args.snapshot_terrain else '')))
    (reports / (report_name+'.log')).write_text(log, encoding='utf-8')
    print(log)
    if not (project / 'reports' / (test+'.json')).exists():
        raise SystemExit(1)
    report = json.loads((project / 'reports' / (test+'.json')).read_text())
    report['source_hashes'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    report['adoption_qualified'] = False
    report['snapshot_terrain'] = args.snapshot_terrain
    report['brick_terrain'] = args.brick_terrain
    (reports / (report_name+'.json')).write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(bool(result.returncode or report['failures'] or re.search(r'(?m)^(SCRIPT ERROR|ERROR:|FAIL |WARNING: ObjectDB instances leaked)', log)))
