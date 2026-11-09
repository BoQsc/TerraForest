# SPDX-License-Identifier: CC0-1.0
"""Extend the established Rack wrist audit with the three left-thumb joints.

Run through Blender with -- --package PACKAGE --output DIRECTORY.
The existing wrist gates keep their original tolerances. This extension supplies
all thumb world rotations to the existing native Godot comparer and reports
continuous chain geometry for review; it does not certify anatomy or contact.
Only Python's standard library and Blender's bundled mathutils are used.
"""
from pathlib import Path
import argparse
import json
import math
import sys

from mathutils import Vector


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    package, output = args.package.resolve(), args.output.resolve()
    sys.path.insert(0, str(package / 'source/validation'))
    import export_hand_path_probe as wrist
    from joint_step_summary import sha, angle

    # The unchanged inherited checker measures the wrist recipe at 289 samples.
    wrist.main()
    path = output / 'FINAL_RAW_GLB_HAND_PATH.json'
    report = json.loads(path.read_text())
    reader = wrist.PoseReader(package / 'Human.px9_eclipse.glb')
    definition = json.loads((package / 'item_px9.json').read_text())
    clip = next(row for row in definition['actions'] if row['id'] == 'rack')
    bones = tuple('LeftHandThumb' + str(i) for i in (1, 2, 3))
    rows, prior = [], None
    quarter_steps, integer_steps = [], []
    integer_prior = None
    for sample in report['samples']:
        frame = sample['frame']
        pose = reader.pose(clip['human_clip'], frame)
        hand_inverse = pose['LeftHand'].inverted()
        row = {'frame': frame, 'seconds': frame / 60, 'joints': {}}
        axes = []
        for name in bones:
            matrix = pose[name]
            quaternion = matrix.to_quaternion().normalized()
            sample['bone_world_quaternions'][name] = list(quaternion)
            local_parent = pose['LeftHand' if name.endswith('1') else name[:-1] + str(int(name[-1]) - 1)].inverted() @ matrix
            axis = (quaternion @ Vector((0, 1, 0))).normalized()
            axes.append(axis)
            row['joints'][name] = {
                'head_glb': list(matrix.translation),
                'head_in_hand': list(hand_inverse @ matrix.translation),
                'axis_glb': list(axis),
                'world_quaternion_wxyz': list(quaternion),
                'local_quaternion_wxyz': list(local_parent.to_quaternion().normalized()),
            }
            if prior:
                step = angle(prior['joints'][name]['local_quaternion_wxyz'],
                             row['joints'][name]['local_quaternion_wxyz'])
                quarter_steps.append({'from': prior['frame'], 'to': frame, 'bone': name, 'degrees': step})
            if frame.is_integer() and integer_prior:
                step = angle(integer_prior['joints'][name]['local_quaternion_wxyz'],
                             row['joints'][name]['local_quaternion_wxyz'])
                integer_steps.append({'from': integer_prior['frame'], 'to': frame, 'bone': name, 'degrees': step})
        row['consecutive_axis_angles_degrees'] = [math.degrees(axes[i].angle(axes[i+1])) for i in (0, 1)]
        rows.append(row)
        prior = row
        if frame.is_integer():
            integer_prior = row
    report['scope'] += ' The three left-thumb world rotations are included at all289 samples for native runtime comparison.'
    report['thumb_extension'] = {
        'schema': 'px9-rack-thumb-quarter-frame-diagnostic-1',
        'bones': list(bones), 'sample_count': len(rows),
        'integer_sample_count': sum(row['frame'].is_integer() for row in rows),
        'maximum_quarter_frame_local_step': max(quarter_steps, key=lambda row: row['degrees']),
        'maximum_integer_frame_local_step': max(integer_steps, key=lambda row: row['degrees']),
        'integer_steps_above30degrees': [row for row in integer_steps if row['degrees'] > 30],
        'rows': rows,
        'limitations': 'Bone-chain kinematics only. Smooth motion does not establish realistic anatomical range, skin deformation, thumb pressure or weapon-surface clearance.',
    }
    report['source_hashes']['source/validation/export_rack_thumb_path_probe.py'] = sha(Path(__file__))
    report['checks']['thumb_289_quarter_frames_and73_integer_frames'] = len(rows) == 289 and sum(row['frame'].is_integer() for row in rows) == 73
    report['checks']['thumb_no_integer_local_step_over30degrees'] = not report['thumb_extension']['integer_steps_above30degrees']
    report['checks']['thumb_values_finite'] = all(math.isfinite(value) for row in rows for joint in row['joints'].values() for values in joint.values() for value in values)
    report['passed'] = all(report['checks'].values())
    path.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': report['checks'],
                      'thumb_maximum_integer_step': report['thumb_extension']['maximum_integer_frame_local_step'],
                      'thumb_maximum_quarter_step': report['thumb_extension']['maximum_quarter_frame_local_step']}, indent=2))
    if not report['passed']:
        raise RuntimeError('Rack wrist/thumb exported path check failed.')


if __name__ == '__main__':
    main()
