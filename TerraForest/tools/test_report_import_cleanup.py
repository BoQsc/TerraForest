# SPDX-License-Identifier: 0BSD
import tempfile
import unittest
from pathlib import Path
import cleanup_report_imports as cleanup


class ReportImports(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'reports/example').mkdir(parents=True)
        (self.root / 'reports/.gdignore').touch()
        (self.root / '.godot/imported').mkdir(parents=True)
        self.source = self.root / 'reports/example/review.png'
        self.source.write_bytes(b'original evidence')
        self.target = self.root / ('.godot/imported/review.png-' + 'a' * 32 + '.ctex')
        self.target.write_bytes(b'rebuildable import')
        self.mapping = self.source.with_suffix('.png.import')
        self.mapping.write_text('source_file="res://reports/example/review.png"\n'
            'path="res://' + self.target.relative_to(self.root).as_posix() + '"\n')

    def test_removes_only_mapped_import_preserves_evidence(self):
        rows = cleanup.candidates(self.root)
        self.assertEqual(len(rows), 1)
        cleanup.remove(rows[0], self.root)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.source.read_bytes(), b'original evidence')
        self.assertTrue(self.mapping.is_file())

    def test_missing_ignore_refuses_cleanup(self):
        (self.root / 'reports/.gdignore').unlink()
        with self.assertRaises(FileNotFoundError):
            cleanup.candidates(self.root)

    def test_other_imports_preserved(self):
        other = self.root / '.godot/imported/runtime.ctex'
        other.write_bytes(b'runtime asset')
        for row in cleanup.candidates(self.root):
            cleanup.remove(row, self.root)
        self.assertTrue(other.is_file())

    def test_changed_source_or_mapping_refused(self):
        row = cleanup.candidates(self.root)[0]
        self.source.write_bytes(b'new evidence')
        with self.assertRaises(ValueError):
            cleanup.remove(row, self.root)
        row = cleanup.candidates(self.root)[0]
        self.mapping.write_text('changed')
        with self.assertRaises(ValueError):
            cleanup.remove(row, self.root)

    def test_misdeclared_source_refused(self):
        self.mapping.write_text(self.mapping.read_text().replace('reports/example/review.png', 'addons/runtime.png'))
        self.assertEqual(cleanup.candidates(self.root), [])

    def test_parent_traversal_refused(self):
        self.mapping.write_text('source_file="res://reports/example/review.png"\npath="res://.godot/imported/../../review.png-' + 'a' * 32 + '.ctex"')
        self.assertEqual(cleanup.candidates(self.root), [])


if __name__ == '__main__':
    unittest.main()
