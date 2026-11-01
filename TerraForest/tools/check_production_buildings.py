# SPDX-License-Identifier: 0BSD
"""Exercise normal browser creation, trade and fresh-process restore in the PCK."""
import datetime
import json
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native


def main():
    config, _ = parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports/production_buildings/packed' / stamp
    folder.mkdir(parents=True)
    (folder.parent.parent / 'packed_latest.json').write_text(json.dumps({'folder': str(folder)}))
    # Tests are deliberately absent from shipping packs. External harnesses use
    # the exported production scripts/assets and the normal browser handlers.
    names = ['window_session_flow', 'world_recipe_generation', 'approved_city_world',
             'civic_world', 'production_buildings']
    for name in names:
        text = (ROOT / 'tests' / (name + '.gd')).read_text(encoding='utf-8')
        for dependency in names:
            text = text.replace('res://tests/' + dependency + '.gd',
                                (folder / (dependency + '.gd')).as_posix())
        if name == 'production_buildings':
            text = text.replace('folder="res://reports/production_buildings"',
                                'folder="' + folder.as_posix() + '"')
        (folder / (name + '.gd')).write_text(text, encoding='utf-8')
    native = verify_pack_native()
    results = []
    for phase, arguments in [('create', ['--create-production']), ('play', []),
                             ('restore', ['--restore-production'])]:
        run = folder / phase
        run.mkdir()
        command = [config.godot, '--main-pack', str(ROOT / 'dist/TerraForest.pck'),
                   '--path', str(ROOT / 'dist'), '--log-file', str(run / 'engine.log'),
                   '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60',
                   '--script', str(folder / 'production_buildings.gd'), '--', *arguments]
        result = execute(command, run, 600, 'PRODUCTION_BUILDINGS checks=')
        results.append({'phase': phase, 'command': command, **result})
        (run / 'run.json').write_text(json.dumps({'native': native, **results[-1]}, indent=2))
        (folder / 'run.json').write_text(json.dumps({'native': native, 'phases': results,
            'passed': len(results) == 3 and all(row['passed'] for row in results)}, indent=2))
        print(('PASS ' if result['passed'] else 'FAIL ') + phase + ' ' + str(run), flush=True)
        if not result['passed']:
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
