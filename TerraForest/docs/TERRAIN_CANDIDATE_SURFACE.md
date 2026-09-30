# Combined CPU surface build

`experimental/region_surface.hpp` adds one synchronous world-backed entry point
for geometry and matching normals. It owns their buffers, carries owner coordinates
and the source world revision, and returns a ready result only when both stages
succeed. Any failure or cancellation discards both stages' output. Default
constructed results are not ready. No engine resources are constructed here.

The World must remain immutable for the entire call. The revision is provenance,
not synchronization; this wrapper does not make concurrent world mutation safe.
The caller's cancellation callback is passed through both stages and checked
again before marking the result ready. A worker integration must also reject
obsolete results at publication, since cancellation can arrive after return.

## Evidence

Run `python tools/probe_terrain_tetra.py`: 54 checks pass. The retained
[report](evidence/terrain_candidate_surface/terrain_tetra_probe.json.gz) includes
a combined 16 m mountain control with exact position/index/normal parity against
separate geometry and scalar-normal builds.

All 27 allocation calls are independently failed, including normal scratch and
output allocation after geometry succeeds. Each returns allocation_failed with
no partial surface and no tracked live buffers. Success retains exactly the three
output buffers and destroys them normally. Cancellation at callback 1, 9,632 and
9,633 covers initial rejection, normal completion and final readiness; each
returns empty cancelled output. A fresh build then succeeds.

## Remaining integration work

This is a CPU geometry/normal result, not a complete terrain render packet. Material
attributes, collision cooking, renderer upload and staged publication remain
unconnected. Existing cave/partition tests exercise the underlying stages, but the
combined fault control uses one mountain owner. Mixed LOD, normal-halo edits,
integrated latency, fullscreen visual checks and long-run behavior remain open.
The experimental headers are still outside the game extension.
