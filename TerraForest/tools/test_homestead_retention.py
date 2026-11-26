# SPDX-License-Identifier: 0BSD
"""Check receipt ownership and pin boundaries without retiring real evidence."""
import json
import tempfile
import unittest
from pathlib import Path

from maintain_homestead_captures import candidates


class PreviewOwnership(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def preview(self, number, family="homestead_pack", **result):
        folder = self.root / "reports/checks" / f"{number:03}"
        folder.mkdir(parents=True)
        image = "homestead_01.png" if family == "homestead_pack" else "homestead_02.png"
        (folder / image).write_bytes(b"retained fixture")
        run = {"command": ["godot", "--script", f"res://tests/{family}.gd", "--check-evidence-dir=" + str(folder)],
               "result": {"exit_code": 0, **result}}
        (folder / "run.json").write_text(json.dumps(run), encoding="utf-8")
        return folder

    def test_two_ready_per_pack(self):
        first = self.preview(1)
        self.preview(2); self.preview(3)
        self.preview(4, "homestead_02_pack"); self.preview(5, "homestead_02_pack")
        self.assertEqual([first], [folder for folder, _ in candidates(self.root)])

    def test_pins_are_not_ordinary_ready(self):
        pinned = self.preview(1); (pinned / ".retain").write_text("rejected witness")
        first = self.preview(2); self.preview(3); self.preview(4)
        self.assertEqual([first], [folder for folder, _ in candidates(self.root)])

    def test_incomplete_and_unowned_captures_survive(self):
        self.preview(1, exit_code=None)
        unowned = self.preview(2)
        record = json.loads((unowned / "run.json").read_text())
        record["command"][-1] = "--check-evidence-dir=elsewhere"
        (unowned / "run.json").write_text(json.dumps(record))
        self.preview(3); self.preview(4)
        self.assertEqual([], candidates(self.root))


if __name__ == "__main__":
    unittest.main()
