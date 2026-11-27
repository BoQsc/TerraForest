# SPDX-License-Identifier: 0BSD
"""Check receipt ownership and pin boundaries without retiring real evidence."""
import json
import tempfile
import unittest
from pathlib import Path

from maintain_homestead_captures import FAMILIES, candidates


class PreviewOwnership(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def preview(self, number, family="homestead_pack", **result):
        folder = self.root / "reports/checks" / f"{number:03}"
        folder.mkdir(parents=True)
        for image in FAMILIES[family]:
            (folder / image).write_bytes(b"retained fixture")
        run = {"command": ["godot", "--temporary", "--script", f"res://tests/{family}.gd", "--check-evidence-dir=" + str(folder)],
               "result": {"exit_code": 0, **result}}
        (folder / "run.json").write_text(json.dumps(run), encoding="utf-8")
        return folder

    def test_two_ready_per_capture_family(self):
        first = self.preview(1)
        self.preview(2); self.preview(3)
        self.preview(4, "homestead_02_pack"); self.preview(5, "homestead_02_pack")
        third_pack = self.preview(6, "homestead_03_pack")
        self.preview(7, "homestead_03_pack"); self.preview(8, "homestead_03_pack")
        fourth_pack = self.preview(9, "homestead_04_pack")
        self.preview(10, "homestead_04_pack"); self.preview(11, "homestead_04_pack")
        input_run = self.preview(12, "drop_key_standard")
        self.preview(13, "drop_key_standard"); self.preview(14, "drop_key_standard")
        fifth_pack = self.preview(15, "homestead_05_pack")
        self.preview(16, "homestead_05_pack"); self.preview(17, "homestead_05_pack")
        sixth_pack = self.preview(18, "homestead_06_pack")
        self.preview(19, "homestead_06_pack"); self.preview(20, "homestead_06_pack")
        seventh_pack = self.preview(21, "homestead_07_pack")
        self.preview(22, "homestead_07_pack"); self.preview(23, "homestead_07_pack")
        eighth_pack = self.preview(24, "homestead_08_pack")
        self.preview(25, "homestead_08_pack"); self.preview(26, "homestead_08_pack")
        ninth_pack = self.preview(27, "homestead_09_pack")
        self.preview(28, "homestead_09_pack"); self.preview(29, "homestead_09_pack")
        tenth_pack = self.preview(30, "homestead_10_pack")
        self.preview(31, "homestead_10_pack"); self.preview(32, "homestead_10_pack")
        outdoor = self.preview(33, "outdoor_01_pack")
        self.preview(34, "outdoor_01_pack"); self.preview(35, "outdoor_01_pack")
        mansion = self.preview(36, "homestead_mansion")
        self.preview(37, "homestead_mansion"); self.preview(38, "homestead_mansion")
        object_world = self.preview(39, "object_system_world")
        self.preview(40, "object_system_world"); self.preview(41, "object_system_world")
        object_rendering = self.preview(42, "object_rendering_world")
        self.preview(43, "object_rendering_world"); self.preview(44, "object_rendering_world")
        model_horizon = self.preview(45, "model_horizon")
        self.preview(46, "model_horizon"); self.preview(47, "model_horizon")
        render_mesh = self.preview(48, "object_pack_render_mesh")
        self.preview(49, "object_pack_render_mesh"); self.preview(50, "object_pack_render_mesh")
        zombie_render = self.preview(51, "zombie_render_mesh")
        self.preview(52, "zombie_render_mesh"); self.preview(53, "zombie_render_mesh")
        house_world = self.preview(54, "house_population_world")
        self.preview(55, "house_population_world"); self.preview(56, "house_population_world")
        house_layout = self.preview(57, "house_furnishings")
        self.preview(58, "house_furnishings"); self.preview(59, "house_furnishings")
        selected = candidates(self.root)
        self.assertEqual([first, third_pack, fourth_pack, fifth_pack, sixth_pack, seventh_pack, eighth_pack, ninth_pack, tenth_pack, outdoor, mansion, house_world, house_layout, object_world, object_rendering, model_horizon, render_mesh, zombie_render, input_run], [folder for folder, _ in selected])
        self.assertEqual(("backpack.png", "player_settings.png"), selected[-1][1])

    def test_browser_image_and_timings_retire_together_after_two_ready(self):
        first = self.preview(1, "world_browser_responsiveness")
        self.preview(2, "world_browser_responsiveness")
        self.assertEqual([], candidates(self.root))
        self.preview(3, "world_browser_responsiveness")
        self.assertEqual([(first, ("first_ui.png", "first_ui.json"))], candidates(self.root))

    def test_requested_player_world_is_outside_capture_retirement(self):
        first = self.preview(1, "homestead_generated_world")
        self.preview(2, "homestead_generated_world"); self.preview(3, "homestead_generated_world")
        receipt = first / "created_world.json"
        receipt.write_text(json.dumps({"slot": "Homestead_Valley", "user_requested_playable_world": True}))
        selected = candidates(self.root)
        self.assertEqual([first], [folder for folder, _ in selected])
        self.assertNotIn("created_world.json", selected[0][1])
        self.assertNotIn("Homestead_Valley.trw", selected[0][1])
        self.assertTrue(receipt.is_file())

    def test_full_launch_uses_its_own_two_ready_capture_family(self):
        first = self.preview(1, "full_launch")
        self.preview(2, "full_launch"); self.preview(3, "full_launch")
        self.preview(4, "world_browser_responsiveness")
        self.assertEqual([(first, ("first_ui.png", "first_ui.json"))], candidates(self.root))

    def test_pins_are_not_ordinary_ready(self):
        pinned = self.preview(1); (pinned / ".retain").write_text("rejected witness")
        first = self.preview(2); self.preview(3); self.preview(4)
        self.assertEqual([first], [folder for folder, _ in candidates(self.root)])

    def test_loading_captures_keep_latest_two_without_retiring_source_worlds(self):
        folders = []
        for number, label in enumerate(("before", "after", "after", "before", "after", "after")):
            folder = self.root / "reports/startup_optimization" / f"loading_{label}_{number:03}"
            folder.mkdir(parents=True);folders.append(folder)
            for name in ("ready.png", "result.json", "source.trw"):(folder / name).write_bytes(b"fixture")
            command = ["godot", "--script", "res://tests/startup_benchmark.gd", "--benchmark-profile", "--benchmark-output=" + str(folder)]
            if number == 3:command[-1] = "--benchmark-output=elsewhere"
            if number == 4:command.append("--benchmark-normal-load")
            if number == 5:(folder / ".retain").touch()
            (folder / "run.json").write_text(json.dumps({"command": command, "result": {"exit_code": 0}}))
        self.assertEqual([(folders[0], ("ready.png", "result.json"))], candidates(self.root))
        self.assertTrue(all((folder / "source.trw").exists() for folder in folders))

    def test_incomplete_and_unowned_captures_survive(self):
        manual = self.preview(0)
        record = json.loads((manual / "run.json").read_text())
        record["command"].remove("--temporary")
        (manual / "run.json").write_text(json.dumps(record))
        self.preview(1, exit_code=None)
        unowned = self.preview(2)
        record = json.loads((unowned / "run.json").read_text())
        record["command"][-1] = "--check-evidence-dir=elsewhere"
        (unowned / "run.json").write_text(json.dumps(record))
        self.preview(3); self.preview(4)
        self.assertEqual([], candidates(self.root))


if __name__ == "__main__":
    unittest.main()
