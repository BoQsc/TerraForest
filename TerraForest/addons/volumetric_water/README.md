# Volumetric water

One C++ water runtime: `NativeRegionalWater`. `NativeWaterTerrainPatch` samples terrain through its existing worker and revision checks. `lake_world.gd` coordinates publication, UI and compound-world persistence. `NativeLakeCatalog` is a metadata/save compatibility codec, not another water implementation.

The static-lake and basin-network implementations are deleted. Git history retains previous versions; they are not included in the addon or built DLLs.

See [current integration and limitations](../../docs/WATER_GAMEPLAY.md). Square shorelines and opaque shading are unfinished. Functional tests do not establish visual acceptance or sustained 60 FPS.

Build: `python tools/build_native.py --addon volumetric_water --target all`

Actual-world check: `python tools/check_regional_water_world.py`

Cached loading: `python tools/check_water_preparation.py`

Runtime guard: `python tools/run_godot_check.py water_single_runtime --headless --timeout 15 --require "WATER_SINGLE_RUNTIME failures=0"`

License: 0BSD. Uses the pinned Zig and prebuilt godot-cpp toolchain.
