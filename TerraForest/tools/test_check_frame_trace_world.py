# SPDX-License-Identifier: 0BSD
"""Storage/pairing failures must precede materializing a gameplay fixture."""
from pathlib import Path
from types import SimpleNamespace
import os
import tempfile
import unittest
from unittest.mock import patch

import check_frame_trace_world as launcher
from resource_limits import load_budgets


class CapturePreflightTest(unittest.TestCase):
    def test_failed_preflight_creates_no_world_or_report(self):
        for failure in ('space', 'native_pairing'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                worlds = root / 'Godot/app_userdata/TerraForest/worlds'
                worlds.mkdir(parents=True)
                fixture = worlds / 'StartupBench_FPS_20261109T073252.trw'
                fixture.write_bytes(b'preserved fixture')
                available = load_budgets()['minimum_free_bytes'] + fixture.stat().st_size + 256 * 2**20 - 1
                if failure == 'native_pairing':
                    available += 1024**3
                before = set(root.rglob('*'))
                with patch.dict(os.environ, APPDATA=str(root)), \
                     patch.object(launcher, 'ROOT', root), \
                     patch.object(launcher, 'parse_args', return_value=(SimpleNamespace(), [])), \
                     patch('sys.argv', ['check_frame_trace_world.py', '--executable']), \
                     patch('resource_limits.shutil.disk_usage', return_value=SimpleNamespace(free=available)), \
                     patch.object(launcher, 'verify_pack_native', side_effect=ValueError('mismatched native libraries')) as native, \
                     patch.object(launcher, 'clone_once') as clone, \
                     patch.object(launcher, 'execute') as execute:
                    with self.assertRaises(OSError if failure == 'space' else ValueError):
                        launcher.main()
                    clone.assert_not_called()
                    execute.assert_not_called()
                    self.assertEqual(native.call_count, int(failure == 'native_pairing'))
                self.assertEqual(set(root.rglob('*')), before)
                self.assertEqual(fixture.read_bytes(), b'preserved fixture')


if __name__ == '__main__':
    unittest.main()
