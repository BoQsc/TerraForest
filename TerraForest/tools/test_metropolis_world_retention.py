# SPDX-License-Identifier: 0BSD
"""Small filesystem fixtures for the metropolis launcher's retirement boundary."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_metropolis_world as target
import recheck_metropolis_world as recheck


class RecheckAdmission(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        (self.folder / 'create').mkdir()
        self.original = {'purpose': target.REPORT_FAMILIES['inhabited_island_world'],
                         'phases': [{'phase': 'create', 'result': {'passed': True}}]}

    def test_island_creation_is_accepted_but_other_family_is_rejected(self):
        self.assertTrue(recheck.validated_creation(self.folder, self.original, 'inhabited_island_world')['result']['passed'])
        with self.assertRaises(ValueError):
            recheck.validated_creation(self.folder, self.original, 'metropolis_world')

    def test_protected_human_save_and_review_pin_are_rejected(self):
        self.original['human_playtest_owned'] = True
        with self.assertRaises(ValueError):
            recheck.validated_creation(self.folder, self.original, 'inhabited_island_world')
        self.original['human_playtest_owned'] = False
        (self.folder / '.retain').write_text('Human review')
        with self.assertRaises(ValueError):
            recheck.validated_creation(self.folder, self.original, 'inhabited_island_world')

    def test_diagnostic_exception_requires_exact_completed_cleanup_evidence(self):
        result = {'passed': False, 'exit_code': 0, 'timed_out': False,
                  'diagnostics': ['WARNING: 1 ObjectDB instance was leaked at exit (run with --verbose for details).']}
        self.original['phases'][0]['result'] = result
        log = self.folder / 'create/console.log'
        log.write_text('PRODUCTION_BUILDINGS checks=7 failures=0 slot=Island_1703_abcdef12\n'
                       'Leaked instance: RefCounted:42 - Reference count: 0\n')
        with self.assertRaises(ValueError):
            recheck.validated_creation(self.folder, self.original, 'inhabited_island_world')
        admitted = recheck.validated_creation(self.folder, self.original, 'inhabited_island_world', True)
        self.assertTrue(admitted['cleanup_warning_only'])
        self.assertFalse(admitted['result']['passed'])
        self.assertNotIn('cleanup_warning_only', self.original['phases'][0])
        log.write_text('PRODUCTION_BUILDINGS checks=7 failures=1 slot=Island_1703_abcdef12\n')
        with self.assertRaises(ValueError):
            recheck.validated_creation(self.folder, self.original, 'inhabited_island_world', True)


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

    def test_human_playtest_is_never_automatically_retired(self):
        self.record['human_playtest_owned'] = True
        self.record['functional_passed'] = True
        result = target.retire_fixture(self.folder, self.record)
        self.assertTrue(result['protected'])
        self.assertFalse(result['pending'])
        self.assertTrue(self.payload.exists())
        self.assertFalse((self.folder / 'world.archive.json').exists())
        self.assertEqual(self.protected.read_bytes(), b'player save must survive')



class ExitWarningScope(unittest.TestCase):
    def test_diagnostic_continuation_cannot_accept_real_failures(self):
        with tempfile.TemporaryDirectory() as temporary:
            phase = Path(temporary)
            complete = ('PRODUCTION_BUILDINGS checks=30 failures=0 slot=Metropolis_test\n'
                        'Leaked instance: RefCounted:123 - Reference count: 0\n')
            log = phase / 'console.log'
            log.write_text(complete)
            result = {'exit_code': 0, 'timed_out': False, 'diagnostics': [
                'WARNING: 1 ObjectDB instance was leaked at exit (run with --verbose for details).']}
            self.assertTrue(target.zero_reference_exit_only(result, phase))
            for changes in ({'exit_code': 1}, {'timed_out': True},
                            {'diagnostics': result['diagnostics'] + ['FAIL water']},
                            {'diagnostics': ['ERROR: Water failed']}):
                with self.subTest(changes=changes):
                    self.assertFalse(target.zero_reference_exit_only(dict(result, **changes), phase))
            for rejected in (complete.replace('count: 0', 'count: 1'),
                             complete.replace('failures=0', 'failures=1'),
                             complete.replace('checks=30', 'checks=0')):
                log.write_text(rejected)
                self.assertFalse(target.zero_reference_exit_only(result, phase))


if __name__ == '__main__':
    unittest.main()
