# SPDX-License-Identifier: 0BSD
"""Exercise isolation arguments and process failures without launching a world."""
import sys
import tempfile
import unittest
from pathlib import Path
from run_godot_check import command_for, execute


class CheckLauncherTests(unittest.TestCase):
    def test_fresh_cache_and_override_rejection(self):
        first, cache = command_for("godot", "cache_eviction_world", Path("reports"), [])
        second, other = command_for("godot", "cache_eviction_world", Path("reports"), [])
        self.assertNotEqual(cache, other)
        self.assertTrue(cache.startswith("user://cache_eviction_world_"))
        self.assertIn("--derived-cache=" + cache, first[first.index("--")+1:])
        self.assertIn("--temporary", second)
        for flag in ["--derived-cache=user://terrain_cache", "--derived-cache", "--no-derived-cache",
                     "--world-slot=world", "--snapshot-readonly", "--temporary", "--"]:
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                command_for("godot", "cache_eviction_world", Path("reports"), [flag])
        with self.assertRaises(ValueError):
            command_for("godot", "../demo/world", Path("reports"), [])

    def run_process(self, source, timeout=5):
        with tempfile.TemporaryDirectory() as directory:
            return execute([sys.executable, "-c", source], Path(directory), timeout, "DONE")

    def test_success_requires_completion_and_no_engine_errors(self):
        self.assertTrue(self.run_process("print('DONE')")["passed"])
        for source in ["print('unrelated')", "print('DONE');print('SCRIPT ERROR: fixture')",
                       "print('DONE');raise SystemExit(3)", "print('DONE');print('FAIL gate')"]:
            with self.subTest(source=source):
                self.assertFalse(self.run_process(source)["passed"])

    def test_timeout_and_missing_executable_are_retained_failures(self):
        result = self.run_process("import time;print('DONE',flush=True);time.sleep(10)", .1)
        self.assertTrue(result["timed_out"])
        self.assertFalse(result["passed"])
        with tempfile.TemporaryDirectory() as directory:
            result = execute([str(Path(directory)/"missing.exe")], Path(directory), 1, "DONE")
        self.assertIsNotNone(result["launch_error"])
        self.assertFalse(result["passed"])

    def test_old_and_counted_object_leak_warnings_fail(self):
        for warning in ["WARNING: ObjectDB instances leaked at exit",
                        "WARNING: 3 ObjectDB instances were leaked at exit"]:
            with self.subTest(warning=warning):
                result = self.run_process("print('DONE');print(" + repr(warning) + ")")
                self.assertFalse(result["passed"])
                self.assertIn(warning, result["diagnostics"])

    def test_engine_log_errors_override_successful_console(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder/"engine.log").write_text("ERROR: native failure\n", encoding="utf-8")
            result = execute([sys.executable, "-c", "print('DONE')"], folder, 5, "DONE")
        self.assertFalse(result["passed"])


if __name__ == "__main__":
    unittest.main()
