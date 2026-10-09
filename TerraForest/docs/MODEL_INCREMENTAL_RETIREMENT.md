# Cooperative cold-model retirement

`NativeStaticBatch` can now retire an exact saved model region with bounded
validation and record cleanup. It shares the native transfer state machine with
incremental admission. It is not yet scheduled by the main-world pager.

## Eligibility and ownership

Retirement is a record-storage operation for a cold region: it must have no
resident render batch and no active physics proxy. Visible/nearby resources are
not forcibly detached by this API. The renderer and physics residency systems
must release them first. Eligibility uses a render-map lookup and scans the
bounded global proxy pool (configured maximum 4,096 bodies), not every record
in the dense region. A region with 100,000 stored transforms can therefore be
eligible even though none of those transforms has a resident draw/proxy object.

The caller must retain a successfully persisted, exact TFMR packet before asking
for retirement. The batch does not own a store and cannot certify persistence.
The future coordinator must obtain the authoritative version from the archive,
retain its storage lifetime, and handle dirty saves before retiring. Corrupt,
wrong-asset, stale or differently encoded transforms cannot replace live data.
There is no new file format or third-party dependency; the implementation is 0BSD.

## API and transitions

Batch methods:

- `begin_region_retirement(packet)` returns true only when a transfer can start.
- `advance_region_retirement(records, hash_bytes, usec)` advances the job using
  the same limits as admission: up to 1,024 records, 262,144 hash bytes and a
  2,000 us cooperative time target per call. Hash chunks are at most 64 KiB.
- `cancel_region_retirement()` requests cancellation only before publication.
- `region_admission_stats()` is the shared status API. `operation` distinguishes
  `retire` from `admit`; `retiring_records` reports hidden records awaiting cleanup.
  Existing phases 0/1/2 validate outer hash, inner hash and records; phase 3 ends
  cancelled/failed validation; new phase 4 removes retired records.

During validation, the whole live region remains readable. Target-region inserts,
removals and moves are locked, while unrelated loaded-region editing continues.
Full replacement and prototype reconfiguration are blocked. Render/proxy selectors
and queued admissions cannot repopulate the locked target if focus moves back.
The coordinator should cancel an uncommitted retirement when the region is needed
again; cancellation dirties selection so normal residency can resume.

Both nested checksums, sorted IDs, finite transforms and exact live transform bits
must match before publication. Validation does not allocate another map of all
packet records or construct another snapshot. A malformed final record leaves
all original live records intact. Signed-zero differences count as stale data.
An empty-region publication rechecks the 4,096-region capacity after unrelated
edits, rather than relying on eligibility measured at begin time.

Publication moves the existing group and ordered render index into cleanup state,
installs unavailable metadata with the exact packet digest and retained bounds,
and removes the live spatial bounds. It emits one change notification at this
point so save caches and observers immediately see the complete unavailable
region. Public record queries and partial storage capture exclude hidden retiring
records. Collision/vegetation queries retain the unavailable-region bounds.

After publication, cancellation is rejected. Continue advancing until complete:
each record removal transfers its ID reservation and frees its transform. Logical
instance capacity remains conserved throughout cleanup. There is no second change
notification for physical cleanup of already-hidden records. A reload can begin
once cleanup completes. Whole collection destruction remains an ordinary unbounded
lifecycle operation, not a runtime eviction substitute.

## Editor journal

`NativeStaticHistory` supplies matching `begin_region_retirement(collection,
packet)`, `advance_region_retirement(collection, ticket, records, hash_bytes,
usec)` and `cancel_region_retirement(collection, ticket)` methods. Begin returns
a positive generation ticket; advance reports `accepted` and the shared status.
Only the owning journal and matching operation/ticket may advance it. Regions
referenced by retained undo/redo cannot retire. Unrelated undo/redo remains usable
during validation and cleanup and survives the availability publication.

Ownership and reentrancy follow [incremental admission](MODEL_INCREMENTAL_ADMISSION.md#journal-owned-admission).
If the owning journal is destroyed after publication, raw retirement advancement
can finish cleanup; cancellation still cannot undo a published transition.

## Validation, 2026-10-09

[Evidence and binary hashes](evidence/model_incremental_retirement/) retain the
initial and expanded test results. Final debug and release each pass 56 correctness
checks: exact disk round trip for 100,000 records, target edit locks, live reads
before publication, save representation during cleanup, unrelated undo/redo,
stale/corrupt/late-malformed packets, signed zero, empty regions, capacity races,
orphan cleanup, callback reentrancy and independent render/physics eligibility.
The render/physics tests run headless; they prove residency bookkeeping rather
than graphical performance.

| Final dense run | Begin us | Calls | p95 call us | p99 call us | Maximum call us |
| --- | ---: | ---: | ---: | ---: | ---: |
| Release | 31 | 954 | 262 | 403 | 2,967 |
| Debug | 27 | 955 | 258 | 436 | 1,508 |

These calls requested at most 256 records, 65,536 hash bytes and a 500 us time
target. Work-count bounds passed. The release 2 ms wall-time gate FAILS; the
single final debug sample passes that gate but does not establish stability.
Earlier retained retirement maxima include 3,556 us release and 3,524 us debug.
Do not select only favorable runs. Allocation, callbacks and scheduling can exceed
a cooperative deadline; the samples do not identify the cause of individual tails.

Existing release regressions pass 58 region/history checks, 31 admission-history
checks and 42 admission correctness checks. The final admission timing sample
passed its per-run gate; earlier failed samples remain recorded, including a
7,395 us failure/rollback call during this change. Overall paging qualification
therefore remains open.

Run from the repository root:

```text
python TerraForest/tools/test_native_release.py --godot <engine.exe> --addon structures --test model_incremental_retirement
```

A correctness pass with failed timing produces a nonzero exit. Capturing the
packet, persisting it, and the final synchronous reload used to verify bytes are
outside retirement-step timings. These short checks are not an FPS, large-city,
vehicle travel, multiplayer or sustained thermal qualification.

## Remaining work

Automatic paging needs a shared coordinator for priorities, tickets, history,
packet lifetime, memory limits, focus changes, cancellation and cumulative frame
budgets across collections. Bounded calls do not by themselves give acceptable
latency: 954 calls at exactly one call per 60 Hz frame would take about 15.9
seconds; that is an arithmetic illustration, not measured runtime latency.
Scheduling multiple short calls under a shared budget and selecting smaller
independently usable pages remain integration/design work.

Snapshot capture and dirty-save preparation remain synchronous. Existing dense
render/collision candidate selection and their resource eviction behavior also
remain separate costs. This cold-record path neither qualifies those operations
nor fixes their limits by hiding them in a worker. No extra GPU stress or thermal
run was performed for this change.
