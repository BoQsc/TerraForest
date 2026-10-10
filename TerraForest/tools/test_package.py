# SPDX-License-Identifier: 0BSD
"""Fast packaging contract checks; no engine or editor cache required."""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
import zipfile
import package

class PackageTests(unittest.TestCase):
    def test_all_declared_bundles_cover_existing_literal_resources(self):
        for addon in package.DEPENDENCIES:
            with self.subTest(addon=addon):
                files, metadata = package.addon_entries(addon)
                names = {p.relative_to(package.ROOT).as_posix() for p in files}
                self.assertIn('LICENSE.txt', names)
                self.assertIn(addon, metadata['included_addons'])
                for path in files:
                    if path.suffix not in {'.gd', '.tscn', '.tres', '.gdextension', '.gdshader'}:
                        continue
                    for ref in re.findall(r'res://([^"\s\)\],;]+)', path.read_text(encoding='utf-8')):
                        if (package.ROOT/ref).is_file():
                            self.assertIn(ref, names, str(path)+': '+ref)
    def test_archive_is_deterministic_and_manifest_is_local(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source.txt';source.write_text('asset', encoding='utf-8')
            first = package.archive(root/'one.zip', [source], root, {'addon':'fixture'})
            second = package.archive(root/'two.zip', [source], root, {'addon':'fixture'})
            self.assertEqual(first, second)
            with zipfile.ZipFile(root/'one.zip') as archive:
                manifest=json.loads(archive.read('MANIFEST.sha256.json'))
                self.assertEqual(set(archive.namelist()), set(manifest)|{'MANIFEST.sha256.json'})
                for name, digest in manifest.items():
                    self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(),digest)
    def test_cache_and_hot_reload_libraries_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            for name in ['.godot/cache', '.build/object', 'reports/result', 'bin/~copy.dll', 'MANIFEST.sha256.json']:
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'x')
                self.assertFalse(package.include_file(path,root))
    def test_vehicle_asset_provenance_included(self):
        files,_=package.addon_entries('vehicle_runtime')
        names={p.relative_to(package.ROOT).as_posix() for p in files}
        self.assertTrue({'vehicle_demo/LICENSE.txt','vehicle_demo/PROVENANCE.md','vehicle_demo/assets/Vehicle.glb'}<=names)

if __name__ == '__main__':
    unittest.main()
