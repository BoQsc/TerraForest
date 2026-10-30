# Door content — schema 1

Doors now use readable definitions for visuals, collision, hinge behavior,
construction, salvage and durability. Built-in and mod doors use the same host
code. This is the first object capability, not a general scripted-object engine.

Start with [the built-in definition](../addons/structures/objects/wooden_door.object.json)
and [the example pack](../mods/example_doors/example.objects.json). The example
reuses the existing simple mesh at 0.8 width, with a right hinge and a different
recipe. No new replacement artwork is included.

## Enable the example

Merge this section into `user://mods/enabled.cfg`, preserving any existing
`[modules]` vehicle settings:

```ini
[objects]
manifests=PackedStringArray("res://mods/example_doors/example.objects.json")
```

On a normal Windows installation, `user://` is
`%APPDATA%/Godot/app_userdata/TerraForest/`. Restart after changing content.
The example is bundled but opt-in: installing this code does not add a mod
dependency to existing worlds. The second door appears in the normal object
construction catalog and uses ordinary E interaction and dismantling.

For an external pack, copy its directory into `user://mods/my_doors/` and use
`user://mods/my_doors/my_doors.objects.json` in the same list. An editor export,
PCK or gameplay script is not required. There is no automatic directory scan,
hot reload, executable script field or native extension field in an object pack.

## Replace a visual with a supplied GLB

Put a self-contained `door.glb` beside `replacement.objects.json`:

```json
{
  "schema": 1,
  "id": "my.door_visuals",
  "objects": [],
  "replacements": [
    {
      "id": "architecture/wooden_door/v1",
      "visual": {
        "source": "door.glb",
        "offset": [0, 0, 0],
        "rotation_degrees": [0, 0, 0],
        "scale": [1, 1, 1]
      }
    }
  ]
}
```

Enable that manifest in `[objects] manifests`. GLB paths are relative to the
manifest's directory and cannot escape it. Buffers and textures must be embedded.
`builtin:wooden_door` is the explicit alias for the existing mesh; arbitrary Godot
resources/scripts are not loaded from loose packs.

The original door occupies X=0..1, Y=0..2.2, Z=-0.07..0.07 metres, with the hinge
at the origin and Y up. Supply **the moving leaf only**: a frame included in the
same GLB would rotate with the leaf. Use visual offset/rotation/scale to align
an asset whose authoring origin differs. These transforms are baked into the
shared visual and never change saved placement transforms or collision.

Replacements accept only `id` and `visual`. They retain the original object's
identity, hinge, collision, recipe, health and interaction permissions. Two
replacements targeting the same ID are an error, not a hidden load-order rule.
A replacement must follow the pack that defines its target. Invalid enabled
content fails startup with a `Door content:` diagnostic; it does not silently
substitute a different model.

## Add a door type

Copy the example's complete object into your pack's `objects` array and assign
a unique stable ID such as `my_pack/doors/front/v1`. Its definition contains:

| Field | Meaning |
| --- | --- |
| `schema` | Definition schema, currently 1. |
| `id`, `name` | Persistent identity and human-readable catalog/HUD name. |
| `visual` | Built-in mesh alias or relative GLB, with optional visual transforms. |
| `collision.position`, `collision.size` | Positive-size box in local metres, independent of render geometry. |
| `behavior.type` | `hinged_door`. |
| `behavior.pivot` | Local hinge position; rotation is around local Y. |
| `behavior.opening_degrees` | Signed angle, magnitude 1..170 degrees. |
| `behavior.zombie_breakable` | Explicit permission for the existing zombie door attack behavior. |
| `recipe`, `salvage` | Integer quantities keyed by brick, wood, concrete or metal. Salvage cannot exceed construction inputs. |
| `durability.health`, `durability.material` | Maximum health and damage class: wood, stone or other. |

Opening is an immediate native transform update, matching existing doors; GLB
animations are not played. Static nested mesh parts are consolidated at startup.
New art does not automatically add interaction behavior: the definition does.

## Saves and compatibility

- The existing ID `architecture/wooden_door/v1`, `door_hinges` save section,
  default pivot/dimensions, exact quarter turn and v1 hinge bytes are preserved.
- Each additional type has its own native state and deterministic save-section
  key. Placement ID 7 in one type is independent of ID 7 in another.
- Old saves without the new type restore it empty. Compatible visual replacement
  does not migrate or rewrite object identities or placement poses.
- Non-default hinge packets include bounds, pivot and angle. Changing these
  under the same ID rejects the saved packet instead of moving an old open door
  incorrectly. Use a new versioned ID for incompatible definitions. The legacy
  v1 packet is accepted only by the original geometry/hinge profile.
- A world containing an unavailable model type is refused by the existing native
  structure validator. The terrain persistence loader disables writes on this
  failure, preserving the original file. Re-enable the required pack to open it.
  Missing-content substitution and automatic migrations are not implemented.

Keep names/recipes/balance stable for published type versions too; this first
schema does not migrate historical health or construction economics.

## Runtime and import limits

Definitions are read once before collections are sealed. Loose GLBs import once
per unique visual in a catalog, using native Godot import/merge/LOD generation.
There is no runtime import during walking or door interaction and no node/script
per placed door. Existing native placement, streaming, collision, undo, durability
and snapshot stores remain authoritative. Hinge occupancy checks use bounded
native swept-box extrema, including intermediate angles, at interaction time.

Admission limits: 16 door types total, 16 manifests, 64 KiB per JSON manifest,
16 MiB per GLB, 256 GLB nodes, 32,768 referenced vertices, eight source surfaces,
four embedded images at up to 2048², and a visual bounds diagonal at most 32 m.
Collision sides are at most 8 m; origins/pivots are within 16 m. Visual scales
must be positive. Apply mirrored transforms before GLB export. Skinning, morphs,
animations and non-triangle geometry are rejected. These are admission limits,
not a claim that every maximum-sized pack meets world performance targets.
Texture decoding precedes the decoded-size check; this is not an asset sandbox.

The shipped example has no new GLB. Tests create disposable box geometry only.
User-supplied replacements still need licensing/provenance intake and visual
alignment review. See [CONTRIBUTING](../CONTRIBUTING.md) and the original-data
[provenance](../addons/structures/objects/PROVENANCE.md).

## Verification

See [door evidence](evidence/door_content/README.md). Checks cover actual old
native save packets, independent same-numbered IDs, visual replacements,
fresh-process persistent terrain/model/hinge save/reopen, native collision,
construction/HUD/durability/salvage integration, and 10,000 native placements.
The box GLB fixture is importer coverage, not approval of future supplied art.
