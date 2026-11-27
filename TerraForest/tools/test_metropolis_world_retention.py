# SPDX-License-Identifier: 0BSD
"""Small filesystem fixtures for the metropolis launcher's retirement boundary."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_metropolis_world as target


class FixtureRetention(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'repo'
        self.folder = self.root / 'reports/metropolis_world/trial'
        self.folder.mkdir(parents=True)
        self.appdata = self.base / 'appdata'
        self.userdata = self.appdata / 'Godot/app_userdata/TerraForest'
        self.worlds = self.userdata / 'worlds'
        self.worlds.mkdir(parents=True)
        self.stage = 'combined_stage_' + 'a' * 32
        self.slot = 'Metropolis_1703_abcdef12'
        self.status = self.userdata / 'world_preparation_42_123.json'
        self.generation = self.userdata / 'generation_reports' / ('a' * 32)
        self.generation.mkdir(parents=True)
        self.payload = self.worlds / (self.stage + '.trw.water') / 'chunk.bin'
        self.payload.parent.mkdir()
        self.payload.write_bytes(b'failed native staging evidence')
        self.protected = self.worlds / 'Player_home.trw'
        self.protected.write_bytes(b'player save must survive')
        self.record = {'purpose': 'normal metropolis generation and fresh restore', 'passed': False,
                       'phases': [{'phase': 'create', 'command': ['engine', '--script',
                                   'res://tests/production_buildings.gd', '--', '--metropolis',
                                   '--metropolis-evidence=' + self.folder.as_posix()],
                                   'result': {'pid': 42, 'exit_code': 1}}]}
        (self.generation / 'run.json').write_text(json.dumps({'destination': self.slot, 'stage': self.stage}))
        self.status.write_text(json.dumps({'slot': self.slot, 'coordinator_pid': 42,
                                          'staging_slot': self.stage, 'report': str(self.generation)}))
        (self.folder / 'request.json').write_text(json.dumps({'slot': self.slot, 'pid': 42,
                                               'status': 'user://' + self.status.name}))
        (self.folder / 'run.json').write_text(json.dumps(self.record))
        self.addCleanup(patch.stopall)
        patch.object(target, 'ROOT', self.root).start()
        patch.object(target, 'no_game_processes', lambda: None).start()
        patch.object(target.storage, 'admit', lambda *a, **k: {}).start()
        patch.dict(os.environ, {'APPDATA': str(self.appdata)}).start()

    def test_failed_stage_is_archived_and_player_save_is_untouched(self):
        result = target.retire_fixture(self.folder, self.record)
        self.assertFalse(result['pending'])
        self.assertFalse(self.payload.exists())
        self.assertTrue(Path(result['manifest']).is_file())
        self.assertEqual(self.protected.read_bytes(), b'player save must survive')

    def test_process_mismatch_retains_every_byte(self):
        self.record['phases'][0]['result']['pid'] = 43
        with self.assertRaises(ValueError):
            target.retire_fixture(self.folder, self.record)
        self.assertTrue(self.payload.exists())

    def test_repeat_retirement_preserves_original_archive(self):
        first = target.retire_fixture(self.folder, self.record)
        manifest = Path(first['manifest'])
        original = manifest.read_bytes()
        second = target.retire_fixture(self.folder, self.record)
        self.assertEqual(second['retired_bytes'], 0)
        self.assertEqual(manifest.read_bytes(), original)
        self.assertEqual(self.protected.read_bytes(), b'player save must survive')

    def test_completed_recheck_owns_its_later_changes(self):
        self.record['passed'] = True
        (self.folder / 'recheck.json').write_text(json.dumps(self.record))
        result = target.retire_fixture(self.folder, self.record, 'recheck.json')
        self.assertFalse(result['pending'])
        self.assertFalse(self.payload.exists())
        self.assertEqual(self.protected.read_bytes(), b'player save must survive')

    def test_unrecognized_driver_retains_every_byte(self):
        self.record['phases'][0]['command'] = ['another tool']
        with self.assertRaises(ValueError):
            target.retire_fixture(self.folder, self.record)
        self.assertTrue(self.payload.exists())

    def test_changed_world_retains_every_byte(self):
        stamp = (self.folder / 'run.json').stat().st_mtime + 10
        os.utime(self.payload, (stamp, stamp))
        with self.assertRaises(ValueError):
            target.retire_fixture(self.folder, self.record)
        self.assertTrue(self.payload.exists())


if __name__ == '__main__':
    unittest.main()
