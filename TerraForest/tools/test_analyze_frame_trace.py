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


if __name__ == "__main__":
    unittest.main()
