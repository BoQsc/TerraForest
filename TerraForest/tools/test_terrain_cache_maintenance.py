"""Exercise offline cache maintenance using disposable fixtures only."""
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import maintain_terrain_cache as cache


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def packet(self, key=(0, 0, 32), age=1, snapshot="b" * 64):
        path = self.root / ("a" * 64) / snapshot / ("%d_%d_%d.trc" % key)
        path.parent.mkdir(parents=True, exist_ok=True)
        data = struct.pack("<IIiiiIIII", cache.MESH_MAGIC, 5, *key, 1, 0, 0, 0)
        path.write_bytes(struct.pack("<II", cache.TRC_MAGIC, len(data)) + hashlib.sha256(data).digest() + data)
        os.utime(path, ns=(age, age))
        return path

    def test_dry_run_and_oldest_first_across_snapshots(self):
        oldest = self.packet(age=1)
        newest = self.packet((-1, 2, 32), age=3, snapshot="new_seed_1703")
        middle = self.packet((2, 2, 32), age=2, snapshot="c" * 64)
        entries, skipped = cache.inspect(self.root)
        self.assertEqual(skipped, 0)
        self.assertEqual([e.path for e in cache.plan(entries, 76)], [oldest, middle])
        self.assertTrue(all(p.exists() for p in (oldest, newest, middle)))
        self.assertEqual(cache.plan(entries, 228), [])

    def test_removal_preserves_saved_world_and_unknown_files(self):
        path = self.packet()
        world = self.root / "world.trw"
        world.write_bytes(b"canonical")
        unknown = path.with_name("notes.trc")
        unknown.write_bytes(b"do not remove")
        entries, skipped = cache.inspect(self.root)
        self.assertEqual(skipped, 2)
        self.assertTrue(cache.remove_verified(self.root, entries[0]))
        self.assertFalse(path.exists())
        self.assertEqual(world.read_bytes(), b"canonical")
        self.assertEqual(unknown.read_bytes(), b"do not remove")

    def test_corrupt_digest_is_retained(self):
        path = self.packet()
        data = bytearray(path.read_bytes())
        data[8] ^= 1
        path.write_bytes(data)
        entries, _ = cache.inspect(self.root)
        self.assertEqual(len(entries), 1)
        self.assertFalse(cache.remove_verified(self.root, entries[0]))
        self.assertTrue(path.exists())

    def test_changed_file_is_retained(self):
        path = self.packet()
        entries, _ = cache.inspect(self.root)
        path.write_bytes(path.read_bytes() + b"changed")
        self.assertFalse(cache.remove_verified(self.root, entries[0]))
        self.assertTrue(path.exists())

    def test_bad_header_key_version_length_and_namespace(self):
        path = self.packet()
        original = path.read_bytes()
        for offset in (0, 4, 40, 44, 48):
            data = bytearray(original)
            data[offset] ^= 1
            path.write_bytes(data)
            self.assertEqual(cache.inspect(self.root)[0], [])
        path.write_bytes(original[:50])
        self.assertEqual(cache.inspect(self.root)[0], [])
        self.packet(snapshot="not-a-snapshot")
        self.assertEqual(cache.inspect(self.root)[0], [])

    def test_scan_limit_aborts_before_any_delete(self):
        path = self.packet()
        with self.assertRaisesRegex(ValueError, "Scan limit"):
            cache.inspect(self.root, 2)
        self.assertTrue(path.exists())

    def test_outside_root_entry_rejected(self):
        path = self.packet()
        entries, _ = cache.inspect(self.root)
        self.assertFalse(cache.remove_verified(self.root / "other", entries[0]))
        self.assertTrue(path.exists())

    def test_symlink_not_traversed(self):
        self.packet()
        link = self.root / ("d" * 64)
        try:
            link.symlink_to(self.root / ("a" * 64), target_is_directory=True)
        except OSError:
            self.skipTest("Symlink creation unavailable on this host")
        entries, skipped = cache.inspect(self.root)
        self.assertEqual(len(entries), 1)
        self.assertEqual(skipped, 1)
        with self.assertRaises(ValueError):
            cache.inspect(link)

    def test_cli_dry_run_and_explicit_offline_apply(self):
        path = self.packet()
        command = [sys.executable, str(Path(cache.__file__)), str(self.root), "--budget-mib", "0"]
        dry = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(dry.returncode, 0, dry.stderr)
        self.assertIn('"planned_bytes": 76', dry.stdout)
        self.assertTrue(path.exists())
        refused = subprocess.run(command + ["--apply"], capture_output=True, text=True)
        self.assertNotEqual(refused.returncode, 0)
        self.assertTrue(path.exists())
        applied = subprocess.run(command + ["--apply", "--offline"], capture_output=True, text=True)
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
