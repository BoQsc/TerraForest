# Finite water spatial queries

2026-10-11. NativeWaterNetwork.probe uses the same tetrahedron selection and
barycentric density interpolation as NativeLakeVolume. It resolves the regional
storage owner and settled component level, rather than extruding a water column
through solid terrain. Query cost has bounded region validation (at most 64), a
region map lookup, four density samples, and a topology binary search; no geometry
rebuild or simulation step is triggered. Dictionary allocation and worst-case query
throughput are not performance-qualified.

76 network checks pass in debug and clean release. Added checks cover both region
interiors, the boundary ridge, exact water surface and air above, invalid coordinates,
depth, busy/stale rejection, drained versus filled caves, and solid cave roofs.
The first cave test used y=3.5, above its actual settled level 3.47112676 m; corrected
the test point to y=3.25 after inspecting both component levels (no solver change).
Shared-helper regression water_shallow_source and actual water_network_terrain pass.

This is a query API, not terrain-edit remapping or a playable bucket. Main-world
lakes remain static. Conserved remapping, runtime scheduling/rendering, save/item
transactions, unloaded boundaries, interpolation accuracy and sustained 60 FPS
acceptance remain open. No new dependencies or license changes.
