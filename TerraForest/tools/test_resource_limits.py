import ctypes
import hashlib
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from cache_retention import finalize_cache
import maintain_terrain_cache as packets
from resource_limits import distribution_size, evaluate, load_budgets, require_free_space, ResourceMonitor
from storage_maintenance import maintain
from run_godot_check import execute


class ResourceLimitTests(unittest.TestCase):
    def test_limits_and_unknown_measurements(self):
        limits = load_budgets()
        self.assertEqual(limits['vram_limit_bytes'], 4 * 1024**3)
        self.assertEqual(limits['redistributable_limit_bytes'], 5_000_000_000)
        self.assertEqual(evaluate()['vram']['status'], 'unavailable')
        for name, argument in [('vram', 'vram_bytes'), ('ram', 'private_bytes'), ('redistributable', 'distribution_bytes')]:
            self.assertEqual(evaluate(**{argument: limits[name + '_warning_bytes']})[name]['status'], 'warning')
            self.assertEqual(evaluate(**{argument: limits[name + '_limit_bytes'] + 1})[name]['status'], 'exceeded')

    def test_distribution_excludes_old_packs_source_and_reports(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, size in [('TerraForest.pck', 50), ('TerraForest.pending.pck', 1000),
                               ('TerraForest-source.zip', 1000), ('TerraForest.exe', 20),
                               ('addons/native.dll', 10), ('reports/trace', 1000)]:
                path = root / name
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(b'x' * size)
            self.assertEqual(distribution_size(root), 80)
            self.assertEqual(distribution_size(root, root / 'TerraForest.pending.pck'), 1030)

    def test_low_disk_fails_before_new_work(self):
        with patch('resource_limits.shutil.disk_usage') as usage:
            usage.return_value.free = 1
            with self.assertRaisesRegex(OSError, 'Low storage'):
                require_free_space(Path('.'))
            usage.return_value.free = load_budgets()['minimum_free_bytes']
            require_free_space(Path('.'))
            with self.assertRaises(OSError):
                require_free_space(Path('.'), 1)

    def test_unknown_gpu_is_not_qualified(self):
        with patch('resource_limits.os.name', 'unavailable'):
            reader = ResourceMonitor(1)
        report = reader.report()
        self.assertFalse(report['telemetry_complete'])
        self.assertFalse(report['within_sampled_limits'])
        self.assertEqual(report['checks']['vram']['status'], 'unavailable')
        reader.close()

    def test_runner_fails_over_budget_and_required_unknown_telemetry(self):
        for exceeded, complete, required, expected in [(True, True, False, False), (False, False, True, False), (False, True, True, True)]:
            with self.subTest(exceeded=exceeded, complete=complete), tempfile.TemporaryDirectory() as folder:
                with patch('run_godot_check.subprocess.Popen') as launch, patch('run_godot_check.ResourceMonitor') as monitor, patch('run_godot_check.require_free_space'):
                    child = launch.return_value
                    child.pid = 123
                    child.poll.side_effect = [None, 0, 0]
                    child.wait.return_value = 0
                    monitor.return_value.report.return_value = {'exceeded': exceeded, 'within_sampled_limits': complete}
                    def start(*args, **kwargs):
                        kwargs['stdout'].write('DONE\n')
                        return child
                    launch.side_effect = start
                    result = execute(['fake-godot.exe'], Path(folder), 3, 'DONE', require_resource_budget=required)
                    self.assertEqual(result['passed'], expected)
                    monitor.return_value.close.assert_called_once()

    def packet(self, root):
        path = root / ('a' * 64) / ('b' * 64) / '0_0_32.trc'
        path.parent.mkdir(parents=True)
        payload = struct.pack('<IIiiiIIII', packets.MESH_MAGIC, 5, 0, 0, 32, 1, 0, 0, 0)
        path.write_bytes(struct.pack('<II', packets.TRC_MAGIC, len(payload)) + hashlib.sha256(payload).digest() + payload)
        return path

    def test_global_cleanup_preserves_worlds_unknown_data_and_corruption(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            cache = root / 'old_check'
            cache.mkdir()
            (cache / '.terraforest-derived.lock').touch()
            packet = self.packet(cache)
            saved = self.packet(root / 'worlds')
            (root / 'worlds/.terraforest-derived.lock').touch()
            note = cache / 'evidence.png'
            note.write_bytes(b'evidence')
            corrupt = packet.with_name('32_0_32.trc')
            corrupt.write_bytes(packet.read_bytes()[:-1] + b'!')
            result = maintain(root, 0, False)
            self.assertTrue(packet.exists())
            result = maintain(root, 0, True)
            self.assertEqual(result['removed_files'], 1)
            self.assertTrue(saved.exists() and note.exists() and corrupt.exists())
            self.assertEqual(len(result['failures']), 1)

    def test_successful_cache_cleanup_and_failed_quota(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'data'
            registry = Path(folder) / 'registry'
            root.mkdir()
            name = 'owned_' + 'a' * 32
            owned = root / name
            owned.mkdir()
            (owned / 'mesh.bin').write_bytes(b'generated')
            command = ['godot', '--temporary', '--derived-cache=user://' + name]
            result = finalize_cache(command, True, root, registry, 0)
            self.assertFalse(owned.exists())
            self.assertIsNotNone(result['removed_owned_cache'])
            failed = root / ('failed_' + 'b' * 32)
            packet = self.packet(failed)
            note = failed / 'failure.png'
            note.write_bytes(b'evidence')
            result = finalize_cache(['godot', '--temporary', '--derived-cache=user://' + failed.name], False, root, registry, 0)
            self.assertFalse(packet.exists())
            self.assertTrue(note.exists())
            self.assertTrue(result['over_budget'])
            self.assertEqual(result['failed_cache_bytes'], len(b'evidence'))

    def test_nonunique_and_non_temporary_paths_never_deleted(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for command in [['godot', '--derived-cache=user://worlds'],
                            ['godot', '--temporary', '--derived-cache=user://worlds'],
                            ['godot', '--temporary', '--derived-cache=user://../worlds']]:
                self.assertFalse(finalize_cache(command, True, root)['managed'])

    @unittest.skipUnless(os.name == 'nt', 'Windows counters')
    def test_current_process_memory_and_counter_structure(self):
        from windows_process_metrics import CounterItem, GpuMemoryMetrics, ProcessMetrics
        self.assertEqual(ctypes.sizeof(CounterItem), 24)
        reader = ProcessMetrics(os.getpid())
        try:
            result = reader.sample()
            self.assertGreaterEqual(result['peak_working_set_bytes'], result['working_set_bytes'])
            self.assertGreaterEqual(result['peak_private_commit_bytes'], result['private_commit_bytes'])
        finally:
            reader.close()
        gpu = GpuMemoryMetrics(os.getpid())
        try:
            value = gpu.sample()
            self.assertTrue(value is None or value >= 0)
        finally:
            gpu.close()


if __name__ == '__main__':
    unittest.main()
