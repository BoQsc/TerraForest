# SPDX-License-Identifier: CC0-1.0
"""Re-evaluate portable authoring from the delivered source, read-only.

Run in Blender with -- --package PACKAGE --report REPORT.json.
Uses native Blender APIs and Python's standard library.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys

import bpy


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    package = args.package.resolve()
    source = package / 'source'
    sys.path.insert(0, str(source))
    import author_px9_first_person as author
    frozen = json.loads((package / 'validation/AUTHORED_FRAMES.json').read_text())
    scene, human, item, solver, attachment = author.setup(source / 'Human.px9_eclipse.blend')
    errors = []
    rows = []
    keys = ('weapon_world_blender', 'right_hand_blender', 'left_hand_blender',
            'magazine_delta_blender')
    for action in ('reload_empty', 'rack'):
        for expected in frozen['clips'][action]['samples']:
            frame = expected['frame']
            actual = author.pose_sample(scene, human, item, solver, action, frame)
            maximum = max(abs(actual[key][r][c] - expected[key][r][c])
                          for key in keys for r in range(4) for c in range(4))
            state_equal = all(actual[key] == expected[key] for key in
                              ('left_contact', 'slide_offset_metres', 'case_visible'))
            rows.append({'action': action, 'frame': frame,
                         'maximum_matrix_component_difference': maximum,
                         'state_equal': state_equal})
            if maximum > 1e-6 or not state_equal:
                errors.append(rows[-1])
    report = {
        'schema': 'px9-portable-authoring-validation-2',
        'passed': not errors and solver.rest_unchanged(),
        'scope': 'Recompute Reload_Empty and Rack from the packaged combined Blender source and packaged author modules; compare every inclusive frame against the final authored-frame record. No original input-path dependency is used.',
        'sample_count': len(rows), 'actions': ['reload_empty', 'rack'],
        'maximum_matrix_component_difference': max(row['maximum_matrix_component_difference'] for row in rows),
        'rest_unchanged': solver.rest_unchanged(),
        'input_hashes': {name: digest(package / name) for name in (
            'source/Human.px9_eclipse.blend', 'source/author_px9_first_person.py',
            'source/px9_motion.py', 'source/human_arm_solver.py',
            'source/hand_weight_patch.json', 'validation/AUTHORED_FRAMES.json')},
        'errors': errors, 'rows': rows,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'rows'}, indent=2))
    if not report['passed']:
        raise RuntimeError('Portable authoring differs from the frozen final frames')


if __name__ == '__main__':
    main()
