# First temperate woodland art pass — 2026-10-11

User selected natural temperate woodland and asked to develop representative
vegetation before further optimization. Main-world ground cover now uses the
original stone/fern-like plant/grass sample documented in
`addons/world_ecosystem/art/README.md`. Old prototype assets remain available for
comparisons. No native binary, population policy, save schema, player inventory
rule or normal launch configuration changed.

Evidence:

- `comparison.png`: previous assets behind, detailed sample in front. Inspected
  after correcting the gallery's initially shared vertical offset, which floated
  the foliage above its platform. Original gallery is retained separately.
- `visual_result.json` and `visual_console.log`:14 checks pass, including finite
  normals/nondegenerate near triangles, interaction-envelope and wind bounds,
  exact near geometry with/without LOD, visible wind and fullscreen1080p cap60.
- `lod_result.json` and `lod_console.log`:28 checks pass using the new assets in
  actual native batches; near screenshots match with wind disabled, expected
  mesh tiers are selected, and placement IDs/snapshot bytes remain unchanged.
- `world_result.json`, `world_console.log`, `world.png`:66 actual-world gameplay
  interaction/exclusion checks pass. This temporary world used a unique derived
  cache and skipped canonical saving. It is not the user's saved settlement.
- Four packaging contract checks pass. Per-run manifests retain Git dirty state,
  engine/test/native hashes and exact commands. New source files are included in
  the resulting commit; the asset source/licensing recipe is in the addon.

The world screenshot HUD reads51FPS. This is a single observation during a
correctness fixture, not a measured frame distribution or a demonstrated cause,
and **does not qualify the60FPS target**. No GPU/CPU/thermal improvement is claimed.
The new meshes deliberately carry more near geometry; their representative
mixed-density cost remains to be measured after visual review.

Remaining visible limitations: one shape per category, thin grass aliasing,
sparse existing distribution, stylized procedural stone texture and preliminary
fern form. Final art, species/biome variants, dense forest-floor placement and
human acceptance remain open. The next decision is visual feedback using the
comparison and existing `Play Combined World.cmd`, rather than another
optimization campaign on unapproved artwork. That human launcher still edits
its existing saved world; this change creates no copy of it.
