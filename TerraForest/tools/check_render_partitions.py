"""Check render-page ownership with isolated debug or release native libraries."""
# SPDX-License-Identifier: 0BSD
import argparse
import datetime
import hashlib
import json
import shutil
from pathlib import Path
from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--suite', action='store_true', help='Include existing placement, continuity, region and retirement contracts')
    args = parser.parse_args()
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report = ROOT/'reports/render_partition_checks'/stamp
    project = ROOT/'.build'/('render_partitions_'+stamp)
    report.mkdir(parents=True); project.mkdir(parents=True)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TerraForest Render Partition Check"\n')
    target = 'template_release' if args.release else 'template_debug'
    library = 'structures.windows.'+target+'.x86_64.dll'
    source = ROOT/'addons/structures'
    destination = project/'addons/structures'
    (destination/'bin').mkdir(parents=True)
    shutil.copy2(source/'bin'/library, destination/'bin'/library)
    descriptor = (source/'structures.gdextension').read_text().replace('template_debug', target).replace('template_release', target)
    (destination/'structures.gdextension').write_text(descriptor)
    if args.suite:
        shutil.copytree(source/'prefabs', destination/'prefabs')
    (project/'.godot').mkdir(); (project/'tests').mkdir()
    (project/'.godot/extension_list.cfg').write_text('res://addons/structures/structures.gdextension\n')
    tests = [('render_partitions', 'RENDER_PARTITIONS checks=')]
    if args.suite:
        tests += [('vegetation_edit_continuity', 'VEGETATION_EDIT_CONTINUITY checks='),
                  ('vegetation_page_retirement', 'VEGETATION_PAGE_RETIREMENT failures=0'),
                  ('transient_collection_retirement', 'TRANSIENT_COLLECTION_RETIREMENT failures=0'),
                  ('static_model_regions', 'STATIC_MODEL_REGIONS checks='),
                  ('static_placements', 'STATIC_PLACEMENTS_RESULT')]
    record = dict(target=target, project=str(project),
                  native_sha256=hashlib.sha256((destination/'bin'/library).read_bytes()).hexdigest(),
                  scope='Isolated GPU-buffer/API ownership and continuity checks. Not a full-world FPS comparison.',
                  outcomes=[], **revision_metadata())
    for test, marker in tests:
        script = ROOT/'tests'/(test+'.gd')
        shutil.copy2(script, project/'tests'/script.name)
        folder = report/test; folder.mkdir()
        command = [str(config.godot), '--path', str(project), '--windowed', '--position', '-2400,-1600',
                   '--resolution', '1280x720', '--max-fps', '60', '--log-file', str(folder/'engine.log'),
                   '--script', 'res://tests/'+script.name]
        outcome = dict(test=test, test_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), command=command,
                       result=execute(command, folder, 150, marker))
        for result in [project/'reports'/test/'result.json', project/'reports'/(test+'.json')]:
            if result.is_file():shutil.copy2(result, folder/'result.json')
        record['outcomes'].append(outcome)
        (report/'run.json').write_text(json.dumps(record, indent=2))
        print(('PASS ' if outcome['result']['passed'] else 'FAIL ')+test, flush=True)
    print(report, flush=True)
    return 0 if all(row['result']['passed'] for row in record['outcomes']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
