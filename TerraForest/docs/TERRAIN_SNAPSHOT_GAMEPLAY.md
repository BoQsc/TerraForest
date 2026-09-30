# Snapshot geometry in the gameplay stream

The opt-in `--snapshot-terrain` launch argument uses snapshot geometry and normals
for 16/32 m patches inside the sampled world. Native conversion adds the existing
block geometry, material weights, sky/sun channels and exact collision faces.
The existing stream prepares collision pieces and publishes edit batches together.
Candidate packets bypass both base and derived geometry caches.

This is an integration step, not an approved default or a completed foundation.
The backend still waits for each snapshot on its existing worker. Native shading
still owns the world mutex. Larger patches retain the old mesher; boundaries
between the two extractors are not qualified. Engine conversion allocations are
outside the snapshot budget. Vegetation preservation and player movement have
not been specifically verified by the checks below.

## Evidence (2026-09-30)

- Both native variants built using Zig and prebuilt godot-cpp; no SDK rebuild.
- 42 adapter checks passed, including stream encoding and stale/malformed rejection.
- 42 real-worker publication checks passed with the candidate enabled: public
  excavation, retained old collision during preparation, replacement physics and
  clean shutdown. This fixed four-region test is headless.
- The existing graphical foundation workload completed at verified 1920×1080
  fullscreen on the GTX 1060 Max-Q, with terrain and forest, 136 scripted edits
  and travel. It **failed five performance gates**. This is one run, not a
  comparative performance claim, visual inspection or endurance qualification.

| Phase | Frame p99 (ms) | Edit p95 (ms) |
| --- | ---: | ---: |
| Baseline | 16.907 | — |
| Compact control | 22.792 | 167.612 |
| Expanding excavation | 19.099 | 201.160 |
| Travel | 17.149 | 434.139 |
| Return control | 17.872 | 136.603 |
| Recovery | 24.147 | — |

No measured phase had a frame interval above 50 ms. This does not establish strict
60 FPS or headroom. The slowest recorded travel patch was the old 256 m rebuild
at (1280,1280), taking 296.039 ms. Bounded local replacement of large edited
patches, with correct coverage and seams, is the next integration requirement.

Raw reports, frame trace and source fingerprints are retained in
`evidence/snapshot_gameplay/`. Run the fixed-cut check with
`tools/probe_terrain_publication.py --worker --snapshot-terrain --godot PATH`.
Run the real scene with `tools/run.py --temporary --snapshot-terrain --godot PATH`.
Run the graphical workload using Godot's `--script res://tests/foundation_mining.gd
-- --snapshot-terrain` arguments from this project.
