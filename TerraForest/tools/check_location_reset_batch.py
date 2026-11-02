# SPDX-License-Identifier: 0BSD
"""Exercise coordinated native-owner rollback without world saves or library copies."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil

from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / 'reports/location_reset_batch' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    sources = ['tests/location_reset_batch.gd', 'addons/world_runtime/location_reset_batch.gd',
               'addons/world_runtime/location_capture.gd', 'addons/volumetric_terrain/mesh_codec.gd']
    record = dict(pack=args.pack, source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sources},
                  native=verify_pack_native() if args.pack else None, variants=[], **revision_metadata())
    for variant in (('pack',) if args.pack else ('debug', 'release')):
        project = folder / variant
        project.mkdir()
        libraries = {}
        if args.pack:
            pack = ROOT / 'dist/TerraForest.pck'
            record['pack_sha256'] = hashlib.sha256(pack.read_bytes()).hexdigest()
            runtime = ['--path', str(ROOT / 'dist'), '--main-pack', str(pack)]
            script = str(ROOT / sources[0])
        else:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Location Reset Batch Check"\n')
            for source in sources:
                destination = project / source
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / source, destination)
            for addon in ('structures', 'player_runtime', 'world_runtime', 'vegetation_runtime', 'volumetric_water', 'volumetric_terrain'):
                descriptor = 'terrain_core' if addon == 'volumetric_terrain' else addon
                relative = f'addons/{addon}/{descriptor}.gdextension'
                contents = (ROOT / relative).read_text()
                if variant == 'release':
                    release = re.search(r'^windows\.release\.x86_64\s*=\s*"([^"]+)"', contents, re.MULTILINE)
                    if not release:
                        raise ValueError(f'Missing release library: {relative}')
                    contents = re.sub(r'^windows\.debug\.x86_64\s*=.*$', f'windows.debug.x86_64 = "{release.group(1)}"', contents, flags=re.MULTILINE)
                for resource in re.findall(r'"(res://[^"\n]+\.dll)"', contents):
                    library = ROOT / resource.removeprefix('res://')
                    libraries[str(library.relative_to(ROOT))] = hashlib.sha256(library.read_bytes()).hexdigest()
                    contents = contents.replace(resource, library.as_posix())
                destination = project / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(contents)
            runtime = ['--path', str(project)]
            script = 'res://' + sources[0]
        command = [config.godot, '--headless', *runtime, '--script', script, '--log-file', str(project / 'engine.log')]
        result = execute(command, project, 90, 'LOCATION_RESET_BATCH checks=')
        log = (project / 'console.log').read_text(encoding='utf-8', errors='replace')
        assertions = re.search(r'LOCATION_RESET_BATCH checks=(\d+) failures=(\d+)', log)
        timings = re.search(r'LOCATION_RESET_TIMINGS (.+)', log)
        record['variants'].append(dict(variant=variant, command=command, result=result, libraries=libraries,
                                       assertions=list(map(int, assertions.groups())) if assertions else None,
                                       timings=json.loads(timings.group(1)) if timings else None))
    record['passed'] = all(row['result']['passed'] and row['assertions'] and row['assertions'][1] == 0 for row in record['variants'])
    (folder / 'run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(('PASS ' if record['passed'] else 'FAIL ') + str(folder))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
