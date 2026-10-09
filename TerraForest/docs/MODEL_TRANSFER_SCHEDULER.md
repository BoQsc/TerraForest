# Shared native model transfer scheduler

`NativeModelTransferScheduler` connects the world archive's strict checkpoint
reads to history-owned incremental admission and retirement. It schedules multiple
model collections with one aggregate scene-thread work budget. Native focus
selection and an explicit scene-adapter lifecycle are available; the default
game scene does not yet activate them.

## Ownership and use

1. Configure a `NativeRegionWorldArchive`, start its shared read service, and
   configure the existing `NativeStaticHistory` with the intended collections.
2. Call `configure(archive, history, max_jobs, max_bytes)` on the scheduler.
   Limits are 1-64 jobs and 5,600,232-134,217,728 reserved packet bytes.
3. Register each asset/collection with its persisted checkpoint. Up to 256 assets
   may register. A live collection has at most one scheduler owner. Registration
   reserves a checkpoint lease; a strict read still verifies existence/content.
4. Request `(asset, region, expected_digest, retire, priority, epoch)`. Positive
   tickets identify accepted jobs; 0 rejects invalid, duplicate or over-budget
   work. Priority is 0-255, higher first. Epoch must equal the current focus epoch.
5. Once per scene frame, call `tick(records, hash_bytes, usec, operations)`, then
   `poll(max_results)`. Defaults: 256 records, 65,536 hash bytes, 500 microseconds,
   eight scheduler operations. Results include ticket, asset, region, epoch,
   operation, outcome, error and whether cancellation was requested.

Records/hash bytes/operation caps are aggregate across collections, not multiplied
by asset count. A tick visits at most 64 queued jobs and advances each at most once.
Higher-priority jobs go first; equally prioritized jobs rotate by last service.
Strict priority can starve lower priorities under continuous higher-priority work.
The archive itself remains FIFO once requests have been submitted. Existing disk
I/O cannot be preempted. Rendering, collision, block paging, and unrelated world
work are outside this model-transfer budget.

The time budget is a **soft deadline**, checked before steps and passed as the
remaining time to the transfer. Allocation, history synchronization, publication
callbacks, destruction and OS scheduling can exceed it. Hard work counts are not
a promise of a hard execution-time ceiling. No additional worker threads are used.

Worst-case packet space is reserved for every accepted job, including queued and
unpolled finished jobs. The archive's independent I/O reservations also apply.
This conservative accounting is not process RSS: collection placements, ID/index
containers, renderer/proxy memory and parser scratch remain separate allocations.
Completed results hold no region packet; callers must poll to release job slots.

## Cancellation and lifetime

`set_epoch(new_epoch)` cancels older jobs. `cancel(ticket)` cancels one job. Queued
and reading jobs terminate without scene mutation; active admissions roll back
through subsequent bounded ticks. Before retirement commits, cancellation keeps
the resident records. After commit, bounded record cleanup must finish; the result
is `complete` with `cancel_requested=true`, not a fictitious rollback. A newer
admission can be requested once that job has finished. History-pinned or active
render/collision regions reject retirement using the existing batch guards.

Ticket-specific archive `take_model_region_read(ticket)` consumes only the named
completion. `discard_model_region_read(ticket)` removes pending/completed work or
marks the active model read for discard when it returns. Both use the existing
reservation and checkpoint-reference accounting. An in-flight disk call is not
interrupted. Other consumers must also use ticket-specific polling when sharing
the model completion channel; bulk polling intentionally consumes all results and
must not be used concurrently with the scheduler. Block results remain separate.

Normal shutdown calls `stop()`, then continues ticks/polls until no jobs remain,
then unregisters collections. It does not stop or join the shared archive worker.
Exceptional scheduler destruction drains owned rollback/committed cleanup
synchronously to avoid leaving a live collection locked under its editor journal.
That destruction path is not frame-budgeted: use explicit draining at runtime.

A checkpoint lease is shared with the weakly registered collection. Unregistering
or destroying the scheduler does not release the backing version of a still-live
unavailable collection. Destroying that collection releases its final lease. A
replacement scheduler can adopt the same checkpoint. Rebinding to a different
checkpoint while unavailable records still rely on the previous one is rejected
by registration; the validated `refresh_checkpoint(asset)` path below supports
handover after a successful save. All-resident detached
collections can release their lease. The archive must remain acquired while those
versions are needed: explicit archive release invalidates all retention guarantees.

Scheduler mutation is scene-thread-only and rejects reentrant changes during
publication callbacks. Collections are weak IDs, so destroying a collection does
not leave a dereferenceable stale pointer. The supplied history remains external;
the scheduler never resets or reconfigures the user's undo/redo journal.

## Saved checkpoint handover

`NativeRegionWorldArchive.published_model_index(asset, after_revision=0, retain=false)`
returns sorted region keys, checksums, checkpoint and the publication revision.
Block and model notices become visible under one lock only after the compound root
is committed. A rejected save leaves the previous notices unchanged; release clears
them. They describe saves published by this archive instance, not a disk-load index.
With `retain=true`, the notice and a `lease` handle are acquired atomically against
cleanup. The caller must release that handle with `release_read_checkpoint`.
Retention pressure or active cleanup returns an empty result and can be retried.

`refresh_checkpoint(asset)` uses that atomic retained notice. It rejects pending,
active or unpolled jobs for the asset and any active collection transfer. Every
unavailable region must appear with the same checksum in the new committed index.
Failure releases the candidate lease and leaves the previous binding intact. Success
replaces both collection and scheduler leases, retaining the new version before
releasing the old one. Resident edits after the save are allowed; later retirement
still checks exact saved bytes and history/render/collision eligibility.

