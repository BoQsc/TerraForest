# Authoritative building picking

The structures addon now queries authored cells directly in C++. Selection no
longer waits for a block mesh or physics bake after placement, removal or travel.
This improves editor interaction; it does not provide predictive player or
vehicle collision readiness.

`NativeBlockWorld.raycast_cells(from, to)` traverses the signed unit grid and
tests cube, slab, stairs, wedge, post and sphere geometry with quarter-turn
rotation. Sphere rendering and ray clipping share the same immutable faceted
template. The result includes local `cell`, `word`, `cell_normal`, world
`position` and `normal`, segment `fraction`, world `distance` and `visited_cells`.
Invalid rays, misses and origins inside solid return an empty dictionary.
Segments are bounded to 256 local units and endpoints to +/-1,048,576 local
units. Traversal has a hard 512-cell ceiling; exact endpoint hits are included.
Call this scene-thread API outside concurrent mutation.

`raycast_scene(from, to, collision_mask=3, exclude=[])` combines the authored
result with one physics query, excluding this world's derived block bodies so
stale geometry cannot intercept a newer edit. Bit 2 enables authored blocks;
the other scene collision remains governed by the supplied mask. Up to 256
caller RID exclusions are accepted. The derived-body exclusion list is bounded
by the existing 2,048-chunk capacity, but its assembly still scales with resident
block bodies. Model and terrain picking still require their physics residency.

Both world block editing and static-model placement use the combined query.
The standalone building editor uses the cell query. GDScript remains input/UI
glue; shape tests and cell traversal run in the native addon.

Debug and isolated release structures tests pass 280 checks, including all
previous structures coverage. New checks compare all six shapes and four
rotations against actual physics triangles, signed coordinates, boundary hits,
empty shape corners, affine frames, removed and unbaked blocks, mesh eviction,
scene occlusion, layer masks, RID exclusions and stale collision rejection.
The release endpoint regression initially failed against an outdated DLL;
rebuilding the changed translation unit and rerunning passed.

Builds use pinned Zig 0.16 and the prebuilt godot-cpp SDK, compiling zero SDK
sources. Reports and DLL hashes are retained in `evidence/block_picking/`.
These are correctness and integration results, not a city-scale ray throughput
or long-run performance claim.

The integrated world test passes 144 checks at 1920x1080 fullscreen and full
render scale. It disables all block collision, confirms both editor tools still
pick the authored support, and verifies newly placed spheres are immediately
selectable before their bake. Terrain density stays unchanged. All four core
addons also pass isolated startup and resource-boundary auditing.
