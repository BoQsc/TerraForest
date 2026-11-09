# SPDX-License-Identifier: 0BSD
import unittest
from analyze_frame_trace import summarize


class TraceAnalysisTests(unittest.TestCase):
    def row(self, frame, milliseconds=16):
        return {"frame": frame, "at_us": frame * 16667, "phase": "gameplay",
                "frame_ms": milliseconds, "pipeline_specialization": frame,
                "stages_ms": {"parent": 10, "child": 8}}

    def test_overlapping_windows_do_not_bias_tail(self):
        first, second = self.row(1), self.row(2, 60)
        result = summarize([{"schema": 1, "frames": [first, second]},
                            {"schema": 1, "frames": [second]}])
        self.assertEqual(result["unique_frames"], 2)
        self.assertEqual(result["phases"]["gameplay"]["frame_ms"]["mean"], 38)
        self.assertEqual(result["slowest_frames"][0]["pipeline_deltas"]["pipeline_specialization"], 1)

    def test_gap_does_not_invent_compilation_event(self):
        result = summarize([{"schema": 1, "frames": [self.row(1), self.row(7, 80)]}])
        self.assertIsNone(result["slowest_frames"][0]["pipeline_deltas"]["pipeline_specialization"])
        self.assertEqual(result["slowest_frames"][0]["stages_ms"], {"parent": 10, "child": 8})

    def test_conflicting_same_frame_rejected(self):
        with self.assertRaises(ValueError):
            summarize([{"schema": 1, "frames": [self.row(1), self.row(1, 80)]}])

    def test_delayed_device_markers_use_cpu_timestamps(self):
        first = self.row(1) | {'draw_ms': 4}
        reported = self.row(3) | {'draw_ms': 2, 'render_markers': {
            'available': True, 'device_frame': 999, 'begin_cpu_us': 13000, 'end_cpu_us': 15000,
            'largest_cpu_gaps': [{'after': 'scene', 'before': 'sky', 'begin_cpu_us': 13000, 'cpu_us': 2000}]}}
        result = summarize([{'schema': 1, 'frames': [first, reported]}])['render_markers']
        self.assertEqual(result['largest_cpu_gaps'][0]['frame'], 1)
        self.assertEqual(result['largest_cpu_gaps'][0]['reported_in_frame'], 3)
        self.assertEqual(result['largest_cpu_gaps'][0]['device_frame'], 999)

    def test_markers_outside_retained_draw_are_not_attributed(self):
        row = self.row(3) | {'draw_ms': 1, 'render_markers': {
            'available': True, 'device_frame': 3, 'begin_cpu_us': 100, 'end_cpu_us': 200,
            'largest_cpu_gaps': [{'after': 'a', 'before': 'b', 'begin_cpu_us': 100, 'cpu_us': 100}]}}
        result = summarize([{'schema': 1, 'frames': [row]}])['render_markers']
        self.assertEqual(result['largest_cpu_gaps'], [])
        self.assertEqual(result['unmatched_gaps'], 1)

    def test_native_samples_exclude_stale_and_unavailable_without_losing_zero(self):
        samples = [{'available': True, 'current': True, 'process_us': 0, 'started_us': 100, 'ended_us': 100},
                   {'available': True, 'current': True, 'process_us': 200, 'started_us': 200, 'ended_us': 400},
                   {'available': True, 'current': False, 'process_us': 9999},
                   {'available': False, 'current': False, 'process_us': 9999}]
        rows = [self.row(index) | {'native_world_process': {'blocks': sample}} for index, sample in enumerate(samples, 1)]
        rows.append(self.row(5))
        result = summarize([{'schema': 1, 'frames': rows}])['phases']['gameplay']['native_world_process']['blocks']
        self.assertEqual(result['current_samples'], 2)
        self.assertEqual(result['stale_samples'], 1)
        self.assertEqual(result['unavailable_samples'], 2)
        self.assertEqual(result['timings_us']['process_us']['mean'], 100)
        self.assertEqual(set(result['timings_us']), {'process_us'})


if __name__ == "__main__":
    unittest.main()
