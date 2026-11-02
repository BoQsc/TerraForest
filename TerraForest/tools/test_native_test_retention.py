# SPDX-License-Identifier: 0BSD
import hashlib
from pathlib import Path
import tempfile
import unittest
from native_test_retention import release_copies


class NativeTestRetention(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / 'reports/check/20261102T172758641008Z/debug'
        self.library = self.project / 'addons/example/bin/example.windows.dll'
        self.library.parent.mkdir(parents=True)
        self.library.write_bytes(b'copied native library')
        self.digest = hashlib.sha256(self.library.read_bytes()).hexdigest()
        self.projects = {self.project: {self.library: self.digest}}

    def test_removes_only_exact_successful_copy(self):
        evidence = self.project / 'evidence.png'
        evidence.write_bytes(b'original review')
        receipt = release_copies(self.projects, True, self.root)
        self.assertFalse(self.library.exists())
        self.assertEqual(receipt['bytes'], len(b'copied native library'))
        self.assertEqual(evidence.read_bytes(), b'original review')
        self.assertFalse(receipt['errors'])

    def test_failed_run_preserves_libraries(self):
        receipt = release_copies(self.projects, False, self.root)
        self.assertTrue(self.library.exists())
        self.assertTrue(receipt['retained_failed_run'])

    def test_nonboolean_success_is_not_authorization(self):
        for value in [1, 'true', 'false', None]:
            receipt = release_copies(self.projects, value, self.root)
            self.assertTrue(self.library.exists())
            self.assertTrue(receipt['retained_failed_run'])

    def test_changed_bytes_preserve_every_candidate(self):
        other = self.library.with_name('other.dll')
        other.write_bytes(b'changed')
        self.projects[self.project][other] = self.digest
        receipt = release_copies(self.projects, True, self.root)
        self.assertTrue(receipt['errors'])
        self.assertTrue(self.library.exists())
        self.assertTrue(other.exists())

    def test_installed_or_reusable_project_rejected(self):
        for project in [self.root, self.root / 'dist', self.root / '.build/reusable']:
            with self.subTest(project=project):
                receipt = release_copies({project: {self.library: self.digest}}, True, self.root)
                self.assertTrue(receipt['errors'])
                self.assertTrue(self.library.exists())

    def test_escaping_path_and_nonlibrary_rejected(self):
        for path in [self.root / 'outside.dll', self.project / 'addons/example/bin/notes.txt']:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'copied native library')
            receipt = release_copies({self.project: {path: self.digest}}, True, self.root)
            self.assertTrue(receipt['errors'])
            self.assertTrue(path.exists())

    def test_unique_build_project_supported(self):
        project = self.root / '.build/building_contract_release_20261102T172758641008Z'
        path = project / 'addons/example/bin/example.dll'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'copied native library')
        receipt = release_copies({project: {path: self.digest}}, True, self.root)
        self.assertFalse(path.exists())
        self.assertFalse(receipt['errors'])

    def test_linked_library_is_retained(self):
        link = self.library.with_name('linked.dll')
        try:
            link.symlink_to(self.library)
        except OSError:
            self.skipTest('Windows symlink creation is unavailable')
        receipt = release_copies({self.project: {link: self.digest}}, True, self.root)
        self.assertTrue(receipt['errors'])
        self.assertTrue(self.library.exists())
        self.assertTrue(link.is_symlink())


if __name__ == '__main__':
    unittest.main()
