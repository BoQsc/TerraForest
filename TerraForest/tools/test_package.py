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
    def test_dynamic_asset_paths_have_declared_addon_dependencies(self):
        for addon in package.DEPENDENCIES:
            files, metadata = package.addon_entries(addon)
            for path in files:
                if path.suffix != '.gd':
                    continue
                for target in re.findall(r'res://addons/([a-z_]+)/', path.read_text(encoding='utf-8')):
                    self.assertIn(target, metadata['included_addons'], str(path)+': '+target)
    def test_uncompressed_binary_resource_dependencies_are_bundled(self):
        for addon in package.DEPENDENCIES:
            files, _ = package.addon_entries(addon)
            names = {p.relative_to(package.ROOT).as_posix() for p in files}
            for path in files:
                if path.suffix != '.res' or not path.read_bytes().startswith(b'RSRC'):
                    continue  # Compressed resources require the engine verifier.
                for raw in re.findall(rb'res://([A-Za-z0-9_./-]+)', path.read_bytes()):
                    ref = raw.decode('ascii')
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
    def test_character_runtime_bundle_and_player_dependency(self):
        files, metadata=package.addon_entries('player_runtime')
        names={p.relative_to(package.ROOT).as_posix() for p in files}
        self.assertIn('characters', metadata['included_addons'])
        _, character_metadata=package.addon_entries('characters')
        self.assertIn('world_runtime',character_metadata['included_addons'])
        self.assertIn('player_runtime',character_metadata['included_addons'])
        self.assertTrue({'addons/characters/runtime/assets/Human.r11.glb',
                         'addons/characters/runtime/assets/Human.placement.res',
                         'addons/characters/runtime/assets/Human.pickaxe_diagonal.res',
                         'addons/characters/runtime/assets/Human.pickaxe_side_pullback.res',
                         'addons/characters/runtime/assets/Human.pickaxe_fresh.res',
                         'addons/characters/runtime/assets/Zombie.drag_walk.res',
                         'addons/characters/runtime/assets/Zombie.r4.glb',
                         'addons/characters/runtime/assets/Zombie.r4.behavior.json',
                         'addons/characters/LICENSE.txt', 'addons/characters/README.md'}<=names)
        self.assertFalse(any('/ZombieLab/' in name or '/Human_R11_Complete_Repost/' in name for name in names))
        pairs=[('Human.r11.glb','Human_R11_Complete_Repost/Godot_Viewer/models/Human.r11.glb'),
               ('Zombie.r4.glb','ZombieLab/assets/Zombie.r4.glb')]
        for runtime, original in pairs:
            self.assertEqual(hashlib.sha256((package.ROOT/'addons/characters/runtime/assets'/runtime).read_bytes()).digest(),
                             hashlib.sha256((package.ROOT/'addons/characters'/original).read_bytes()).digest())

if __name__ == '__main__':
    unittest.main()
