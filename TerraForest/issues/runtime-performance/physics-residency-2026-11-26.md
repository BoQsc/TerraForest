# Physics and corpse residency — 2026-11-26

Status: scoped runtime fix verified and committed as `271e577f`; broader frame
pacing remains open. Scope: the latest `Hidden_Meadow` save, two hotspots from the human capture,
current source checkout, Godot 4.7.2 / Jolt / Forward+ on RTX 4050 Laptop,
1920×1080, VSync and 60 FPS cap. This is a repeatable grounded workload, not a
reconstruction of unrecorded human inputs or proof of 60 FPS headroom.

## Diagnosis

The broad physics-tail interval includes deferred scene work. Instrumenting
ragdoll construction identified 26 measured corpse admissions in the baseline:
17.164 ms mean / 22.962 ms maximum spent entering ragdoll mode. Shape installation
accounted for 13.145 ms mean; discovering joint properties through reflection
accounted for another 3.132 ms. Skin sampling itself was cheap. Installing dense
convex clouds into physical bodies and constructing finger compounds dominated
shape preparation. These calls ran together in a deferred callback.

Corpse residency separately spent 0.633 ms per frame recursively visiting scene
nodes to freeze detached bodies. The detached groups are siblings of the zombie,
so that scan did not even reach the intended bodies. Readiness queries averaged
0.133 ms; they did not justify weakening or caching collision-coverage decisions.

The removed-body transform error had a concrete lifetime gap: severing removes a
physical bone from the tree immediately, but its ObjectID remains resolvable until
deferred deletion. Native pick/wake/pose queries treated object existence as world
residency. The baseline reproduced that error through structural invalidation.

## Changes

- `Zombie.set_simulation_available` owns suspension for living actors, corpses,
  and their explicit detached segment groups. Repeating an unchanged state does
  no traversal. New detached groups inherit the state. Suspension keeps bodies
  and joints registered, records authoritative velocities, and tolerates a limb
  being removed before resume. Population admission and developer spawning use
  the same state transition.
- A single authored passive joint definition serves initial creation and
  death-pose rebinding. This removes property-list discovery without changing
  joint limits, translation locks, damping, mass or neighbor collision exceptions.
- Saved-corpse residency has a pending preparation phase. Known missing anatomy
  is removed before shape cooking. One pending corpse prepares its exact posed
  hulls in 1.5 ms target slices, then publishes the complete connected ragdoll to
  physics, rendering and loot together. One engine hull installation is atomic
  and can exceed that target; this is not a hard 1.5 ms deadline. Coverage loss,
  leaving the residency radius, reset and capacity pressure cancel the pending
  object. Its original saved record remains authoritative while pending.
- Native spatial and support queries use a shared live-body check, excluding
  removed and queued-for-deletion nodes. Sampling an out-of-tree rig returns no
  geometry. Corpse joints, support-loss waking, CCD and physical contact remain.

The active cap of 12 corpses, 80/96 m admission/retirement radii, population,
readiness checks, simulation rate, rendering settings and collision point clouds
are unchanged. Live combat deaths still activate immediately; only restoration
from saved residency uses preparation slices.

## Evidence

All measured legs use 600 physics ticks: idle, outward and return at each site.
Setup teleports are excluded. Walking uses the ordinary player motor with flight
disabled. Site 0 travels 54.451 m each way. Site 1's outward movement encounters
the same obstacle at 6.656 m; the return travels 54.431 m. The input seed, saved
world SHA-256, six endpoints and end-of-leg living/corpse counts match exactly
in the first candidate and final diagnostic repetition. This checks observed
route outcomes, not every AI or rigid-body state.
The original save hash is verified after every run; loading is temporary and
read-only. No save copy, export, reduced population or simplified geometry is used.

| Metric | Instrumented baseline | First candidate | Final diagnostic repeat |
| --- | ---: | ---: | ---: |
| Recorded frames over 60 simulated seconds | 3,532 | 3,590 | 3,585 |
| Frame p95 | 20.694 ms | 19.330 ms | 19.667 ms |
| Frame p99 | 27.204 ms | 22.061 ms | 22.272 ms |
| Frame maximum | 46.935 ms | 41.873 ms | 34.126 ms |
| Frames over 33.333 ms | 29 | 1 | 1 |
| Physics-tail maximum | 24.194 ms | 8.070 ms | 9.417 ms |
| Corpse suspension, mean per frame | 0.633 ms | 0.0076 ms | 0.0079 ms |
| Corpse update, mean per frame | 0.832 ms | 0.280 ms | 0.284 ms |
| Ragdoll preparation CPU work, mean | 17.164 ms | 10.641 ms | 11.136 ms |
| Largest preparation slice | one whole transition | 5.826 ms | 11.982 ms |

Preparation now contributes to the measured corpse-update phase; previously its
deferred work was outside that phase. Its p99 therefore cannot be compared alone
as total corpse cost. Mean elapsed preparation-to-publication was 73.382 ms,
maximum 104.528 ms in the first candidate (77.006 / 105.058 ms in the final repeat),
versus the baseline's single-frame transition. This is an
explicit admission-latency tradeoff, while the arrival cadence remains one new
corpse per 0.5 seconds and final populations match.

