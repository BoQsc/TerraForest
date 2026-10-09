# Cooperative native model-region admission

The dense-region pressure test found that synchronous restore processes every
placement in one main-thread call. `NativeStaticBatch` now offers a separate
cooperative admission API, retaining the existing TFMR/TFSI storage formats.
It is not yet connected to automatic world paging.

## Contract

All calls belong on the collection's owning/main thread. Only one admission
may be active per collection. Configure render streaming or collision-only mode
before starting; legacy unbounded rendering is rejected.

1. `begin_region_admission(bytes)` validates bounded headers, asset identity,
   unavailable region version and count. It retains the immutable/COW packet and
   reserves the ordered-ID buffer, up to 800 KB for 100,000 placements.
2. `advance_region_admission(max_records, max_hash_bytes, max_usec)` advances
   checksum validation, record installation or rollback. Allowed limits are
   1-1,024 records, 1-262,144 hash bytes and 1-2,000 microseconds. Hash chunks are
   at most 64 KiB. Invalid limits leave work pending. The record and byte limits
   are hard work-count limits; elapsed time is cooperative, checked between
   operations, not a hard real-time guarantee.
3. Inspect `region_admission_stats()`: `active`, `result`, `error`, `phase`,
   `staged_records`, `step_records`, `step_hash_bytes`. Terminal results are
   `complete`, `failed` or `cancelled`. Phase values are 0 outer hash, 1 inner
   hash, 2 records, 3 rollback; -1 means inactive.
4. `cancel_region_admission()` requests rollback. Continue advancing until
   inactive before attempting another admission or a full replacement.

Both nested SHA-256 checksums must pass before installation. Each record validates
its sorted positive ID, finite nonsingular transform, region ownership, available
reservation and derived bounds. Reservations move into the staged group one at
a time; logical capacity includes both installed-but-hidden and unloaded IDs.
A late validation failure returns every moved reservation during bounded rollback.

The unavailable region remains authoritative throughout installation. Partial
records are hidden from public ID/transform queries, collision/render indexes
and full snapshots. Partial storage capture excludes staged records and retains
the complete unavailable disk-region reference. Unrelated loaded-region edits
continue normally. Mutating staged IDs, full snapshot/metadata replacement,
synchronous region transfers and render-mode reconfiguration are rejected while
admission is active. Collision/vegetation queries retain unavailable bounds.

Bounds and ordered render IDs are accumulated with the records. Final publication
moves prepared containers into the live indexes; it does not reserialize the
packet or rebuild all region bounds. Existing render/proxy admission then handles
GPU buffers and physics objects. Publication emits the normal change signal and,
like raw `restore_region`, creates a history barrier. For editor streaming, use the journal-owned wrapper described below to retain
unrelated undo/redo.

`resident_instances` excludes staging; `staged_instances` reports it explicitly.
Transform-byte counters include staged allocations because that memory exists.
Reserved-ID counts include staged identities until publication.

## Evidence, 2026-10-09

[Raw debug/release reports and build hashes](evidence/model_incremental_admission/)
retain every measured step. Both variants pass 42 correctness checks: exact
100,000-object publication, hidden partial state, save representation, unrelated
editing, cancellation/retry, reserved-ID protection, late malformed-record
rollback, both checksum failures, empty regions, and subsequent render/physics
admission. Existing release region/history tests pass 58 checks; metadata tests
pass 27.

| Variant / operation | Calls | p95 call us | p99 call us | Maximum call us |
| --- | ---: | ---: | ---: | ---: |
| Release dense success | 562 | 335 | 621 | 1,900 |
| Release late failure plus rollback | 955 | 270 | 643 | 2,540 |
| Debug dense success | 563 | 688 | 849 | 1,632 |
| Debug late failure plus rollback | 954 | 596 | 1,092 | 3,224 |

The fixture requests 256 records, 65,536 hash bytes and a 500 us time target per
call. Dense begin took 67 us release / 39 us debug. The separate 2 ms wall-time
gate FAILS in both variants because of rollback tails; reports mark qualification
false and the script exits 2 when correctness passes but timing fails. Do not
retry until a favorable sample replaces this evidence. Scheduling and allocation
can exceed a cooperative deadline; the measurements do not establish the cause
of these individual tails.

