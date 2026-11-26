# SPDX-License-Identifier: 0BSD
import json
from pathlib import Path
import tempfile
import unittest

from maintain_physics_captures import candidates
from analyze_physics_residency import read_capture, summarize, workload_differences
from run_godot_check import planned_report_bytes


class PhysicsCaptureTests(unittest.TestCase):
    def test_only_audited_drivers_receive_bounded_output_allowance(self):
        self.assertEqual(planned_report_bytes(['godot', '--script', 'res://tests/physics_residency_world.gd']), 16 * 2**20)
        self.assertEqual(planned_report_bytes(['godot', '--headless', '--script', 'res://tests/zombie_residency_lifecycle.gd']), 2 * 2**20)
        self.assertEqual(planned_report_bytes(['godot', '--headless', '--script', 'res://tests/zombie_collision_cloud.gd']), 2 * 2**20)
        self.assertEqual(planned_report_bytes(['godot', '--script', 'res://tests/zombie_ragdoll_reactivation.gd']), 256 * 2**20)

    def test_retention_requires_completed_owned_output_and_preserves_two_and_pins(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folders = []
            for number in range(8):
                folder = root / 'reports/checks' / str(number)
                folder.mkdir(parents=True)
                folders.append(folder)
                command = ['godot', '--script', 'res://tests/physics_residency_world.gd',
                           '--check-evidence-dir=' + str(folder)]
                if number == 1: command[-1] += '_unowned'
                if number == 2: command[2] = 'res://tests/another.gd'
                run = dict(command=command, result={'exit_code': None if number == 3 else 1})
                (folder / 'run.json').write_text(json.dumps(run))
                (folder / 'physics_residency.json').write_text('{}')
            (folders[4] / '.retain').touch()
            self.assertEqual(candidates(root), [folders[0], folders[5]])
            (folders[0] / 'physics_residency.json').unlink()
            self.assertEqual(candidates(root), [folders[5]])

    def test_cadence_counts_hitches_and_distinguishes_work_from_admission_latency(self):
        data = dict(source='fixture', source_sha256='hash', seed=1703, scope='test', route=[],
                    samples=[dict(phase='idle', frame_ms=ms, physics_tail_ms=2, corpse_us={'freeze_us':100})
                             for ms in (16, 20, 40, 60)],
                    ragdoll_transitions=[dict(phase='idle', begin_us=1000, end_us=101000,
                                             total_us=10000, max_slice_us=3000,
                                             shapes={'Head':dict(input_points=5408, points=1844,
                                                                 cloud_us=50, install_us=2000, plan_built=False)})])
        result = summarize(data)
        self.assertEqual(result['cadence']['over_33_ms'], 2)
        self.assertEqual(result['cadence']['over_50_ms'], 1)
        self.assertEqual(result['ragdolls']['admission_span_ms']['maximum'], 100)
        self.assertEqual(result['ragdolls']['total_ms']['maximum'], 10)
        head = result['collision_shapes']['bodies']['Head']
        self.assertEqual(head['input_points']['mean'], 5408)
        self.assertEqual(head['points']['mean'], 1844)
        self.assertEqual(head['cloud_ms']['mean'], .05)
        self.assertEqual(head['install_ms']['mean'], 2)
        self.assertEqual(head['plan_builds'], 0)
        data['render_ablation'] = [dict(phase='0:baseline', draw_us=99000, setup_ms=1,
            render_cpu_ms=80, gpu_ms=4, draw_calls=1000)]
        data['samples'][0]['render_markers'] = {'available': True}
        diagnostic = summarize(data)
        self.assertTrue(diagnostic['diagnostics'])
        self.assertEqual(diagnostic['cadence']['frames'], 4)
        self.assertEqual(diagnostic['cadence']['frame_ms']['maximum'], 60)
        self.assertEqual(diagnostic['render_ablation']['0:baseline']['draw_us']['mean'], 99000)
        data['collision_comparison'] = [dict(part='head', input_points=5408, pairs=[
            dict(original=dict(total_us=original), reduced=dict(total_us=reduced, points=2000))
            for original, reduced in [(1000, 600), (1100, 650), (30000, 30000)]])]
        paired = summarize(data)['paired_collision']['parts']['all']
        self.assertEqual(paired['original_total_ms'], 1.1)
        self.assertEqual(paired['reduced_total_ms'], .65)
        self.assertEqual(paired['retained_points'], 2000)

    def test_population_or_settings_drift_cannot_pass_workload_comparison(self):
        first = dict(source_sha256='same', seed=1703, route=[dict(living=5, corpses=10)], physics_hz=60)
        self.assertEqual(workload_differences(first, first.copy()), [])
        self.assertEqual(workload_differences(first, dict(first, route=[dict(living=4, corpses=11)])), ['route'])
        self.assertEqual(workload_differences(first, dict(first, physics_hz=30)), ['physics_hz'])
        self.assertEqual(workload_differences(first, dict(first, source_sha256='changed')), ['source_sha256'])
        first['diagnostics'] = False
        self.assertEqual(workload_differences(first, dict(first, diagnostics=True)), ['diagnostics'])
        first['manual_no_present'] = False
        first['detached_present'] = False
        self.assertEqual(workload_differences(first, dict(first, manual_no_present=True)), ['manual_no_present'])
        self.assertEqual(workload_differences(first, dict(first, detached_present=True)), ['detached_present'])
        for key, value, changed in [('presentation_surface', 'interactive_desktop', 'isolated_desktop'),
                                    ('window_mode', 3, 0), ('window_focus', 'focused', 'mixed')]:
            first[key] = value
            self.assertEqual(workload_differences(first, dict(first, **{key: changed})), [key])

    def test_presentation_provenance_comes_from_actual_launcher_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / 'physics_residency.json').write_text('{}')
            (folder / 'run.json').write_text(json.dumps(dict(command=['godot', '--windowed', '--isolated-render'])))
            data = read_capture(folder)
            self.assertEqual((data['presentation_surface'], data['window_mode']), ('isolated_desktop', 0))
            (folder / 'run.json').write_text(json.dumps(dict(command=['godot', '--fullscreen'])))
            data = read_capture(folder)
            self.assertEqual((data['presentation_surface'], data['window_mode']), ('interactive_desktop', 3))
            (folder / 'physics_residency.json').write_text('{"window_mode":0}')
            self.assertEqual(read_capture(folder)['window_mode'], 0)
            (folder / 'run.json').write_text('{}')
            self.assertEqual(read_capture(folder)['presentation_surface'], 'unknown')


if __name__ == '__main__':
    unittest.main()
