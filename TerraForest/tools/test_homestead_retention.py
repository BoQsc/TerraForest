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
        selected = candidates(self.root)
        self.assertEqual([first, third_pack, fourth_pack, fifth_pack, sixth_pack, seventh_pack, eighth_pack, ninth_pack, input_run], [folder for folder, _ in selected])
        self.assertEqual(("backpack.png", "player_settings.png"), selected[-1][1])

    def test_pins_are_not_ordinary_ready(self):
        pinned = self.preview(1); (pinned / ".retain").write_text("rejected witness")
        first = self.preview(2); self.preview(3); self.preview(4)
        self.assertEqual([first], [folder for folder, _ in candidates(self.root)])

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
