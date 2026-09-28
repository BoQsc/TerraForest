# Native static-model render residency

Static model collections previously allocated a MultiMesh buffer for every
authored spatial group. They now optionally admit nearby render pages in C++,
with separate ceilings for resident page count, resident transform payload,
pages uploaded per process tick and transform payload uploaded per tick.
The main world enables this mode for its registered model assets.

All authored placements and mesh resources remain in RAM. This change releases
derived MultiMesh nodes, buffers and GPU slot mappings during travel; it does
not implement disk regions, geometry LOD or an aggregate city asset budget.
The existing 100,000-placement and 4,096-page limits still apply per collection.

## API contract

`configure_render_streaming(enabled, radius, batch_limit, byte_limit,
uploads_per_tick, bytes_per_tick)` validates the entire configuration before
changing state. Radius is finite, 0–16,384 collection-local units; page limit
is 1–4,096 render pages; both payload budgets are 48–4,800,000 bytes; uploads are 1–64 per
process tick. Both enabled and disabled calls require valid limits. Invalid
calls preserve existing state. Reconfiguration releases old rendering
immediately, ensuring a smaller budget is respected without an over-budget
frame. Disabling streaming synchronously restores eager rendering.

`set_render_focus(position)` takes a finite collection-local position. Selection
runs after edits/reconfiguration or four units of movement, using four units of
padding. Each candidate uses actual mesh bounds merged across its spatial
group, independently of collision proxy bounds. Nearest bounds win with a
deterministic signed group-key tie break. Pending batches upload nearest first.
At most 4,096 maintained group bounds are scanned and sorted during selection;
unchanged stationary collections do not repeat that work.

Render pages are admission units. Each group is divided by sorted placement ID
into pages of at most 1,024 instances, reduced further to fit the resident and
per-tick payload budgets. A dense group can progressively load across frames.
Pages that exceed the remaining resident payload or page-count capacity are
reported as `budget_deferred`; a smaller final page can fill remaining space.
Changed transforms within a group replace only their affected pages. Membership
changes replace all affected groups' pages. Those pages can briefly disappear
while queued; streaming edits do not bypass upload limits. The eager mode
retains incremental slot updates for small edits. See DENSE_MODEL_PAGES.md for
the implementation and validation that supersede the initial whole-page limit.

`render_stats()` reports authored groups, resident pages/instances/payload,
pending pages, candidate and deferred counts, selection status/count, evictions
and cumulative uploaded transform bytes. Payload accounting uses 48 bytes per
resident transform. It excludes mesh resources, driver allocations, Godot nodes,
map/vector overhead and authored records, and must not be described as measured
VRAM or total memory. Limits apply independently to each collection.

Physics admission, placement IDs, snapshots, journals and vegetation exclusion
continue to use authored data independently of rendering. Entering/exiting the
scene rebuilds/releases streamed rendering. Mesh changes require application
asset reconfiguration so maintained bounds are refreshed. All residency and
authoring APIs are scene-thread operations.

## Evidence

Native placement tests exercise budget enforcement, nearest-group travel,
nonresident edits, resident replacement, restore, rejected configurations,
oversized-group deferral, removal, tree exit/reentry, eager mode restoration,
mesh bounds beyond the origin group, asset reload and collision/exclusion
independence. Fullscreen GPU readback verifies republished transforms.

A 100,000-placement fixture spans 100 groups. Under a two-group/96,000-byte
resident budget and one-group/48,000-byte upload budget, 2,000 transforms are
resident. Twenty end-to-end focus changes remain within those limits and retain
the exact saved snapshot. Clearing the fixture leaves no resident nodes, slots,
payload or authored groups. This demonstrates bounded derived residency, not
full city rendering, total-memory bounds or long-run frame-rate headroom.

Validation on Godot 4.7.2 Steam with the pinned Zig/prebuilt godot-cpp toolchain:
200 placement checks in debug and isolated release; 205 placement checks with
fullscreen GPU readback; 280 existing structure checks; and 148 integrated
world checks at 1920x1080 fullscreen. The world test verifies model eviction
during 900-unit travel, unchanged snapshots and restored rendering on return.
The retained screenshot shows the model editor after a transform edit. It is
not a 100,000-visible-model benchmark. Reports, build hashes and the screenshot
are under `evidence/static_streaming/`. No godot-cpp sources were rebuilt.
