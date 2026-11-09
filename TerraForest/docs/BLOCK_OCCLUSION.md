# Native building occlusion

`NativeBlockWorld.configure_occlusion(enabled, radius, chunk_limit,
geometry_byte_limit)` adds optional render-only occlusion for its opaque near
block meshes. The component does not enable a viewport or change authored cells,
collision, saves, materials, mesh LOD, shadows or visibility distance. The world
scene enables its own viewport and restores its previous setting on exit;
headless world setup does not enable the component.

The current world policy is 96 m, 128 chunks and 2 MiB of submitted vertex/index
data. Each chunk is limited to 256 KiB. These are geometry accounting limits,
not total RAM limits: Godot's resource and acceleration-structure allocations
require process-memory measurements. Oversized or unadmitted chunks still render
normally. Rendering additional geometry is the fallback when occlusion is absent.

## Ownership and correctness

`BlockOcclusion` is a native adapter owned by `NativeBlockWorld`. It uses the
existing CPU vertex/index arrays at mesh publication, with no GPU readback or
GDScript gameplay scan. The occluder is a child of its source mesh and shares its
transform and visibility. Only the opaque block shader is covered. Model glass,
movable doors, vegetation, dynamic actors and distant replacement meshes do not
become occluders through this component.

The full base-mesh triangles are submitted without proxy boxes or simplification.
Doorways, windows, sloped shapes and destroyed cells therefore retain their actual
openings. Future transparent block materials must explicitly exclude their
triangles before being admitted here.

Cell edits, destruction, snapshot replacement and region transfers use the same
native invalidation hook. It hides affected occluders immediately, including
neighbor chunks whose baked faces depend on the edit. Hidden stale geometry stays
in the accounting until retired. Mesh replacement or eviction removes its entry
before deleting the parent mesh; the SceneTree releases owned resources on exit.
No occlusion data is persisted or sent as authoritative gameplay state.

## Scheduling and observation

Selection runs on mesh/invalidation events or after 8 m of focus movement;
the movement interval permits up to 8 m of selection hysteresis. Candidates are
ordered by chunk-box distance, then admitted within the count and geometry limits.
Each step retires up to four hidden entries and publishes at most one new
occluder. A 500 microsecond soft elapsed budget gates publication; a single engine
call cannot be preempted. The per-chunk limit bounds its input, not its wall time.
`flush_bakes()` drains this queue only for explicit offline/test operations.

`occlusion_stats()` reports resident/active/retiring counts, pending publications,
geometry limits and bytes, selection scans, skipped dense chunks and step timings.
The opt-in rolling gameplay trace records these counters. They supplement whole
frame and process-memory telemetry; they do not establish headroom by themselves.

## Verification

`tests/block_occlusion.gd` covers exact mesh correspondence, independent rays
through an opening, immediate destruction invalidation, region reload, transforms,
forty edit/destruction cycles, disable, admission limits, travel and oversized
fallback. `--occlusion-images` captures an object through an open, closed and
destroyed doorway. The release harness supports the same native fixture.

`tools/check_frame_trace_world.py --short --block-occlusion` compares culling off,
on, on and off in the retained default-world view. It uses native owned occluders
when available, checks that source meshes stay unchanged, and restores viewport
state. The earlier diagnostic prototype constructs exact temporary occluders only
when native occlusion is absent. Construction and screenshot readbacks are outside
the measured phases. `--save` adds a normal gameplay save and clean shutdown check.

See the [runtime-performance evidence](../issues/runtime-performance/block-occlusion-2026-11-09.md) for measured results and remaining acceptance
work. Indoor gains do not establish outdoor, destruction-stress, long-session or
weak-hardware performance. New code and fixtures are original AI-assisted 0BSD;
no external code, asset or dependency was added. The implementation uses the
existing [Godot occlusion API](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html).
