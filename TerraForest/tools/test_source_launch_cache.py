# SPDX-License-Identifier: 0BSD
"""Preparation reuse must fail closed on source/output changes and incomplete runs."""
import tempfile
import os
import unittest
from pathlib import Path
from source_launch_cache import IMPORT_INDEX, check, record, execute_action


class PreparationCache(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'TerraForest'
        self.root.mkdir()
        (self.root.parent / 'Launcher').mkdir()
        self.engine = self.root.parent / 'godot.exe'
        self.engine.write_bytes(b'engine')
        self.write('addons/example/native/world.cpp', b'source')
        self.write('addons/example/bin/example.dll', b'native')
        self.write('assets/image.png', b'image')
        self.write('.godot/imported/image.ctex', b'imported')
        for name in IMPORT_INDEX:
            self.write('.godot/' + name, b'index')

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def ready(self):
        self.assertFalse(check(self.root, self.engine))
        record(self.root, self.engine)
        self.assertTrue(check(self.root, self.engine))

    def test_current_preparation_survives_fresh_checks_and_log_changes(self):
        self.ready()
        self.write('reports/worlds_game.log', b'new log')
        self.write('docs/note.md', b'documentation')
        self.assertTrue(check(self.root, self.engine))

    @unittest.skipUnless(os.name == 'nt', 'Windows native build lease')
    def test_fast_path_respects_an_active_native_build(self):
        from cleanup_generation_copies import lease
        self.ready()
        with lease(self.root / 'reports/native_build'):
            with self.assertRaises(OSError):
                execute_action(self.root, self.engine, 'check')
        self.assertEqual(execute_action(self.root, self.engine, 'check'), 0)

    def test_source_native_asset_and_import_changes_require_preparation(self):
        for path in ['addons/example/native/world.cpp', 'addons/example/bin/example.dll',
                     'assets/image.png', '.godot/imported/image.ctex', '.godot/uid_cache.bin']:
            with self.subTest(path=path):
                check(self.root, self.engine, force=True)
                record(self.root, self.engine)
                self.write(path, b'changed contents')
                self.assertFalse(check(self.root, self.engine))

    def test_new_and_deleted_files_invalidate_preparation(self):
        self.ready()
        path = self.write('addons/new_pack/model.res', b'new model')
        self.assertFalse(check(self.root, self.engine))
        record(self.root, self.engine)
        path.unlink()
        self.assertFalse(check(self.root, self.engine))

    def test_engine_replacement_invalidates_preparation(self):
        self.ready()
        self.engine.write_bytes(b'new engine')
        self.assertFalse(check(self.root, self.engine))

    def test_source_edits_during_pipeline_cannot_be_marked_ready(self):
        self.assertFalse(check(self.root, self.engine))
        self.write('addons/example/native/world.cpp', b'changed while importing')
        with self.assertRaises(ValueError):
            record(self.root, self.engine)

    def test_pipeline_may_update_its_generated_outputs(self):
        self.assertFalse(check(self.root, self.engine))
        self.write('addons/example/bin/example.dll', b'rebuilt')
        self.write('assets/image.png.import', b'import recipe')
        self.write('addons/player_runtime/art/drops/3.res', b'baked mesh')
        record(self.root, self.engine)
        self.assertTrue(check(self.root, self.engine))

    def test_missing_import_indexes_cannot_be_marked_ready(self):
        self.assertFalse(check(self.root, self.engine))
        (self.root / '.godot/uid_cache.bin').unlink()
        with self.assertRaises(ValueError):
            record(self.root, self.engine)

    def test_corrupt_receipt_and_force_option_require_full_pipeline(self):
        self.ready()
        self.write('reports/source_preparation/ready.json', b'broken json')
        self.assertFalse(check(self.root, self.engine))
        record(self.root, self.engine)
        self.assertFalse(check(self.root, self.engine, force=True))
        self.assertFalse(check(self.root, self.engine), 'A failed/interrupted forced pipeline cannot reuse the older ready record')


if __name__ == '__main__':
    unittest.main()
