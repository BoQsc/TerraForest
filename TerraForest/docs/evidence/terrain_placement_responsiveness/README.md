# Terrain placement responsiveness, 2026-10-24

Requested baseline commit: `8249e0c0`. That commit includes the previously pending
work and changes bare-hand reach from 0.72 m to 1.65 m, with unchanged contact
timing and damage. The user has now accepted the subsequent changes described
below as the next baseline and requested committing and pushing them. Roads and
block-grid rules are unchanged.

## Reproduction and correction

The old target cache expired after only 8 cm of aim movement or a slight normal
change. Every expiry required another terrain-worker answer, leaving the marker
amber and rejecting right clicks meanwhile. The retained baseline reproduction
moves the aimed point around a 22 cm radius: **0/60 ready frames, 46 new queries**.
Stationary stacking tests had missed this real interaction defect.

Command39 now samples a bounded 5x5x5 neighbourhood on the existing worker and
returns its empty samples as a **16-byte bitmask** in a 60-byte reply. A shared
native selector examines 27 candidate bits/math operations against that immutable
mask for each new aim. It does not read mutable terrain from the scene thread.
Full neighbourhood coverage, revision, epoch and edit-ticket checks still apply.
Leaving coverage or editing the field requests a new mask, not a fabricated green
answer. Worker queue limits and edit serialization are unchanged.

One explicit placement click can wait up to 1.5 seconds for a cold query or the
previous stamp's publication. Live target, inventory and clearance are rechecked
before payment. Focus/menu/control changes, item/slot/world changes, movement over
15 cm, aim changes over roughly 3.6 degrees or expiry cancel the queued intent.
There is no auto-repeat or unbounded click backlog. Genuine object, vehicle,
player, inventory and streaming constraints remain. Player clearance now tests
the stamp sphere against the player bounds instead of an overbroad box corner.
The compact translucent octahedron and silent invalid-target styling are unchanged.

## Verification

- Native debug and release: 76 checks each; 75 moving point/normal comparisons
  match fresh authoritative selection exactly. Invalid/truncated/occupied masks,
  out-of-coverage queries, stale revisions, four materials and 100 shoulder probes
  are covered. Querying never edits terrain.
- Graphical source: 54 checks pass, including **60/60 ready moving-aim frames and
  zero additional queries**, cold-click submission, five cancellation contexts,
  epoch/revision/ticket invalidation, exactly-once payment, six paid soil stamps
  (including two quick clicks), and a paid grid block atop the added soil.
- Shared terrain planner: 184 checks; mining/rewards: 35 checks; terrain material
  conservation also passes. These do not claim universal world performance.
- Ready and blocked captures were inspected: the translucent marker is exposed,
  and a real obstruction remains red without blocking text. The source stack
  capture is a close overhead material view, not proof of marker visibility at
  that camera position. The final packaged stack capture uses a camera above the
  completed stack; the exposed green octahedron was inspected there as well.
- Export/startup succeeds with 14 external libraries. The exported runtime passes
  all 54 graphical checks and all 76 native checks using external regression
  drivers. Source/package terrain DLL hashes match. `packaged_world/` and
  `packaged_native/` retain pack/test hashes, commands, captures and results.

## Retained failures and limits

`before/` retains the moving-aim failure. `first_cache_attempt/` fixes moving aim
but fails the obstruction fixture because it asserts red before its fresh query
has returned. The fixture now waits for a resolved answer; it still checks actual
obstruction rejection and no debit. `planner_marker_mismatch/` records a runner
failure from requiring `failures=0` when that test prints JSON; all 184 assertions
passed, and rerunning with its actual completion marker passes. A transient file
write failure was retried successfully without truncating the test.

`packaged_report_path_failure/` retains a native test-driver failure after all
assertions passed: its hard-coded `res://reports` destination was not writable
inside the pack. Only that owned test process was stopped. The driver now accepts
an explicit report destination and exits cleanly on a write failure; the packaged
rerun passes. No runtime behavior was changed to accommodate the fixture.

The user accepted this responsiveness correction as the baseline after the
playtest launch; **this is not a claim that terrain building is universally
flawless**. Long aim jumps can still
briefly need an amber query; collision publication and genuine obstruction remain
visible constraints. Broad slopes, cave walls, sustained rapid walking/building,
edited saves and lower-end hardware need further play review. Existing terrain
mesh/contact aesthetics are not resolved by this cache. The terrain-placement
approval prerequisite for the separate road follow-up is now satisfied.
