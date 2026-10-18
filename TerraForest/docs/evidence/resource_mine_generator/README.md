# Resource-bearing mine generator 13 — 2026-10-18

Generator 13 preserves profile-12 terrain geometry, roads, lakes and owned cave
layout, adding two finite deposits tied to the main chamber and workings. Iron
occupies the first, copper the second. Each capsule is centred six metres west
and one metre below its chamber datum, with a six-metre axial segment and a
three-metre falloff radius. Its continuous weight blends into ordinary geology.
The constant two-deposit lookup rejects points outside small bounds before distance
evaluation. No authored voxel pages or runtime scans are introduced.

World::ore_weight is used by base_material (including excavation rewards), mesh
shading and material diagnostic queries. Profiles 1–12 retain their prior field.
Profile 13 has a distinct save/cache identity and uses the existing snapshot format.
New integrated district preparation selects 13; lake-only preparation retains 12.
Existing saves are preserved. Both Windows debug/release DLLs were rebuilt with
Zig and the pinned prebuilt godot-cpp library; no SDK sources were compiled.

Validation:

- All seven seeds (0,1,42,50,141,1703,9999) now expose both ores within 0.5 m of a
  chamber floor. The equivalent generator-12 shallow results remain unchanged.
- 2,852 sampled density values agree between profiles 12/13 for seed 42; cave
  primitive payloads agree. Profile-13 snapshot roundtrip and distinct cache key pass.
- Existing generator1–5 golden binary compatibility and regional lake layout pass.
- Ten preparation orchestration tests pass.
- Complete seed-42 district creation and fresh-process reopen pass, including
  geometry/furnishings, vegetation, vehicles, residents and chest-content signatures.
  Published slot: resource_mine_42_20261018, selectable in Worlds.cmd.
- A 22.15-second 1920×1080 read-only gameplay check stages viewpoints at the two
  deposits, performs ordinary pickaxe attacks, verifies ore removal, exact inventory
  deltas, tool wear and empty reward inbox. Saves are not changed by the check.

The copper screenshot was inspected: the deposit's color/texture and excavation
are visible, and the gathered item appears in the toolbelt. HUD shows 34 FPS at
capture, so this is explicitly not a performance qualification. The earlier
intermittent frame spikes remain open. Full on-foot traversal was previously checked
on the unchanged seed-1703 mine geometry, not on every seed or this staged route.
Deposits are finite and deterministic; broad geological variety and balancing remain
unfinished. Do not mark the overall world foundation complete from this milestone.
