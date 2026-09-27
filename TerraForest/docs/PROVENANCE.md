# Provenance

Inputs:

- `C:\Users\Windows10_new\Downloads\TerrainRewrite_v0.4.4\TerrainRewrite` — code identifies itself as 0.4.6-r4 despite the enclosing download name.
- `C:\Users\Windows10_new\Downloads\Forest12.RC3\Forest12` — contains later RC6/RC7 changes despite the enclosing RC3 name.

The unpacked directories supplied by the user were used. Nested zip files were not silently selected as alternate versions. `source_manifest.json` records original copied-file SHA-256 values. It describes inputs, not the final modified-file hashes. The release packager writes a separate final manifest.

Terrain native binaries and their base meshes are retained as a matching set. Native code/ABI and procedural field generation were not changed. The GDScript query/integration layer reuses existing native command 7 to verify natural-surface support; it does not pretend that command returns edited surface height.

The existing meshing and vegetation render algorithms were preserved while public APIs, lifecycle handling, world integration, streaming admission, resource paths, export loading and the demo were changed. This is not a claim that all underlying algorithms were newly authored.

Both code distributions provide 0BSD licenses. Spruce provenance and its stated CC0 terms are retained in `addons/vegetation/ASSET_LICENSE.md`. Terrain texture notices are retained under `addons/volumetric_terrain/terrain_textures`. Review those notices when publishing assets separately. No Godot executable, export template, compiler, system library or Python package is redistributed.
