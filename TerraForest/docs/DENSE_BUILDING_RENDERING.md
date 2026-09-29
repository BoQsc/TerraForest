# Dense building rendering and cached upload batches

Returning to a fully cached district previously uploaded only one chunk per
frame. In the retained fullscreen fixture this took 4.267 seconds for 256 chunks,
even though no worker baking was required. Native cached publication now fills
a bounded per-frame batch. The same view returned in 0.536 seconds (32 frames,
about eight times faster), without rebaking or changing authored cells.

## Native upload policy

`NativeBlockWorld.configure_mesh_uploads(chunk_limit, byte_limit, time_limit_us)`
sets the policy. Defaults are eight meshes, 512 KiB of vertex/index payload,
and a 1,500 microsecond soft elapsed-time threshold. Accepted ranges are 1–16
meshes, 64 KiB–8 MiB, and 100–5,000 microseconds. Invalid configurations leave the
current settings intact. The former one-mesh behavior remains selectable.

Elapsed time is checked between calls, not enforced by interrupting the engine.
A first oversized mesh may publish alone so byte limits cannot permanently
starve it. A fresh worker completion is counted in the same frame's budget.
The worker is never waited on in `_process`; cold baking still uses its existing
single-job pipeline. Collision admission retains its separate one-piece budget.
`flush_bakes()` remains an explicit offline operation outside frame budgeting.

`streaming_stats()` exposes configured limits, last/high mesh counts and bytes,
oversized-frame count, and last/maximum native upload-stage time. The stage
includes publication, cache selection and worker submission; it excludes
residency refresh, collision work, GPU execution and presentation.

Material construction now fills native RGB buffers instead of calling engine
pixel setters 65,536 times. All four 128×128 layers and every mip level match
pre-change SHA-256 references in `tests/fixtures/block_material_tiles.json`.
This reduces API calls, but the recorded cold-start spike was not resolved.

## Measured fixture

`tests/dense_building_render.gd` places sixteen twelve-storey tower prefabs and
eight cottages: 80,160 authored cells, 256 mesh chunks and 91,096 triangles. It
uses the main world's 384-cell view radius, 256-chunk / 64 MiB mesh limit and
32 MiB bake cache. All district chunks fit without deferred or budget-blocked
geometry. Actual mesh payload was 8,447,392 bytes; cache capacity 9,952,768 bytes.
The scene includes shadows and the showcase's separate static props.

Both retained graphical runs used Godot 4.7.2, Vulkan Forward+, GTX 1060 Max-Q,
1920×1080 fullscreen and full rendering scale. These are individual matched
fixture runs, not repeated statistical performance trials.

| Measurement | Before | After |
| --- | ---: | ---: |
| Cached return readiness | 4,267.078 ms | 535.515 ms |
| Cached return frames | 256 | 32 |
| Cached return frame p95 | 17.141 ms | 17.274 ms |
| Cached return frame maximum | 18.359 ms | 18.717 ms |
| Stationary frame p95 (240 samples) | 17.089 ms | 17.342 ms |
| Street travel frame p95 | 17.161 ms | 17.245 ms |
| Street travel frame maximum | 33.019 ms | 33.401 ms |
| Cold readiness | 4,434.779 ms | 4,477.822 ms |
| Cold frame maximum | 167.611 ms | 195.635 ms |

The final cache-return native stage peaked at 1.3262 ms, with at most eight
uploads and 422,144 payload bytes in a frame. It reused all 256 cached chunks.
Cold native publication still peaked at 33.5717 ms; first-frame GPU/engine work
is not isolated by these timings. Cold readiness and rare frame spikes need
further work. VSync-capped intervals do not establish GPU headroom or prove
physical scanout is tear-free.

The graphical fixture passed 18 checks, including exact texture/mipmap hashes,
full district coverage, cache reuse, per-frame budgets, byte-stable authored
state, nearby collision completion and distant physics/mesh release. Native
structures tests now cover configurable upload bounds and oversized cached
meshes progressing alone; the release suite passed 291 checks. Clean extraction
repeats the headless district checks, which do not verify pixels or presentation.
Reports, logs, native hashes and the before/after images are retained in
`evidence/dense_building_rendering`.

This scene excludes terrain, forest, cell-region paging, multiplayer and vehicle
simulation. The 30 m/s street path is an authoring camera, not a vehicle or player
collision test. Building LOD, large-city combined-world testing, persistent bake
caches and multi-hour endurance remain unfinished.
