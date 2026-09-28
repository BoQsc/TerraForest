# Existing-model transform controls

The model tool now selects an existing physics-resident model by stable ID and
offers world-axis position increments, world-up rotation and uniform scale.
Every action uses `NativeStaticHistory.update`; native storage, validation,
rendering, collision, exclusion and persistence paths are unchanged. No native
DLL rebuild was necessary for this UI integration. The tool retains one selected
collection/ID and renders one amber overlay; it does not scan placements.

`tests/structure_world.gd --gpu` passed **118 checks** in Godot 4.7.2 Steam using
1920×1080 fullscreen, full render scale and the GTX 1060 Max-Q. Added checks
exercise actual editor input handlers for selection, half-metre translation,
quarter-turn rotation, 10% scaling and Shift fine-height adjustment. They verify:

- Stable selection and exact native placement ID after transformations.
- Compound save invalidation without changing terrain density.
- Bounded collision admission followed by a physics ray resolving the same ID.
- Player-intersecting movement rejected without mutation or a history entry.
- Four transform undos restoring exact original transform and compound snapshot.
- Selection invalidation on undo and even byte-identical collection reload.
- Re-selection and explicit Q return to placement.
- Transform callbacks reject edits while loading/focus disables authoring.

The earlier main-world block/prefab authoring, tower, collision, vegetation,
history and travel checks also passed. The new transform screenshot was inspected:
the amber selected object, active ID, history counts, buttons and hints are visible
without clipping. Evidence is in `evidence/model_transform/`.

This is discrete single-object editing, not a complete CAD-style editor. There
are no drag handles, numeric transform entry, multi-selection or per-axis scale
yet. Inter-object/terrain overlap and unsupported placements remain allowed;
player protection uses the existing conservative native proxy tests. The short
graphical test makes no new FPS, dense-city or endurance claim.
