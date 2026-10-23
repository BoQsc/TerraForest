# Generation lifecycle: live progress and safe regeneration

2026-10-23. This continues the [bounded unpublished generation mechanism](../terrain_generation_staging/README.md).
It changes lifecycle and observability, not terrain geometry, water behavior,
world units or license. Runtime authoring stays native; GDScript coordinates
the job and UI. Both native libraries use pinned Zig and prebuilt godot-cpp.

## Implementation

- The loading screen exists before planning. The shared native-backed plan and
  resource recipes run on a worker, with an exact digest comparison against the
  same cold and cached plan. No second mutable world representation is added.
- Offline terrain baking waits for explicit admission after scene/UI setup. This
  is generation-only: ordinary load/save startup retains its existing behavior.
  Cancelling a waiting job releases the gate and performs no terrain I/O.
- Native command/checkpoint boundaries publish one atomic 64-bit observation.
  UI reads do not acquire the terrain mutex. Counters identify completed commands,
  total commands, durable checkpoints and applying/checkpoint/terminal state.
  The UI polls every 100 ms and records details in the existing progress file;
  it never invents a whole-job percentage. Cancellation text stays visible.
- A bounded test argument interrupts the existing native product publisher before
  an intermediate index is published. Production uses its default disabled value.
  Failed generation discards unpublished in-memory edits and exposes no final
  checkpoint reference. Existing immutable private products remain retained.

## Targeted and integrated evidence

| Check | Observation | Limit |
| --- | --- | --- |
| `generation_bake_progress` | 2,112 commands, 89 checkpoints, 256 resident-page bound; 435 coherent active observations; maximum observed getter 357 microseconds; reset returns idle | Finite synthetic native job; getter timing is an observation, not a real-time guarantee |
| `generation_bake_failure` | Publisher interruption after 48 of 80 commands; three prior checkpoints remain valid; no final reference; partial in-memory world discarded; fresh staging regeneration exactly matches ordinary authoring | Controlled product/index boundary, not hardware I/O failure |
| `generation_admission` | Waiting live worker performs no I/O; one admission starts it; duplicate admission rejects; stopping a waiting worker returns promptly with no world products | Explicit generation gate only |
| `generation_plan_worker` | Cold worker plan equals cold reference and cached worker digest; 24 main-loop frames during the observed 349.889 ms cold plan | Headless main-loop liveness, not graphical FPS qualification |
| Actual production interruption | Verified Windows child terminated after three completed private checkpoints; all three validate in a fresh inspector; coordinator fails without public world; same public name regenerates under a different private owner and passes full verification/publication | Child process termination, not physical power loss; regeneration rather than resume |
| Source creation/reopen | Actual 367-command coastal connected-world job shows live road counters; fresh full game reopens read-only at 1920×1080 with all four baked map layers hitting cache | Smaller rendered world has 479 authored pages; not the synthetic capacity case |
| Exported creation/reopen | Export and smoke check pass; actual packaged coordinator creates and verifies the world; fresh packaged game hits all four map caches; canonical SHA-256 remains unchanged on read-only reopen | Installed Steam Godot plus external DLL package; not clean-machine installer qualification |

Existing staged generation, cancellation and async-save regressions also pass.
Raw check manifests/logs are in `checks/`. The finite physical interruption record
is `generation_interruption.json` and `interruption/`; the source and package
creation/reopen directories retain commands, status, engine logs and pictures.
`build.json` records native/source/package hashes. Timings were collected during
development and are not controlled comparisons or hardware-independent budgets.

The exported package is 250,060,048 bytes with 14 external native DLLs. The observed
creation job took 62.242 seconds; fresh full-game reopen took 14.664 seconds in the
host runner. These are workflow checks, not a claim of acceptable final loading time.

## Visual review

Inspected `source_generation/generation_planning.png`,
`source_generation/generation_loading.png` and
`pack_generation/generation_baking.png`. The early screen uses an honest plain
background before a world photograph exists. The live baking capture displays
23 / 367 completed road/foundation commands. Once a real photograph exists it
becomes the loading background; the image excludes gameplay HUD/hands. Screenshot
readback is opt-in qualification work, outside runtime performance measurements.

This accepts the demonstrated loading presentation only. Repeated box-like
buildings, draft landscape and the rejected northern district remain unaccepted
under `WORLD_BUILDING_STANDARD.md`. These lifecycle changes do not add new world
content or certify final generated-world quality.

## Retained unsuccessful attempts

`retained_attempts/` preserves the first observer failure, inspector parse failure
and the pre-admission successful crash case. The first observer incorrectly used
Godot's Windows `OS.is_process_running` on the coordinator's child. That API checks
only the calling engine instance's process map in the
[Godot Windows implementation](https://github.com/godotengine/godot/blob/master/platform/windows/os_windows.cpp).
The replacement host holds a Windows process handle and verifies parent PID and
executable before termination. The next attempt reached the intended interruption
but its inspector script failed to parse; neither attempt is counted as a pass.

The pre-admission case passed crash/regeneration but missed live road progress:
native baking finished during scene construction. The explicit generation gate
fixes that ordering. The accepted case then observed 0 / 367 before admission
and 33, 126, 198 and 294 during native authoring. Exported graphical capture also
shows live native progress. No failed check was hidden by lowering its assertion.

## Required continuation

- Retention/compaction needs canonical, backup, in-flight capture and active-reader
  ownership first. Return with interrupted collection, corruption/backup recovery
  and measured storage growth. No private product cleanup is implemented here.
- Broader physical power-loss/disk-full coverage needs a deliberate storage-fault
  environment and root/backup verification. Valid private prefixes here do not
  establish that qualification. Partial-bake resume is not implemented; the
  demonstrated recovery path is explicit fresh-owner regeneration.
- Rendered populated history beyond the old cap, long unsaved pressure, cold
  storage admission and bounded local mining publication remain open. The failed
  first-visible mining gate in `terrain_simplifier_links` is unchanged.
- Complete POI/options/map planning, measured compute benefit, world visual
  acceptance, clean-machine packaging and sustained 60 FPS/older-laptop thermal
  qualification remain required by `WORLD_WORKFLOW_REDESIGN.md` and the current
  `WORLD_FOUNDATION_STATUS.md`. These checks do not complete the large rewrite.
