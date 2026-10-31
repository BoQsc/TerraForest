# BG5 runtime assets

The user-supplied door, chest, chair, table and bookshelf replace the five
built-in visual meshes at their existing resource paths. Model IDs, recipes,
durability, hinge packets, placement transforms and native collision proxies
are unchanged. No save migration or native DLL replacement is needed.

## Authoring and rights

The original five GLBs are retained byte-for-byte in
[`authoring/bg5`](../authoring/bg5/README.md), including parts, animations,
textures and embedded reconstruction metadata. The contributor reports ChatGPT
website/Pro authorship and confirmed on 2026-10-30 that all inputs were their
own/generated material and approved CC0. Exact hashes and that statement are in
[`provenance.json`](../authoring/bg5/provenance.json). The
[runtime notice](../addons/structures/prefabs/BG5_LICENSE.md) is also in offline
game credits. This records the contributor's confirmation, not a new assertion
about unrelated project assets or third-party engine components.

The masters are excluded from Godot import and game exports, but retained in
source archives. Runtime derivatives do not alter the Downloads originals.

## Outputs and canonical dimensions

| Runtime visual | Source mesh parts → surfaces | Triangles at full detail | Canonical size, width × height × depth |
| --- | --- | ---: | --- |
| Door leaf | 44 → 3 | 4,048 | Timber leaf fits X=0..1 m, Y=0..2.2 m; hardware stays within about 1 cm of the hinge/latch edges. |
| Door frame | 37 → 3 | 3,584 | About 1.215 × 2.321 × 0.222 m; same alignment transform as the leaf. |
| Chest, closed | 45 → 1 | 1,084 | 1.215 × 0.75 × 0.8075 m |
| Chair | 10 → 2 | 1,032 | 0.48 × 0.98 × 0.48 m |
| Table | 16 → 2 | 1,152 | 1.6 × 0.8 × 0.9 m |
| Bookshelf | 13 → 1 | 812 | 1.2 × 1.8 × 0.4 m |

The furniture sizes match the previous visual AABBs. Each is grounded at Y=0;
chair and shelf are turned to preserve the old front/back convention. The recipe
retains the existing six chair, five table and seven shelf collision boxes.
Chest collision remains the existing single box. Matching these established
game dimensions intentionally applies nonuniform scaling to the supplied art.

The door uses a proper 180-degree rotation (no reflected winding), aligning its
source hinge axis with legacy X=Z=0 and its timber bottom with Y=0. Native
collision remains X=0..1, Y=0..2.2, Z=-0.07..0.07. The visual handles and hinge
hardware extend beyond the timber as they did on the old simple model; they do
not add collision bodies. The original 90-degree opening behavior remains.

`door_frame.glb` is a separate stationary companion. It is **not** merged into
the moving leaf or automatically placed into existing worlds. Existing buildings
continue providing their current doorway structures. Chest lid and assembly
animations remain available in the masters; the current chest gameplay uses
one static closed mesh and its existing storage interaction.

## Rebuild and validate

```text
python tools/prepare_bg5_runtime.py --godot <Godot-4.7-Windows-engine>
python tools/prepare_bg5_runtime.py --check
python tools/check_bg5_runtime.py
python tools/check_bg5_runtime.py --preview
```

[`runtime_recipe.json`](../authoring/bg5/runtime_recipe.json) is the readable
source for part selection, transforms, dimensions and inherited collision boxes.
The original 0BSD conversion tool imports each master offline, combines parts
by material, generates geometry LODs and writes the existing `.tres` resources
plus portable GLBs in [`mods/bg5_runtime`](../mods/bg5_runtime/README.md).
Their `.glb.import` sidecars use Godot's `Keep File` mode so exported games retain
the raw GLB bytes required by the loose-mod loader instead of scene remaps.
The bake receipt records source, recipe, tool, texture/import and output hashes;
export fails if these are stale. Legacy `bake_door.gd`, `bake_furniture.gd` and
`bake_storage_chest.gd` still describe historical simple meshes and must not be
used to regenerate these supplied models.

The door master uses mirrored-repeat UVs that Godot's standard material import
otherwise clamps. The bake creates one mirrored texture period and halves UV
scale to preserve wrapping, then uses ordinary repeating standard materials.
This fixes the stretched edge sampling without a runtime custom shader.

Textures are capped at a 1024-pixel long edge, share hashed resources, use
mipmaps/aniso filtering and VRAM compression for built-in meshes. Portable GLBs
embed their own textures for loose-pack use. No authoring animations, separate
screw nodes, physics bodies or animation players are instantiated per placement.
Native batches, native hinge changes and existing near/far rendering remain the
runtime owners. Scaled built-in variants regenerate their LODs at catalog startup
instead of losing them during the mesh transform.

The loose door importer now permits eight embedded images, each at most 2048²,
with a combined 16,777,216-pixel limit. The former four-by-2048² total ceiling is
retained while accommodating compact multi-material PBR sets. Existing file,
vertex, node and surface caps remain. Decoded-size checks are not a sandbox.

After export, run `python tools/check_bg5_runtime.py --pack` and
`python tools/check_bg5_runtime.py --pack --preview`. The latter uses the native
model collection and hinge with the stationary frame in a separate collection.
Tests use fresh temporary worlds/fixtures and do not rewrite user saves.

## Verification and limits

[Evidence and inspected images](evidence/bg5_runtime/README.md) distinguish
source checks, release checks, the packaged game and rejected intermediate bakes.
Legacy door bytes, actual disk save/reopen, new mod doors and native collision
are checked independently from image review. No native source or library is
changed by this asset conversion.

The art has more full-detail geometry than the earlier box meshes. Batching,
LOD, texture and instance bounds are preserved; this is not a guarantee of
identical frame times in every dense world. Human visual approval, dense-world
cost qualification, automatic frame placement and animated chest lids remain
separate work, with triggers recorded in WORLD_FOUNDATION_STATUS.md.
