# SPDX-License-Identifier: 0BSD
import json
import os
from pathlib import Path
import tempfile
import unittest
import cleanup_generation_copies as cleanup


class GenerationRetention(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.worlds = self.root / 'worlds'
        self.worlds.mkdir()
        self.stage = 'combined_stage_' + 'a' * 32
        self.source = self.worlds / (self.stage + '.trw')
        self.target = self.worlds / 'Played_world.trw'
        self.source.write_bytes(b'old generation')
        self.target.write_bytes(b'current player save')
        self.store = Path(str(self.source) + '.terrain')
        self.store.mkdir()
        (self.store / 'chunk.bin').write_bytes(b'generated terrain')
        folder = self.root / 'generation_reports' / ('a' * 32)
        folder.mkdir(parents=True)
        self.report = folder / 'run.json'
        self.record = dict(stage=self.stage, destination='Played_world', seed=1703, generator=29,
            publication=dict(ok=True, created=True, slot='Played_world'))
        self.report.write_text(json.dumps(self.record))
        self.row = cleanup.candidates(self.root)[0]
        self.row.update(source_sha256=cleanup.digest(self.source), destination_sha256=cleanup.digest(self.target))

    def test_only_stage_removed_destination_and_evidence_unchanged(self):
        self.assertGreater(cleanup.retire(self.worlds, self.row), 0)
        self.assertFalse(self.source.exists())
        self.assertFalse(self.store.exists())
        self.assertEqual(self.target.read_bytes(), b'current player save')
        self.assertTrue(self.report.exists())

    def test_changed_save_refuses_cleanup(self):
        self.target.write_bytes(b'changed since verification')
        with self.assertRaises(ValueError):
            cleanup.retire(self.worlds, self.row)
        self.assertTrue(self.source.exists())

    def test_live_world_lease_refuses_cleanup(self):
        with cleanup.lease(self.target):
            with self.assertRaises(OSError):
                cleanup.retire(self.worlds, self.row)
        self.assertTrue(self.source.exists())

    def test_failed_publication_not_candidate(self):
        self.record['publication']['ok'] = False
        self.report.write_text(json.dumps(self.record))
        self.assertEqual(cleanup.candidates(self.root), [])

    def test_missing_destination_not_candidate(self):
        self.target.unlink()
        self.assertEqual(cleanup.candidates(self.root), [])

    def test_pending_save_retained(self):
        Path(str(self.source) + '.tmp').touch()
        self.assertEqual(cleanup.candidates(self.root), [])
        with self.assertRaises(ValueError):
            cleanup.retire(self.worlds, self.row)

    def test_changed_receipt_refuses_cleanup(self):
        self.report.write_text('{}')
        with self.assertRaises(ValueError):
            cleanup.retire(self.worlds, self.row)

    def test_nonstage_name_refused(self):
        self.row['stage'] = 'Played_world'
        with self.assertRaises(ValueError):
            cleanup.retire(self.worlds, self.row)

    def test_linked_store_retained(self):
        external = self.root / 'outside'
        external.mkdir()
        try:
            os.symlink(external, self.store / 'linked', target_is_directory=True)
        except OSError:
            self.skipTest('Symlink creation unavailable')
        with self.assertRaises(ValueError):
            cleanup.retire(self.worlds, self.row)
        self.assertTrue(self.source.exists())


if __name__ == '__main__':
    unittest.main()
