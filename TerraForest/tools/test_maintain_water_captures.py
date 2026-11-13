# SPDX-License-Identifier: 0BSD
import json
from pathlib import Path
import tempfile
import unittest

from maintain_water_captures import candidates


class WaterCaptureOwnershipTests(unittest.TestCase):
    def test_only_completed_declared_unpinned_runs_and_keep_two(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folders = []
            for i in range(8):
                folder = root / 'reports/checks' / str(i)
                folder.mkdir(parents=True)
                folders.append(folder)
                command = ['godot', '--script', 'res://tests/water_barrel_world.gd',
                           '--check-evidence-dir=' + str(folder)]
                if i == 1:
                    command[-1] += '_different'
                if i == 2:
                    command[2] = 'res://tests/another.gd'
                result = {'exit_code': None if i == 3 else 1}
                (folder / 'run.json').write_text(json.dumps(dict(command=command, result=result)))
                (folder / 'barrel_after.png').write_bytes(b'evidence')
            (folders[4] / '.retain').touch()
            self.assertEqual(candidates(root), [folders[0], folders[5]])
            self.assertEqual(candidates(root, 1), [folders[0], folders[5], folders[6]])
            with self.assertRaises(ValueError):
                candidates(root, 0)
            # An archive receipt makes a run ineligible for repeat retirement.
            (folders[0] / 'captures.archive.json').write_text('{}')
            self.assertEqual(candidates(root), [folders[5]])
            # New reverse views get a separate receipt; the original archive
            # remains authoritative for the already-retired first-angle files.
            (folders[0] / 'player_shore_after_reverse.png').write_bytes(b'reverse')
            self.assertEqual(candidates(root), [folders[0], folders[5]])
            (folders[0] / 'captures.supplement.archive.json').write_text('{}')
            self.assertEqual(candidates(root), [folders[5]])


if __name__ == '__main__':
    unittest.main()