Run from the repository root:

```text
python TerraForest/tools/test_native_release.py --godot <engine.exe> --addon structures --test model_incremental_admission
```

The release wrapper returns nonzero for either correctness or timing failure.
These are short headless CPU tests, not 1080p graphical or thermal qualification.
The debug sample overlapped the separate metadata regression for part of its
execution and is not an isolated performance comparison with release.

## Remaining integration and limits

- No automatic scheduling is enabled. The world coordinator must budget all
  collections together, including retained packet/staging memory, cancellation,
  priorities, history ownership and pending archive results.
- This bounds work per admission call; it does not guarantee fast arrival. At
  exactly one test-sized call per 60 Hz frame, 562 calls would require about
  9.4 seconds before the entire dense region becomes available. This is an
  arithmetic illustration, not a measured streaming latency. Prefetch and/or
  smaller independently usable pages are needed for high-speed travel.
- Snapshot capture, metadata installation and storage saves remain synchronous.
  Cold records now have [cooperative retirement](MODEL_INCREMENTAL_RETIREMENT.md);
  legacy synchronous unload remains for explicit non-runtime use. Disk workers
  alone cannot remove the remaining main-thread costs.
- Render and collision candidate selection still traverse region contents.
  Cooperative record installation does not qualify those subsequent operations.
- Destruction releases the collection's state normally; it is not a bounded
  runtime eviction primitive. Drain cancellation while the collection remains
  live when cleanup must share a frame budget.
- The implementation is project-owned 0BSD C++ and uses the pinned prebuilt
  godot-cpp SDK; no new third-party dependency or license was introduced.

## Journal-owned admission

`NativeStaticHistory` now wraps the same bounded admission engine:

- `begin_region_admission(collection, packet)` returns a positive generation
  ticket, or 0 on rejection. The collection must be registered, and the region
  must not be referenced by retained undo/redo records. Header inspection is
  bounded; the existing incremental validator still checks the packet contents.
- `advance_region_admission(collection, ticket, records, hash_bytes, usec)`
  returns the admission status plus `accepted: true` when ownership and ticket
  match. Otherwise it returns `accepted: false` without advancing work. Advance
  the same ticket until `active` becomes false.
- `cancel_region_admission(collection, ticket)` requests bounded rollback;
  continue advancing through the journal until it terminates.

Only the owning journal can advance or cancel an owned transfer. Raw callers,
other journals and stale tickets are rejected. Tickets increase per collection
and remain visible in the batch's admission statistics after completion. A
completed ticket cannot replay publication. There is no extra thread or duplicate
record staging in the wrapper.

Unrelated journal edits, undo and redo may execute between steps. On successful
publication, the owner updates its revision cursor before emitting the change
signal; both history stacks survive. Reentrant journal commands are blocked
during the notification. External raw edits during that notification still create
a history barrier, as they do for existing synchronous transfers. Cancellation
and validation failure leave the journal stacks unchanged unless an independent
external edit invalidates them.

Journal reconfiguration is rejected while it owns a live transfer. Collection
and journal ownership use weak Godot instance identities: freeing a collection
does not leave a permanent configuration lock; freeing its journal allows raw
advancement or cancellation again. Finishing such an orphan through the raw API
has ordinary raw history-barrier semantics. A coordinator should normally cancel
and drain before discarding its journal rather than depend on orphan recovery.

This completes the native history-preserving admission wrapper, not automatic
world paging or its performance qualification. The recorded density gate above
remains failed; no graphical or thermal claim follows from this integration.

Journal integration evidence: [reports and binary hashes](evidence/model_admission_history/).
Debug and release each pass 31 checks, including undo/redo between steps,
publication notification ordering, cross-journal exclusion, stale tickets,
cancellation, checksum failure, external-edit barriers and orphan recovery.
Existing release transfers/history pass 58 checks. The raw admission regression
passes 42 correctness checks but again fails the 2 ms gate: dense success reached
4,939 us and failure/rollback 2,297 us in this run. Preserve this variation alongside
the earlier measurements; no performance improvement or timing qualification is
claimed for the journal wrapper.
