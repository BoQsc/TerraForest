# SPDX-License-Identifier: 0BSD
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import prepare_combined_world as prep


class PreparationTests(unittest.TestCase):
    def test_seed_validation_and_forwarding(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for seed in (-1, 2147483648, True, 1.5):
                with self.assertRaises(ValueError): prep.prepare('unused', root, root/'report', seed=seed)
            self.assertEqual(list(root.iterdir()), [])
            with patch.object(prep, 'execute', return_value={'passed': True}) as run, patch.object(prep, 'clone_once', return_value={'created': True}):
                self.assertEqual(prep.prepare('unused', root, root/'report', 'seed42', 'districts', 42), 0)
                self.assertEqual(run.call_count, 2)
                for call in run.call_args_list:
                    self.assertIn('--world-seed=42', call.args[0])
                    self.assertIn('--world-generator=12', call.args[0])

    def test_invalid_layout_rejected_before_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(ValueError):prep.prepare('unused', root, root/'report', layout='unknown')
            self.assertEqual(list(root.iterdir()), [])

    def test_mixed_layout_is_used_in_both_processes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.object(prep, 'execute', return_value={'passed': True}) as run, patch.object(prep, 'clone_once', return_value={'created': True}):
                self.assertEqual(prep.prepare('unused', root, root/'report', 'mixed_review', 'mixed'), 0)
                for call in run.call_args_list:
                    self.assertIn('--checkpoint-layout=mixed', call.args[0])

    def test_invalid_destination_rejected_before_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ('../world', '', 'x'*49, 'é'):
                with self.assertRaises(ValueError):prep.prepare('unused', root, root/'report', name)
            self.assertEqual(list(root.iterdir()), [])

    def test_custom_destination_is_exclusive(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            save = root/'review.trw'
            save.write_bytes(b'review progress')
            with patch.object(prep, 'execute') as run:
                self.assertEqual(prep.prepare('unused', root, root/'report', 'review'), 0)
                run.assert_not_called()
            self.assertEqual(save.read_bytes(), b'review progress')

    def test_existing_progress_never_runs_generation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            save = root / 'combined_gameplay.trw'
            save.write_bytes(b'existing progress')
            with patch.object(prep, 'execute') as run:
                self.assertEqual(prep.prepare('unused', root, root / 'report'), 0)
                run.assert_not_called()
            self.assertEqual(save.read_bytes(), b'existing progress')

    def test_reopen_failure_cannot_publish(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.object(prep, 'execute', side_effect=[{'passed': True}, {'passed': False}]), patch.object(prep, 'clone_once') as publish:
                self.assertEqual(prep.prepare('unused', root, root / 'report'), 1)
                publish.assert_not_called()
            self.assertFalse((root / 'combined_gameplay.prepare.lock').exists())

    def test_verified_stage_publishes_once(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.object(prep, 'execute', return_value={'passed': True}) as run, patch.object(prep, 'clone_once', return_value={'created': True}) as publish:
                self.assertEqual(prep.prepare('unused', root, root / 'report'), 0)
                self.assertEqual(run.call_count, 2)
                self.assertIn('--reopen-checkpoint', run.call_args_list[1].args[0])
                publish.assert_called_once()

    def test_concurrent_preparation_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lock = root / 'combined_gameplay.prepare.lock'
            lock.write_text('other preparation')
            with patch.object(prep, 'execute') as run:
                with self.assertRaises(FileExistsError):prep.prepare('unused', root, root / 'report')
                run.assert_not_called()
            self.assertEqual(lock.read_text(), 'other preparation')


if __name__ == '__main__':unittest.main()
