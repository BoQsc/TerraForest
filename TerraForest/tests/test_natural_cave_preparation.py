# SPDX-License-Identifier: 0BSD
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import prepare_natural_cave as prep


class CavePreparationTests(unittest.TestCase):
    def test_existing_progress_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            save = root / 'natural_cave_gameplay.trw'
            save.write_bytes(b'player progress')
            with patch.object(prep, 'execute') as run, patch.object(prep, 'clone_once') as publish:
                self.assertEqual(prep.prepare('unused', root, root / 'report'), 0)
                run.assert_not_called()
                publish.assert_not_called()
            self.assertEqual(save.read_bytes(), b'player progress')

    def test_failed_reopen_cannot_publish(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.object(prep, 'execute', side_effect=[{'passed': True}, {'passed': False}]), patch.object(prep, 'clone_once') as publish:
                self.assertEqual(prep.prepare('unused', root, root / 'report'), 1)
                publish.assert_not_called()
            self.assertFalse((root / 'natural_cave_gameplay.prepare.lock').exists())

    def test_existing_lock_is_not_removed_or_bypassed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lock = root / 'natural_cave_gameplay.prepare.lock'
            lock.write_text('another preparation')
            with patch.object(prep, 'execute') as run:
                with self.assertRaises(FileExistsError):prep.prepare('unused', root, root / 'report')
                run.assert_not_called()
            self.assertEqual(lock.read_text(), 'another preparation')


if __name__ == '__main__':unittest.main()
