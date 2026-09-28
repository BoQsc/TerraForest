# Compound collision for static architecture

Native static placements now accept up to 32 authored box parts on one physics body. This preserves architectural openings while keeping a single placement identity. Independent resident and per-tick shape budgets bound detail as well as object counts. The single-box API remains supported through the same implementation.

The reusable doorway model and its collision metadata are generated together from two posts and a lintel. Its merged visual surface remains spatially batched like any other model. The main world registers the asset before sealing its persistence registry; snapshots continue storing IDs/transforms and resolve geometry from the application asset registry.

## Validation

Run `tools/validate.py --test static_placements`, `tools/test_native_release.py --addon structures --test static_placements`, and `tools/validate.py --test structure_world --gpu`, supplying `--godot PATH`. Build both native variants with `tools/build_native.py --addon structures --target all`.

The placement suites pass 98 checks in debug and release. New checks cover shape-limited residency/publication, a clear doorway aperture, all parts resolving to one stable ID, character passage and post obstruction, invalid or impossible budgets, the 32-part cap, caller-array isolation, restoration and removal/destruction cleanup. Existing scaled geometry, private physics-world, 100,000-placement and repeated-travel cases remain covered.

All 69 integrated world checks passed. The test places the doorway on an independent static-model platform, checks all three parts, casts through the opening while excluding the player, and moves the actual world player through it. Graphical tests use 1920×1080 exclusive fullscreen, full render scale, Godot 4.7.2 Vulkan Forward+ on GTX 1060 Max-Q. Reports and inspected imagery are retained in [evidence/compound_collision](evidence/compound_collision).

## Scope

This is authored box composition, not arbitrary concave triangle collision, automatic convex decomposition or climbable-ladder behavior. Each resident placement owns its part shapes; shape counts bound resources but do not measure total physics memory or CPU time. Admission uses conservative union bounds, which may prioritize an object while the focus is inside its opening. Pending and deferred objects have no collision. Global multi-collection budgets, predictive high-speed loading, model-placement UI, city-scale performance and long-duration endurance remain unfinished.
