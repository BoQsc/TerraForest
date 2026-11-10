# SPDX-License-Identifier: 0BSD
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from development_storage import admit, usage, LIMITS


class DevelopmentStorageTests(unittest.TestCase):
    def test_separate_budgets_and_planned_growth(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            for name,size in [('reports/capture/trace',10),('reports/retained_artifacts/chunks/hash',20),
                              ('.build/native/current',30),('.build/old/pack',40),('.godot/cache',50),
                              ('dist/TerraForest.pck',100),('assets/source',100)]:
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'x'*size)
            self.assertEqual(usage(root),dict(reports=10,archive=20,compiler_cache=30,scratch=40,import_cache=50))
            limits=dict(LIMITS,reports=12,scratch=42)
            with patch('development_storage.require_free_space'):
                admit(root,report_bytes=2,scratch_bytes=2,limits=limits)
                before=set(root.rglob('*'))
                with self.assertRaisesRegex(OSError,'Development output budget'):
                    admit(root,report_bytes=3,scratch_bytes=0,limits=limits)
                self.assertEqual(set(root.rglob('*')),before)

    def test_archive_pressure_blocks_capture_without_deleting_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);path=root/'reports/retained_artifacts/chunks/hash';path.parent.mkdir(parents=True);path.write_bytes(b'evidence')
            with patch('development_storage.require_free_space'),self.assertRaises(OSError):
                admit(root,report_bytes=0,limits=dict(LIMITS,archive=1))
            self.assertEqual(path.read_bytes(),b'evidence')

    def test_shared_runner_never_launches_when_admission_fails(self):
        from run_godot_check import execute
        with tempfile.TemporaryDirectory() as temporary:
            with patch('run_godot_check.require_free_space'), patch('run_godot_check.admit',side_effect=OSError('Development output budget reached')), patch('run_godot_check.subprocess.Popen') as launch:
                result=execute(['fake-godot.exe'],Path(temporary),3,'DONE')
            launch.assert_not_called()
            self.assertFalse(result['passed'])
            self.assertIn('Development output budget',result['launch_error'])


if __name__=='__main__':unittest.main()
