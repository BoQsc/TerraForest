# SPDX-License-Identifier: 0BSD
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from maintain_performance_traces import candidates, maintain_traces, maintain_observations
from retained_artifacts import Store, restore


class TraceRetentionTests(unittest.TestCase):
    def fixture(self, root, name, completed=True):
        folder = root/'reports/performance_changes'/name
        (folder/'traces').mkdir(parents=True)
        (folder/'traces/trace_1.json').write_text('{"evidence":123}')
        (folder/'observation.json').write_text(json.dumps({'slot':name, 'must_stay':True}))
        (folder/'run.json').write_text(json.dumps({'command': ['res://tests/frame_trace_world.gd',
            '--frame-trace-dir='+str(folder/'traces'), '--trace-world-slot='+name, '--trace-world-output='+folder.as_posix()],
            'result': {'exit_code': 1 if completed else None}}))
        (folder/'completion.json').write_text(json.dumps({'slot': name, 'ok': False}))
        return folder

    def test_completed_failures_retained_and_pins_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            old = self.fixture(root, '01')
            pinned = self.fixture(root, '02');(pinned/'.retain').write_text('baseline')
            self.fixture(root, '03');self.fixture(root, '04')
            self.fixture(root, '05', completed=False)
            self.assertEqual(candidates(root), [old])
            with patch('maintain_performance_traces.admit'), patch('maintain_performance_traces.no_game_processes'):
                result = maintain_traces(root, apply=True)
            self.assertEqual(len(result['completed']), 1)
            self.assertFalse((old/'traces/trace_1.json').exists())
            self.assertTrue((old/'observation.json').exists())
            destination = root/'inspection'
            restore(old/'traces.archive.json', Store(root/'reports/retained_artifacts/chunks'), destination)
            self.assertEqual((destination/'traces/trace_1.json').read_text(), '{"evidence":123}')

    def test_mismatched_completion_does_not_authorize_archival(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            old = self.fixture(root, '01')
            (old/'completion.json').write_text('{"slot":"another_world"}')
            self.fixture(root, '02');self.fixture(root, '03')
            self.assertEqual(candidates(root), [])

    def test_cadence_retention_preserves_pins_active_and_mismatched_runs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            old = self.fixture(root, '01')
            (old/'completion.json').unlink()  # Older drivers completed in observation.json.
            (old/'arrival.png').write_bytes(b'referenced picture')
            (old/'destruction_before.png').write_bytes(b'owned picture')
            pinned = self.fixture(root, '02'); (pinned/'.retain').write_text('baseline')
            mismatch = self.fixture(root, '03')
            (mismatch/'completion.json').write_text('{"slot":"different"}')
            self.fixture(root, '04'); self.fixture(root, '05')
            active = self.fixture(root, '06', completed=False)
            references = {'project/reports/performance_changes/01/arrival.png'}
            with patch('maintain_performance_traces.admit'), patch('maintain_performance_traces.no_game_processes'), patch('retire_backed_outputs.referenced_media', return_value=references):
                result = maintain_observations(root, apply=True)
            self.assertEqual(result['completed'], [str(old/'observation.archive.json')])
            self.assertFalse((old/'observation.json').exists())
            self.assertTrue((old/'arrival.png').exists())
            self.assertFalse((old/'destruction_before.png').exists())
            for folder in (pinned, mismatch, active, root/'reports/performance_changes/04', root/'reports/performance_changes/05'):
                self.assertTrue((folder/'observation.json').exists())
            restore(old/'observation.archive.json', Store(root/'reports/retained_artifacts/chunks'), root/'inspection')
            self.assertEqual(json.loads((root/'inspection/observation.json').read_text()), {'slot':'01','must_stay':True})
            self.assertEqual((root/'inspection/destruction_before.png').read_bytes(), b'owned picture')


if __name__ == '__main__':
    unittest.main()
