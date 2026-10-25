# Volumetric water

One C++ water runtime: `NativeRegionalWater`. `NativeWaterTerrainPatch` samples terrain through its existing worker and revision checks. `lake_world.gd` coordinates publication, UI and compound-world persistence. `NativeLakeCatalog` is a metadata/save compatibility codec, not another water implementation.

The bucket now uses a 16,700-triangle Blender-authored metal pail with embedded
PBR maps. `bucket_model.gd` supplies its cached pickup mesh; the character rig
uses separate hinged pail/bail meshes, a fixed overhand grip and supported
scoop/pour animations. Visible fill follows the gesture after confirmation. Water
transactions remain in the existing native path. See
[bucket source/rebuild](../characters/authoring/Human.bucket.README.md).

The static-lake and basin-network implementations are deleted. Git history retains previous versions; they are not included in the addon or built DLLs.

See [current integration and limitations](../../docs/WATER_GAMEPLAY.md). Depth-aware transmission now resolves the nearest surface, removing repeated water-face tinting. Stepped shores and smaller geometry discontinuities remain unfinished. Functional tests do not establish visual acceptance or sustained 60 FPS.

Build: `python tools/build_native.py --addon volumetric_water --target all`

Actual-world check: `python tools/check_regional_water_world.py`

Cached loading: `python tools/check_water_preparation.py`

Runtime guard: `python tools/run_godot_check.py water_single_runtime --headless --timeout 15 --require "WATER_SINGLE_RUNTIME failures=0"`

License: 0BSD. Uses the pinned Zig and prebuilt godot-cpp toolchain.

Connected surface cells share corners across region and adjacent height-layer boundaries; see [current rendering evidence and limitations](../../docs/evidence/water_layer_compositing/README.md).

The same regional cache now retains terrain samples for clipped shore geometry. [Shoreline evidence](../../docs/evidence/water_shore_clipping/README.md) records cache migration, correctness checks and remaining representation/performance limits.

Bucket targeting and shallow depth queries now share the native shoreline clipper with rendering. [Interaction evidence](../../docs/evidence/water_shore_interaction/README.md) includes actual-world mouse input and remaining limits.

Generator 18 adds a first coastal inlet using this same native store. The two-triangle
horizon beyond the western map boundary is presentation only, not navigable or
editable offshore volume. Coastal boundary configuration must be set before mesh
publication. See `docs/evidence/coastal_inlet` and `docs/WORLD_FOUNDATION_STATUS.md`
for tested scope, resource counts and remaining ocean-streaming work.
