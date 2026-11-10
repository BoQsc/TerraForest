# SPDX-License-Identifier: 0BSD
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from maintain_performance_traces import candidates, maintain_traces
from retained_artifacts import Store, restore


class TraceRetentionTests(unittest.TestCase):
    def fixture(self, root, name, completed=True):
        folder = root/'reports/performance_changes'/name
        (folder/'traces').mkdir(parents=True)
        (folder/'traces/trace_1.json').write_text('{"evidence":123}')
        (folder/'observation.json').write_text('{"must_stay":true}')
        (folder/'run.json').write_text(json.dumps({'command': ['res://tests/frame_trace_world.gd',
            '--frame-trace-dir='+str(folder/'traces'), '--trace-world-slot='+name],
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


if __name__ == '__main__':
    unittest.main()
