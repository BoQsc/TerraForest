# Native finite-water scene publication

2026-10-11. NativeWaterScene is a Node3D adapter for a compiled, settled finite-water
network. begin_publish(network, material) stages native regional surface builders
and MeshInstance3D resources under a hidden group. advance(work_budget) performs
bounded builder work, uploads at most one regional mesh per call, then publishes
all staged regions with their matching depth/occupancy queries. _process provides
automatic budget-128 advancement and stale-state visibility checks; callers may
disable processing and drive the same API through a scene scheduler.

Published water is guarded by geometry ownership and the water mutation counter.
refresh hides stale meshes, and depth_at/probe refuse stale data immediately.
The eventual world scheduler must call refresh at mutation/invalidation boundaries;
the per-frame check alone does not guarantee zero stale frames when another node
mutates water later in that frame. Pending scene publication has no query authority.
If it becomes stale, it is cancelled and its hidden resources retire. Identity world
transforms are required because mesh vertices and queries use world coordinates.

Old groups hide before replacement publication. At most one regional node or final
empty group is queued for deletion per advance call. New publication is refused
until retirement drains, preventing an unbounded replacement backlog. Actual Godot
GPU uploads, deferred deletion, and builder destruction have indivisible costs;
worst-case frame/thermal behaviour remains unqualified. Main-thread-only scene use
is required. Idle scenes perform cheap version checks, not mesh rebuilds.

277 network checks pass in debug and clean release, including scene publication,
matching immersion depth, invalidation hiding, replacement, idle mesh work=0,
staging cancellation and separate retirement of two old region meshes plus group.
The actual TerrainCore excavation/placement test publishes the scene using the
existing water shader and verifies the existing water_camera.gd enters and exits
immersion while restoring the previous Environment.

A brief fullscreen render check ran at 1920x1080 with a 60 FPS cap. The inspected
scene_1920x1080.png shows the actual finite-water cavity surface and the hole where
solid material displaces it. Terrain rendering is deliberately omitted and labelled
in the screenshot. This verifies basic shader visibility and presentation, not
terrain integration, visual polish, frame-rate sustainability or thermal performance.
The initial camera test ran before SceneTree entry and was corrected to deferred
execution before accessing global camera coordinates.

## Still open

Main-world static lakes are unchanged. Native compilation/sampling must join the
existing terrain worker scheduler; state, meshes, queries and terrain publication
need a common world transaction. Persisted quantities and item/bucket transactions,
static-lake migration, streaming, unrouteable displacement handling, retirement
budgets and performance acceptance remain incomplete. This adapter is an actual
scene component, but the main game is not yet using finite water. Original code
remains 0BSD; the existing shader adds no extra render pass.
