# SPDX-License-Identifier: CC0-1.0
"""Compare saved RACK release subframes, including inherited support contacts.

Run with Blender. Uses native bpy/mathutils and Python standard library only.
Neither source scene is modified or saved. Pass --baseline for a portable run.
"""
from pathlib import Path
import argparse, hashlib, json, sys
import bpy

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parents[1] if HERE.name == 'validation' and HERE.parent.name == 'source' else HERE / 'package'
sys.path.insert(0, str(PACKAGE / 'source/validation'))
import audit_rack_clearance as audit

TIMES = [q / 4 for q in range(160, 241)]
TOLERANCE_MM = 0.01


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect(path, label, report, destination):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    scene = bpy.context.scene
    human, item, body = (bpy.data.objects[n] for n in ('Human_Rig', 'WeaponSkeleton', 'Human_FP_Hands'))
    human.animation_data.use_nla = False
    item.animation_data.use_nla = False
    human.animation_data.action = bpy.data.actions['FP_PX9_ECLIPSE_Rack']
    item.animation_data.action = bpy.data.actions['PX9_FP__Rack']
    regions, weights = audit.regions_for(body)
    result = {'source_sha256': sha(path), 'frames': [], 'parts_topology': {}}
    report[label] = result
    for index, frame in enumerate(TIMES):
        row = audit.frame_metrics(scene, human, item, body, frame, regions, weights, 'coarse', result['parts_topology'])
        result['frames'].append(row)
        if index % 8 == 0:
            destination.write_text(json.dumps(report, indent=2) + '\n')
            print('SAVED_RELEASE_SUBFRAME', label, frame, flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, default=PACKAGE / 'source/Human.px9_eclipse.blend')
    parser.add_argument('--report', type=Path, default=PACKAGE / 'validation/RACK_TRANSITION_SUBFRAME_CONTACT.json')
    parser.add_argument('--recheck-existing', action='store_true', help='Recompute comparisons from complete hash-matched saved measurements without resampling.')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    report = {
        'schema': 'px9-rack-saved-transition-subframes/v2', 'passed': False, 'complete': False,
        'times': TIMES, 'clear_window': [40, 56], 'depth_tolerance_mm': TOLERANCE_MM,
        'scope': '81 saved-Action quarter-frame times from 40 through 60, all six left-hand regions and seven weapon parts, compared with revision 7. No recipe overrides.',
        'limits': ['Finite samples do not prove all triangle intersections absent.', 'Inherited support contacts near the endpoint are compared with the baseline rather than labeled clear.', 'Native wrist/thumb reproduction is validated separately.'],
        'baseline': {}, 'candidate': {},
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    if args.recheck_existing:
        report = json.loads(args.report.read_text())
        assert report['complete'] and report['times'] == TIMES
        old, new = report['baseline'], report['candidate']
        assert old['source_sha256'] == sha(args.baseline)
        assert new['source_sha256'] == sha(args.candidate)
        assert [row['frame'] for row in old['frames']] == TIMES
        assert [row['frame'] for row in new['frames']] == TIMES
    else:
        old = inspect(args.baseline, 'baseline', report, args.report)
        new = inspect(args.candidate, 'candidate', report, args.report)
    regressions, unknowns, baseline_unknowns, unknown_changes, clear_records = [], 0, 0, [], []
    for before, after in zip(old['frames'], new['frames']):
        assert before['frame'] == after['frame']
        for part in audit.PARTS:
            for family in audit.FAMILIES:
                a, b = before['parts'][part][family], after['parts'][part][family]
                unknowns += b['unknown_samples']
                baseline_unknowns += a['unknown_samples']
                if b['unknown_samples'] != a['unknown_samples']:
                    unknown_changes.append({'frame': after['frame'], 'part': part, 'family': family, 'baseline': a['unknown_samples'], 'candidate': b['unknown_samples']})
                if 40 <= after['frame'] <= 56:
                    clear_records.append(b)
                delta = b['maximum_closed_depth_mm'] - a['maximum_closed_depth_mm']
                if delta > TOLERANCE_MM:
                    regressions.append({'frame': after['frame'], 'part': part, 'family': family, 'before_mm': a['maximum_closed_depth_mm'], 'after_mm': b['maximum_closed_depth_mm'], 'increase_mm': delta})
    records = [v for row in new['frames'] for groups in row['parts'].values() for v in groups.values()]
    report.update({
        'source_sha256': new['source_sha256'], 'baseline_source_sha256': old['source_sha256'],
        'frames': new['frames'],
        'inside_samples': sum(v['inside_samples'] for v in records),
        'unknown_samples': unknowns,
        'baseline_unknown_samples': baseline_unknowns,
        'unknown_classification_changes': unknown_changes,
        'inherited_unknowns_unchanged': not unknown_changes,
        'maximum_closed_depth_mm': max(v['maximum_closed_depth_mm'] for v in records),
        'minimum_unsigned_gap_mm': min(v['minimum_unsigned_surface_distance_mm'] for v in records),
        'clear_window_inside_samples': sum(v['inside_samples'] for v in clear_records),
        'clear_window_unknown_samples': sum(v['unknown_samples'] for v in clear_records),
        'clear_window_minimum_unsigned_gap_mm': min(v['minimum_unsigned_surface_distance_mm'] for v in clear_records),
        'depth_regressions': regressions, 'complete': True,
    })
    report['acceptance_policy'] = 'Zero inside/unknown samples at 40–56. Across 40–60, no per-region depth increase above 0.01 mm and identical unknown classification counts to baseline. Inherited support unknowns remain explicitly unresolved.'
    report['passed'] = len(new['frames']) == 81 and not unknown_changes and not regressions and not report['clear_window_inside_samples'] and not report['clear_window_unknown_samples']
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('SAVED_RELEASE_SUBFRAMES_COMPLETE', json.dumps({k: v for k, v in report.items() if k not in ('frames', 'baseline', 'candidate', 'times')}), flush=True)
    if not report['passed']:
        raise RuntimeError('The saved release introduces sampled contact or increases baseline contact.')


if __name__ == '__main__':
    main()
