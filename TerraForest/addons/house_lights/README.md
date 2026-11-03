# Breakable house-light props

Original editable GLBs: caged room lamp, standing pitch torch and freestanding cast
iron fireplace. These are objects, not building-block assemblies. The existing
building grid and approved building geometry are unchanged. See `PROVENANCE.md`.

## Ownership and performance

- `catalog.gd` admits shared GLB meshes and bounded data definitions through the
  existing trusted runtime-module registry (`world_light` capability, API 1).
- Native model placement, collision, durability, ordinary salvage and compound
  saves own each object. Breaking one removes its mesh and light; reloading does
  not repopulate it. Existing saves are not automatically furnished with lights.
- `NativeResidentLights` maintains four real shadowed point-light nodes shared by
  the world. Source objects remain ordinary native batches, including far models.
  There is no light node or GDScript tick per placed prop. Native selection uses
  the collections' spatial groups, 512 candidate visits and 512 cell visits per
  update, at 10 Hz. Dense groups continue with cursors rather than restarting.
- Eight provider types and eight pooled lights are hard API limits; production
  uses three providers and four lights. Light range is at most 16 m, admission
  radius 24 m, with a 6 m energy fade and retained-source preference. Removal or
  residency loss is checked on active identities every frame. Disabled means no
  processing. Large/nonstandard collection transforms can remain unavailable.
- Flame surfaces are original GPU-animated shader materials applied to their GLB
  surfaces. No per-object particle scene, animation player or clock update.
- Generation surveys supported room regions in native code, closes personnel-door
  openings for room separation, excludes one-cell ledges/passages and caches plans
  by actual cells plus attachments. Candidate work is bounded to 200000 probes and
  128 rooms per prefab. Publication caps at 2048 props, checks real native support
  and block/model occupancy, and respects spawn, vehicle, sleeper and quest space.
  Unsafe positions are reported, never forced through existing content.

## Packs and authoring

Use the existing explicit `user://mods/enabled.cfg` trusted module mechanism.
Manifests register `world_light` providers with a unique module/provider identity
and a bundled `res://...` definition path. No automatic folder scanning or hot reload.
Enabled executable packs are trusted code, not a sandbox.

Definitions follow the three shipped JSON examples: unique persistent `asset`,
`name`, relative self-contained rigid `mesh` GLB, local `bounds` and light `offset`,
HTML `color`, positive `energy`/`range`, integer `health`, impact `material`, material
`costs` and no-greater `salvage`. Meshes must fit their declared bounds. The existing
GLB reader limits each asset to 16 MiB, 32768 vertices, eight surfaces and embedded
images only; skins, animations and external URIs are rejected. Native derived LODs
are shared. Keep authored unit scale for qualified room placements.

Run `tools/author_house_lights.gd` in headless Godot to reproduce the original GLBs.
It also bakes shared native mesh resources and LODs, recording the GLB checksum.
Built-in runtime loading uses those resources because Godot remaps GLB files in
exported games; startup does not re-import or regenerate their LODs. Source GLB
changes reject a stale bake. External GLB packs must retain raw GLB bytes, e.g.
through `PCKPacker.add_file`, rather than supplying only Godot's remapped scene.
The `TerraForestFlame` material name opts a surface into the shipped GPU flame.
Changing a definition or mesh requires restart. Do not change a live persistent
asset identity to silently replace an old world's objects.

Qualification and unfinished visual/performance coverage:
[house-light tracker](../../issues/house-lights/README.md).
