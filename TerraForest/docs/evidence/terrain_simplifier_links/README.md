# Terrain edit follow-through — 2026-10-23

This is a contained native cost correction, **not closure of mining arrival or
the world rewrite**. The new generated checkpoint reproduces the already
documented whole-patch amplification in `TERRAIN_MESH_COST_BREAKDOWN.md`.

The integrated worker trace identifies a still-visible 256 m owner at
`(1280,1024)` during the first held-mining burst. A preliminary 32 m replay did
not represent that job. Replaying the actual coarse owner measures roughly
67–83 ms extraction and 106–136 ms simplification before this change, with zero
page faults during those measured builds. Demand-page prefetch cannot remove
that observed reconstruction cost. It remains necessary to qualify cold reads
separately under residency pressure.

The simplifier now uses timestamped native scratch for adjacency deduplication
and distinct neighbor intersection. It preserves traversal/collapse order, the
manifold link test, geometric rejection, material checks, edit and border pinning.
It does not retain a collapse decision across topology changes. Scratch is four
bytes times the larger input vertex/triangle count, allocated only for actual
simplification and freed before returning. There is no persistent cache, GPU
resource or resident-page limit increase.

## Evidence

- `native_comparison.json`: 60 complete mesh packets are byte-identical against
  pre-change commit `9b451125`. Independent processes use identical compile flags
  and fixtures: generators 1/9/19, seeds 0/42/1703, fresh/cut/add states and widths
  16–256 m. Encoded normals, materials, visibility, triangles and collision data
  are included. This is finite parity coverage, not universal topology proof.
  Reproduce with `python tools/probe_terrain_link_scratch.py`.
- `before.json` / `after.json`: native coarse-owner replay of the first five
  recorded edit descriptors from each saved-world burst. Every packet hash
  matches. Successful page-fault time is measured only with native profiling
  enabled; zero fault time does not mean zero sampling or field work.
- `held_before*` / `held_after*`: actual mounted generated world, read-only,
  1920x1080 fullscreen, 60 FPS cap, two three-second held-input bursts. After the
  change, first-burst capture-to-draw p95 is **211.371 ms**, maximum visible gap
  **283.908 ms**; second-burst p95 is **78.987 ms**, maximum gap **176.921 ms**.
  Both gap gates and the first response gate still fail. Frame p99 is
  17.332/17.074 ms, with no frames over 50 ms. Timings are scoped observations,
  not a sustained 60 FPS, thermal, universal speedup or multiplayer result.
  Different held-input throughput also changes later edit sequences, so this is
  not an identical-command comparison; use the native replay for that purpose.
- `checks/`: native independent-world concurrency/cancellation, bounded resident
  storage and reconstruction-cache reuse/regression checks pass. The cache check
  includes the retained 2,176-command workload; it is correctness coverage, not
  qualification of that optional cache for ordinary gameplay. Both debug/release
  terrain libraries were rebuilt with pinned Zig and prebuilt godot-cpp.

The portable comparison observed lower simplification costs, but neither it nor
the in-world check makes rebuilding a whole 256 m owner a bounded local operation.
Do not substitute further micro-optimization or prefetch for that requirement.

## Required continuation

Arrival must establish locally replaceable render/collision ownership without
waiting for repeated whole-parent reconstruction. Reuse the existing native owner
work rather than introducing another mesher. Its optional renderer is not
automatically qualified for production: preserve join/topology/material/lighting
and distant edited terrain, then pass the unchanged 150 ms held-input response
and visible-gap gates with measured owner/draw/resource costs. Large authored
history and unsaved pressure remain separate required cases. The world generator,
storage and workflow requirements in `WORLD_WORKFLOW_REDESIGN.md` remain active.

Retained non-passes: the first `terrain_native` wrapper required a completion
marker that the successful test did not print (exit 0, no diagnostics); a marker
was added. The first full reconstruction-cache regression exceeded its 30 s
wrapper limit after successful checks; it was not reported as a pass. Original
logs and manifests are retained under `retained_failures/`. Both held-mining
failures remain failures, including the post-change run.
