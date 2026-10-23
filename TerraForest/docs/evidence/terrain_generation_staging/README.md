# Bounded native generation before world publication

2026-10-23. Production generation no longer requires its entire edited field to
remain resident until the first compound-world save. `TerrainCore` performs the
existing ordered command-28 earthworks in the new private staged bake. It uses
the existing native capture, immutable regional publisher and bounded terrain
pager. GDScript selects/coordinates this native job and carries its private
checkpoint into the first ordinary compound save.

The destination staging directory must be new and the native world pristine.
Generation checkpoints every 64 commands and can checkpoint pending dirty pages
once before retrying a rejected atomic command. It never increases the resident
limit or divides an indivisible edit silently. Every checkpoint is durable before
its samples become evictable. No public compound root is written by this method.
A failed/cancelled bake discards its in-memory field and exposes no final reference;
immutable private products may remain for diagnosis. The coordinator still owns
verification and final root-last world publication.

The expected cancellation epoch closes the race between stopping the worker and
entering the native bake. Cancellation stays nonblocking while that bake holds
the world mutex. Capture/commit/mount share their existing implementations through
helpers used only while that mutex is held; public locking semantics remain.

## Evidence

- `terrain_generation_staging.json`: forty independent grades under a 16-page
  bound trigger 19 checkpoint/retry cycles. Complete field bytes equal the normal
  native bake, including page order, materials, revision and edit counters. Cold
  reopen, subsequent runtime editing/publication, existing-directory and edited
  world protection, late semantic rejection, oversized atomic command and
  cancellation before entry pass.
- `generation_earthworks.json`: complete real coastal world-plan archives for
  seeds 0/42/1703 are byte-identical to ordinary ordered native edits. The staged
  path runs with a 512-page bound. This covers actual generator packets rather
  than only the empty-field fixture.
- `terrain_generation_capacity.json`: **one** native generation call executes
  2,112 grading commands, producing **16,896** authored pages while resident high
  stays at **1,024** (12 MiB density/material samples). Its largest immutable
  sample capture is 9,437,184 bytes. All products verify; fresh mounting under
  32 resident pages retains 34 independently generated distributed hits/normals,
  including the earliest/latest commands. The finite synthetic empty-field case
  measured about 3 seconds; it is not a city, renderer or endurance result.
- `checks/handoff`: actual production `_load`/save/mount/clone paths. First outer
  publication rejection leaves the root absent and dirty samples unacknowledged;
  retry publishes from the private checkpoint. The ordinary loader and cloned
  published destination restore exact staged data plus a later edit.
- `terrain_generation_cancel.json` and `checks/cancel`: a confirmed live native
  bake cancels after at least three private checkpoint files exist, joins and
  discards its unpublished field. The actual backend stop
  path also cancels a confirmed live bake without publishing a partial root.
  That production stop waits until at least two checkpoint files exist. Both
  meet the one-second stop gate. This is not a power-loss/crash test.
- `checks/residency` / `checks/async_save` / `checks/storage_failure`: native cold storage, dirty/atomic-edit
  pinning and asynchronous publication/query/reload/shutdown regressions pass.
- `workflow/`: actual connected coastal seed1703 creation runs all 367 earthworks
  through seven private checkpoints, verifies all addon/terrain sections, then
  publishes the complete world. The rendered generated field has 479 authored
  pages. Creation measured 56.279 seconds, with roughly 0.802 seconds in native
  staged earthworks; this is an observation, not an isolated speedup comparison.
- `source_reopen/`: independent full-game read-only reopening at 1920×1080 with normal
  gameplay succeeds. All four map layers hit their baked caches; zero terrain
  patches are generated for the map. At playable admission, 298/479 authored
  terrain pages are resident. Canonical bytes remain unchanged. The observed
  full check/load took 13.839 seconds, not an instant-loading qualification.
- `pack_workflow/`: the explicit exported PCK's production coordinator and child
  generate, verify and publish a second connected world, again with 367 commands
  and seven private checkpoints. No source script implements generation in this
  case. The observed workflow took 50.830 seconds; it is not a controlled timing
  comparison against the source run.
- `reopen/`: that PCK-created world opens in the full exported game at 1920×1080.
  All four map layers hit cache, map terrain patches remain zero, and canonical
  bytes remain unchanged. The observed script check took 15.233 seconds. External
  test code supplies assertions only; production assets/scripts/libraries load
  from the export. This is same-machine PCK coverage, not release-template or
  clean-machine installer proof. `export.log` / `pack_smoke.log` also retain the
  250,056,672-byte PCK export/startup with 14 external native libraries.

Generation loading and reopened world images were inspected. They establish
integration, not world-quality acceptance. Repeated building recipes, landscape
and access/detail design remain unaccepted. No terrain geometry, vegetation model,
accepted static-water behavior, world resolution or license change is introduced.
Both debug/release libraries use pinned Zig and prebuilt godot-cpp.

The first handoff fixture supplied an invalid plan digest, so configuration was
correctly rejected before generation. Its failed report is retained under
`retained_failures/`; the corrected real SHA-shaped digest then passes. It was not
a failure of first-root publication and the failed setup is not counted as a pass.

`retained_failures/source_to_pack_cache` retains a different cache case: opening
the source-created world in the exported game loads it correctly but misses all
four map caches. `_compatibility()` deliberately hashes source versus remapped
compiled codec payloads, so these are different derived-cache namespaces. The
world and canonical bytes were valid; the cache-hit assertion failed. It is not
reported as a pass or hidden by weakening compatibility. Creation and reopening
within the same exported build subsequently pass with all four cached layers.

## Remaining requirements and return triggers

1. Expose native command/checkpoint progress to the generator UI without taking
   the world lock. Staging boundaries now supply meaningful counters; do not
   invent overall percentages or introduce a competing mutable world copy.
2. Inject storage failure and process interruption during intermediate baking,
   then verify no canonical destination and either explicit safe regeneration or
   validated recovery. Existing store/outer-publication failures are prerequisites,
   not complete mid-bake crash evidence.
3. Collect/compact superseded and cancelled products only after canonical,
   backup, in-flight capture and active-reader ownership is explicit. No automatic
   cleanup of authoritative products is implemented here.
4. Keep rendered populated history beyond the old cap, long unsaved pressure,
   mining arrival/local publication, complete POI/options/map planning, compute
   benefit, world visual acceptance, sustainable 60 FPS and thermal evidence open.
   The native capacity case and smaller rendered world must not be conflated.

The full rewrite remains active under `WORLD_WORKFLOW_REDESIGN.md`.