This is a scene-thread operation over at most 4,096 region entries per collection,
not a frame-budgeted sweep over all assets. No scene-thread file I/O is added. The
future coordinator must invoke it at a drained per-asset save boundary, retry
backpressure, and manage collection registration and focus selection. Default game
paging is not activated by this API. See [handover evidence](MODEL_CHECKPOINT_HANDOVER.md).

## Native focus selection and scene lifecycle

`select_focus(world_focus, load_radius=384, unload_radius=512, max_scans=64,
max_usec=250)` rotates through assets and their unavailable/resident bounds using
persistent ordered-map cursors. It examines at most the requested number of
entries/empty-collection visits, subject to a soft deadline, and queues work under
the existing shared job/byte limits. Nearby admissions have higher priority than
cold retirement. Radii are collection-local after transforming the world focus;
the default world uses identity collection transforms.

Both render and collision focus follow selection. Unavailable bounds include
prototype extent; resident selection merges visual and collision bounds. Work
outside the retained radius is cancelled, while small camera motion does not
invalidate all jobs. History and active rendering prevent retirement selection;
the native transfer guard additionally protects collision proxies. Failed regions
have a 120-selection-call retry delay, cleared by successful checkpoint handover.
Scene-thread statistics expose selection visits, queued requests and elapsed time.

Selection performs an additional bounded pass over at most 64 existing jobs for
cancellation. Its deadline is soft; this is not a hard timing guarantee or a
spatial-tree nearest query. Discovering a destination can require a complete cursor
pass as region/asset counts grow. Dense discovery/arrival latency needs a targeted
scale check before default activation; the small lifecycle fixture does not qualify it.

`structures_world.gd` now supplies these opt-in support methods:

1. `enable_model_paging(archive, history)` registers saved collections with a running
   shared archive service and the existing editor history. Unsaved new assets wait
   for their first committed save.
2. `step_model_paging(focus)` selects and advances native work, polls results and
   reports failed transfers. GDScript does not scan regions or placements.
3. `drain_model_paging()` pauses selection and cancels old jobs with a new epoch.
   Continue stepping until `drained` is true before capturing a save or replacing
   world state. Draining is idempotent and does not discard editor history.
4. After successful publication, `resume_model_paging()` validates/adopts checkpoints
   and registers newly saved assets. On failure it remains drained for caller handling.
5. For reload/shutdown, `finish_model_paging()` unregisters only after draining.
   Restore the new scene state and enable again as needed. Exceptional destruction
   retains the scheduler's synchronous cleanup fallback.

The normal game command/autosave/shutdown paths still need to call these barriers;
do not enable metadata-only default startup before that integration. Run the short
`model_focus_paging` release test for the scene-adapter route. Debug/release each
pass 24 checks for multi-asset travel, exact edits, history pins, partial saves,
new asset registration, reload and lease cleanup. [Evidence](evidence/model_focus_paging/).

## Targeted evidence and remaining gates

The short correctness fixture covers two collections, shared queue/packet/work
limits, priority, history protection, unrelated undo/redo, partial admission
cancellation, committed retirement cancellation, stale epochs, callback reentrancy,
read cancellation, foreign metadata results, destroyed collections and retained
checkpoint ownership across scheduler replacement and later saves.

The separate pressure fixture uses two 100,000-record regions. Fixture creation,
snapshot capture and save are outside measured scheduler ticks. It checks exact
round-trip bytes and aggregate counters, and reports timing failure separately
from correctness. These are headless tests, not rendered 60 FPS or thermal tests.

Run with `tools/test_native_release.py --addon structures --test
model_transfer_scheduler` or `--test model_scheduler_pressure`, supplying `--godot`.
Raw reports/build hashes are in [evidence](evidence/model_transfer_scheduler/).

Initial release pressure result: all 17 correctness checks passed; 3,078 ticks,
p95 560 microseconds, p99 880 microseconds, maximum 4,235 microseconds. The 2 ms
observation gate **failed**. Retirement took 1,932 ticks and admission 1,146 ticks.
At one tick per 60 Hz frame those counts would imply roughly 32.2 and 19.1 seconds,
respectively, if per-tick progress stayed the same. That is not qualified arrival
latency; this dense-case result remains evidence against claiming streaming ready.
The fixture's actual elapsed times were 13.3 s and 7.9 s at its headless scheduling
rate, which must not be presented as game-frame arrival times.

The earlier small correctness run also observed a 5.364 ms release tick (and a
preliminary debug run 2.230 ms). Preserve these outliers; subsequent faster samples
do not establish stability. Automatic focus selection, metadata-first scene
installation, version handover after dirty saves, renderer/collision selection
costs, and dense transfer latency/tails remain unfinished. This change provides
shared bounded work scheduling, not runtime GPU savings or large-city qualification.

The implementation is project-owned 0BSD C++ using the pinned Zig/prebuilt
Godot C++ SDK. No save format or licensing changes were introduced.

Final scheduler correctness runs pass 42 checks in debug and release. Observed
maximum ticks were 7.413 ms debug and 0.303 ms release in those runs; the earlier
release outliers remain retained. Existing release regressions pass 71 archive
reader, 34 checkpoint retention/provenance and 31 history-admission checks. The
pressure test's 2 ms gate remains failed. Its build identity and the small final
cleanup-accounting change are recorded in `pressure_build_context.json`.
