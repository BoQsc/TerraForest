# SPDX-License-Identifier: 0BSD
import json
import tempfile
import unittest
from pathlib import Path
from analyze_combat_probe import analyze


class CombatEvidenceTest(unittest.TestCase):
    def test_focus_phase_and_completed_event_frame(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'traces').mkdir()
            records = {
                'run.json': {'command': ['godot', '--profiling']},
                'combat_probe.json': {'events': [{'action': 'sever', 'at_us': 100, 'us': 20}]},
                'observation.json': {'samples': [
                    {'phase': 'combat_sever', 'frame_ms': 8, 'window_focused': True},
                    {'phase': 'combat_sever', 'frame_ms': 12, 'window_focused': True},
                    {'phase': 'combat_sever', 'frame_ms': 300, 'window_focused': False},
                    {'phase': 'test_screenshot', 'frame_ms': 900, 'window_focused': True}]},
                'traces/trace_01.json': {'frames': [
                    {'frame': 1, 'at_us': 110, 'frame_ms': 10},
                    {'frame': 2, 'at_us': 130, 'frame_ms': 20}]}}
            for name, data in records.items():
                (root/name).write_text(json.dumps(data))
            result = analyze(root)
            self.assertEqual(result['events'][0]['completed_frame']['frame'], 2)
            self.assertEqual(result['phases']['combat_sever']['frames'], 2)
            self.assertEqual(result['phases']['combat_sever']['mean_ms'], 10)
            self.assertTrue(result['engine_profiler'])
            self.assertFalse(result['gameplay_fps_acceptance'])
            (root/'traces/trace_01.json').unlink()
            self.assertIsNone(analyze(root)['events'][0]['completed_frame'])


if __name__ == '__main__':
    unittest.main()
