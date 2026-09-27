# Vegetation addon

This addon does not depend on the terrain addon. It accepts caller-owned chunks with stable integer tree IDs and uniform-scale transforms. Enable the plugin for the `VegetationWorld` editor node, or instantiate its script directly.

```gdscript
const Vegetation = preload("res://addons/vegetation/vegetation_world.gd")
var forest = Vegetation.new()

func _ready():
    forest.camera = $Camera3D
    add_child(forest)
    if forest.initialize() != OK:
        return
    var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3.ZERO)]
    forest.upsert_chunk("orchard/0", PackedInt64Array([1]), transforms)
```

`upsert_chunk(owner, ids, transforms) -> bool` validates all input before replacing an owner. IDs must be unique within and across owners; transforms must be finite, orthogonal, right-handed and uniformly scaled in [0.05, 10]. `root_limit` defaults to 16,384 and is checked before mutation. `remove_chunk(owner)` unloads one owner. `clear()` releases all roots, cell nodes and selection events even if no camera is assigned. Node teardown frees GPU resources with the scene.

The node must stay at identity world transform because transforms and camera positions use world coordinates. Camera projection is perspective with vertical FOV (`KEEP_HEIGHT`), matching the demo. The facade updates the renderer and material uniforms; do not also tick its internal renderer yourself.

`remove_roots_in_bounds(bounds) -> int` removes roots from intersecting spatial cells while preserving other roots' owners and LOD/fade state. Removing a visual root does not persist a gameplay action; persistence belongs to the caller or terrain coordinator.

Defaults: 448 m draw distance, 128 m shadow reach, wind 0.3. `sun_direction` points toward the sun. The renderer uses source geometry close up, fitted layered view proxies in the middle, and silhouette proxies far away. Visual and shadow transitions share stable per-tree state. Ordinary camera movement updates changed instance rows rather than rebuilding complete batches.

The included source loader is specialized to the supplied spruce asset (6,592 triangles, two surfaces, fixed proxy bake metadata). Replacing the six textures alone does not create a new compatible species. Multiple species and an arbitrary-asset authoring/bake pipeline require further work. Trees are render/shadow objects; add your own gameplay collision policy.

Only compact current assets are included. Historical comparison view textures are intentionally omitted; `set_previous(true)` on the internal asset object is unsupported. Reference renderer scripts are retained for regression testing and are not loaded during ordinary play.

The `data` directory must be included in exports. The root project provides an include filter for `*.bin,*.565,*.r8,*.trtex,*.gdshader,*.gdshaderinc`; use it in other projects too. Do not add a `.gdignore` to `data`. Raw texture bytes are decoded through FileAccess so exported imports cannot silently replace their format.
