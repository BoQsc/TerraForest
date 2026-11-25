# SPDX-License-Identifier: 0BSD
import unittest

from analyze_human_capture import summarize


class HumanCadenceTests(unittest.TestCase):
    def test_focus_edges_and_rotating_trace_gaps_do_not_bias_percentiles(self):
        rows = [dict(phase='human_gameplay', window_focused=True, frame=i, at_us=i*100000,
                     frame_ms=16, gpu_ms=5) for i in range(7)]
        rows[2]['window_focused'] = False
        rows[2]['frame_ms'] = 500
        rows[3]['frame_ms'] = 300  # Interval begins outside focus; also excluded.
        rows[4]['frame_ms'] = 100  # Genuine hitch, absent from rotating traces.
        trace = {'frames': [dict(rows[5], stages_ms={})], 'trigger':'automatic', 'trigger_us':500000}
        result = summarize({'slot':'test', 'samples':rows}, [trace, trace])
        self.assertEqual(result['focused_gameplay_frames'], 4)
        self.assertEqual(result['frame_ms']['maximum'], 100)
        self.assertEqual(result['detailed_coverage_frames'], 1)
        self.assertFalse(result['worst_frames'][0]['detailed_trace_retained'])


if __name__ == '__main__':
    unittest.main()