[Baseline run](../../reports/checks/20261125T223636357760Z/run.json) ·
[baseline summary](../../reports/checks/20261125T223636357760Z/physics_summary.json) ·
[first candidate](../../reports/checks/20261125T225702746543Z/run.json) ·
[candidate summary](../../reports/checks/20261125T225702746543Z/physics_summary.json) ·
[final repetition](../../reports/checks/20261125T231712786293Z/run.json) ·
[final summary](../../reports/checks/20261125T231712786293Z/physics_summary.json).
The baseline harness remains failed because of the reproduced transform error;
its route and unchanged-save assertions passed. Both matched candidate harnesses
pass. The final repeat uses committed runtime source/binaries and adds a bounded
identity event journal: 25 events, zero deaths. Retirements during measured legs
were living state-1 actors at 96.00–96.07 m; setup teleports account for the others.

An intervening [candidate repetition](../../reports/checks/20261125T230950928619Z/run.json)
passed engine/save assertions but **failed workload equivalence**: site 0 returned
with four living actors and eleven corpses instead of five and ten; site 1 also
had one fewer living actor. Its p99 was 22.509 ms, maximum 43.316 ms and two frames
exceeded 33.333 ms, but it is excluded from the matched comparison. All 27 recorded
ragdolls were staged saved-corpse restorations; an extra corpse does not establish
a death. That run lacks identity events, so its individual retirement cannot be
reconstructed. Existing awareness seeds its random stream from transient scene
instance IDs (`zombie_awareness.cpp:add_agent`); seeded player input alone is not
deterministic AI replay. Streaming/readiness timing can also change admission.
The final diagnostic run was added to observe this, not to remove actors or force
population counts. Future general replay needs stable actor random streams and
state checkpoints. The analyzer continues to reject the mismatched run.

An [earlier baseline](../../reports/checks/20261125T203355108997Z/physics_summary.json)
without ragdoll subphase instrumentation recorded p99 34.524 ms, maximum 53.063 ms
and 36 intervals over 33.333 ms. This variation limits claims from short capped
runs; the instrumented baseline above is the closer causal comparison.

Final regression results:

- [Lifecycle: 16 assertions](../../reports/checks/20261125T230355533675Z/console.log):
  point-for-point hull/finger-compound equality, joint parameters, missing anatomy
  before cooking, no partial collision, idempotent suspension, frozen motion and
  space membership, removal while suspended, sibling ownership, safe removed-node
  queries and cancellation on readiness/radius loss.
- [Restore cost](../../reports/checks/20261125T230417045664Z/console.log): three
  missing-anatomy patterns use the real staged path with no discarded debris.
- [Geometry cache: 30 checks](../../reports/checks/20261125T230444307749Z/console.log),
  [rest/support: 33 checks](../../reports/checks/20261125T230511459340Z/console.log),
  and [ragdoll reactivation](../../reports/checks/20261125T230612209544Z/console.log)
  pass, preserving push/contact response, connected constraints and support waking.
- Both debug and release native outputs match their source build signatures;
  the incremental editor import passes and generates both new test UIDs. The first
  extended lifecycle fixture had a `ready` name collision with Node's signal
  ([failed log](../../reports/checks/20261125T230257268457Z/console.log)); renaming
  the fixture property resolved it before the final sixteen checks.

## Reproduction and retained evidence

```powershell
python tools/run_godot_check.py physics_residency_world --godot <Godot.exe> --isolated-render --timeout 300 --require 'PHYSICS_RESIDENCY failures=0'
python tools/analyze_physics_residency.py reports/checks/<baseline> reports/checks/<candidate>
```

The route defaults to `Hidden_Meadow`; `-- --residency-source=SLOT` selects an
explicit existing save. It records bounded frame cadence and named phases, source
hash, exact route outcomes, identity events and ragdoll preparation work/span. The analyzer refuses
a matched-comparison claim when source, seed or route outcomes differ. The runner
admits 16 MiB before allocation and cold-retains older cadence by receipt after
process exit, keeping two ordinary ready runs plus pins. The analyzer reads and
hash-checks cold evidence directly; logs and small summaries stay loose.
It also rejects differences in explicit viewport, physics rate or VSync when
both captures contain those fields. Older captures require settings verification
from the driver/run receipt. Four capture-tool tests and seven shared-runner tests
cover retention ownership, pins, output admission, timing units and drift rejection.
Run those Python checks from `tools/` with
`python -m unittest test_physics_captures test_run_godot_check`; the initial
project-root invocation lacked that module search path and was corrected.

## Limits and rejected experiments

General convex cleaning on each death moved work rather than saving it. Preparing
support vertices by equal skinning-weight cohorts saved too little on this asset
to justify complexity and cold preparation cost. Both experiments were removed;
the exact original posed collision clouds remain. Their diagnostic logs are
retained in check runs `20261125T224405640384Z` and `20261125T225142366593Z`.

The first candidate's remaining 41.873 ms frame was a different mix: 10.788 ms in
physics callbacks, 2.048 ms tail and 22.375 ms draw interval. No corpse restore ran
in that frame. The final repeat still had an 11.982 ms atomic preparation slice:
the 1.5 ms target cannot preempt an engine shape installation. This evidence does not close broader draw/physics variability,
large simultaneous combat deaths, long sessions or lower-end hardware. The
unretained 126/103 ms human spikes still lack detailed attribution. Return with
independently retained worst windows and a recorder-off equivalent route before
claiming global 60 FPS headroom. Arbitrary human input recording/replay and the
normal-exit capture handshake also remain separate work.

Implementation and test additions are original AI-assisted 0BSD work using the
existing engine/native toolchain. No external code, assets or dependency upgrades
were admitted. Source-checkout engineering results are separate from packaged
release qualification and human visual acceptance.
