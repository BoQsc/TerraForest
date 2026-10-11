# Shared water surface corners

One regional water runtime, unchanged authoritative storage format and quantities. Surface corners average only face-connected wet cells within the same vertical layer. Cardinal shared openings determine connectivity; mere diagonal contact does not. Internal walls between joined exposed surface cells are omitted. Exterior sides use the reconstructed edge. Changes at regional X/Z corners dirty the diagonal region as well as face neighbours.

Four native release assertions cover continuity across two regions, no internal wall, exact state preservation, and isolation across a solid diagonal gap. The actual-world mining/bucket/cache round trip passes all 34 assertions. Current screenshot is still a visual acceptance failure: shorelines and transitions between vertical cell layers remain visibly discrete. Reconstruction is derived geometry, not a change to the fluid solver; gameplay queries still use stored cell intervals. The largest possible reconstruction offset within one layer is bounded by its 0.5 m height, not an exact fluid surface guarantee.

The diagnostic pre-change draining-lake view had 2000 side quads; the final view has 384. These are transient flowing snapshots, not identical simulation ticks. Final maximum native region mesh generation before save was 0.475 ms in this small scene; this excludes Godot upload time and does not establish large-world scaling.

Timing correction: GPU mesh readback was removed from face counting. Counts now travel with the native mesh result. Screenshot GPU readback plus PNG encoding costs 812-839 ms and is explicitly measured outside gameplay frame statistics. Earlier screenshot-induced stalls are not evidence of runtime water simulation latency. Final measured gameplay frame p50/p95/max: 16.666/16.895/40.320 ms. Screenshot reads 60 FPS after capture recovery. This does not establish sustained 60 FPS or old-laptop thermal suitability.

Run/shader/native hashes are in run.json. No alternate water implementation is included.
