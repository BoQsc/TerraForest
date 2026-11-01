# SPDX-License-Identifier: 0BSD
import unittest

from profile_runtime import gameplay_gates, summarize


class GameplayGatesTests(unittest.TestCase):
    def fixture(self):
        phases = ("idle", "walking", "sprinting", "jumping", "mining_idle", "mining_after_run", "mining_after_jump", "recovery")
        gameplay = {"contacts": [{"changed": True, "contact_to_draw_ms": 50} for index in range(24)], "jumps": 4}
        frames = [{"phase": phase, "frame_ms": 16} for phase in phases for index in range(100)]
        return gameplay, frames

    def test_complete_workload_passes(self):
        self.assertTrue(all(gameplay_gates(*self.fixture()).values()))

    def test_first_contact_delay_cannot_hide_in_average(self):
        gameplay, frames = self.fixture()
        gameplay["contacts"][0]["contact_to_draw_ms"] = 220
        self.assertFalse(gameplay_gates(gameplay, frames)["contact_to_draw_max_150ms"])

    def test_missing_draw_is_not_success(self):
        gameplay, frames = self.fixture()
        del gameplay["contacts"][0]["contact_to_draw_ms"]
        self.assertFalse(gameplay_gates(gameplay, frames)["contact_to_draw_max_150ms"])

    def test_missing_movement_phase_fails(self):
        gameplay, frames = self.fixture()
        frames = [frame for frame in frames if frame["phase"] != "jumping"]
        self.assertFalse(gameplay_gates(gameplay, frames)["jumping_frame_p99_20ms_max_50ms"])

    def test_single_long_stall_fails(self):
        gameplay, frames = self.fixture()
        frames[0]["frame_ms"] = 80
        self.assertFalse(gameplay_gates(gameplay, frames)["idle_frame_p99_20ms_max_50ms"])

    def test_summary_retains_nonwalking_phases(self):
        frames = [{"phase": "jumping", "frame_ms": 16, "process_ms": 4, "gpu_ms": 5,
                   "render_cpu_ms": 2, "ecosystem_us": 50, "cover_us": 100, "stages": {}}]
        self.assertEqual(summarize(frames)["jumping"]["frame_ms"]["mean"], 16)


if __name__ == "__main__":
    unittest.main()
