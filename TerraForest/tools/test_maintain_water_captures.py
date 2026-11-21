# SPDX-License-Identifier: 0BSD
import json
from pathlib import Path
import tempfile
import unittest

from maintain_water_captures import candidates
from retained_artifacts import digest


class WaterCaptureOwnershipTests(unittest.TestCase):
    def test_legacy_release_requires_both_packaged_driver_and_overlay_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folders = []
            for number in range(5):
                folder = root / 'reports/checks' / str(number)
                folder.mkdir(parents=True)
                folders.append(folder)
                overlay = folder / 'terrain_contact.zip'
                overlay.write_bytes(b'original terrain overlay')
                driver = folder / 'water_player_world.gd'
                driver.write_bytes(b'packaged gameplay driver')
                command = ['game', '--main-pack', 'game.pck', '--script', str(driver),
                           '--check-evidence-dir=' + str(folder)]
                run = dict(command=command, result={'exit_code': 1}, pack_sha256='f' * 64,
                           patch_sha256=digest(overlay), test_sha256=digest(driver))
                (folder / 'run.json').write_text(json.dumps(run))
                (folder / 'player_shore_before.png').write_bytes(b'capture')
            (folders[1] / 'terrain_contact.zip').write_bytes(b'changed overlay')
            (folders[2] / 'water_player_world.gd').write_bytes(b'different driver')
            self.assertEqual(candidates(root, 1), [folders[0], folders[3]])

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
