# Physics and corpse residency — 2026-11-26

The original scheduling/lifetime result below is preserved. The later
[collision-work follow-up](#collision-work-reduction-follow-up) reduces hull input
while preserving its convex boundary.

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

## Collision work reduction follow-up

Status: scoped collision-work reduction verified on two repetitions of the same
route, including one fully matched route outcome. Exact-input paired construction
uses 20.5–22.8% less CPU including filtering. Global frame headroom remains open.

### Cause and final design

The [subphase measurement](../../reports/checks/20261125T232838023335Z/console.log)
separates sampling, resource setup and attachment to a physics body. A head sent
5,408 points to the hull builder: sampling took 0.096–0.106 ms, resource setup
0.060–0.062 ms, and attachment 4.569–4.624 ms. The engine backend's
[shape construction/cache](https://github.com/godotengine/godot/blob/master/modules/jolt_physics/shapes/jolt_shape_3d.cpp)
and [convex builder](https://github.com/godotengine/godot/blob/master/modules/jolt_physics/shapes/jolt_convex_polygon_shape_3d.cpp)
helped locate the measurement boundary; the run receipts identify the actual
installed engine binary.

The native `convex_cloud.hpp` preconditions dense collision clouds before they
reach the engine hull builder. It selects source support points in 26 directions
and forms at most 48 tetrahedra with their average. An eight-by-eight-by-eight
spatial lookup restricts the candidate volumes examined for each point. A point
is discarded only after a strictly positive barycentric containment test proves
it lies inside one of those volumes. All support points remain. Their average is
itself a convex combination, so every discarded point is inside the retained
cloud's convex hull. Gaps and degenerate cells retain additional points.

This is applied to the actual evaluated pose, including deformations, with no
persistent pose-plan cache. Retained vertices preserve their original values and
order. It changes redundant interior input points while preserving the convex
boundary. Clouds below 1,024 points bypass the search. Normalized double-precision tests,
degeneracy rejection and an interior margin guard against roundoff. The helper
is reusable native geometry code, independent of zombie residency. Shared rest
fits, live death-pose fits and detached-body fits use the same path. Posed finger
compounds, collision margins, body offsets, mass, joints, population and the
existing 1.5 ms scheduling target retain their previous behavior.

### Alternatives tested

The first conservative filter reduced a head from 5,408 to 1,684 points and
attachment from 4.454 to 1.728 ms, but the search cost another 2.190 ms. Repeating
that search consumed most of the saving. [Prototype and 39 checks](../../reports/checks/20261125T233213683452Z/console.log).

An intermediate design cached interior certificates in shared geometry and
revalidated them for each pose. It passed 119 geometry/contact checks and used
65,020 bytes per shared asset. Rest-pose head revalidation took 0.064 ms and
attachment 1.895 ms. However, the actual saved-world route retained an average
3,684 head points, since many original certificates no longer applied to those
poses. Its first geometry/body setup also increased from 11.495 to 13.723 ms.
The [world run](../../reports/checks/20261125T234218035511Z/run.json) passed engine
and save checks but failed route equivalence at one living-population checkpoint.
It is intermediate evidence, not an accepted matched frame comparison.

A denser fresh spatial search reduced saved-world heads to 1,404 points on average,
with 1.254 ms preparation and 1.826 ms attachment. Its maximum preparation slice
was 4.773 ms. The [run](../../reports/checks/20261125T234707256408Z/run.json) again
had a population mismatch; frame p99 was 24.150 ms and maximum 42.291 ms. These
results motivated a smaller bounded search and an exact-input paired measurement.
The retained final implementation removes the pose-plan cache and uses the cheaper
26-direction search. The rejected variants remain documented here.

The first [paired route measurement](../../reports/checks/20261125T235814172383Z/physics_summary.json)
covered 163 actual posed clouds. Head construction fell from 72.739 to 48.175 ms
in aggregate (34%); torso construction fell from 35.131 to 27.392 ms (22%).
These totals include reduction and use each cloud's median of three pairs.
The 256–532 point clouds instead cost 10–31% more. The final 1,024-point cutoff
keeps their original construction path. It is an algorithm-cost decision, with
no change to body counts, mesh assets, collision detail or simulation rate.

### Verification

The final [73 collision checks](../../reports/checks/20261126T002345336432Z/console.log)
reconstruct discarded points from positive retained-point weights and compare
original/reduced engine ray contacts within 0.5 mm. Cases include dense interiors,
boundary-only, planar and collinear clouds, translated/scaled coordinates, newly
exterior points, small inputs, and rest/attack/morphed character poses.
The final planar, collinear and boundary-only fixtures use 2,048 points so they
exercise the filter above its 1,024-point cutoff, rather than only the fast path.

The final [geometry-cache check](../../reports/checks/20261126T000314918390Z/result.json)
measured 1.600 ms shape fitting plus 9.639 ms body attachment (11.239 ms total),
versus 0.518 + 10.977 ms (11.495 ms) in the
[earlier baseline fixture](../../reports/checks/20261125T230444307749Z/result.json).
This is one cold-fixture observation, not a whole-world startup qualification.
The 30 geometry-cache, [16 residency lifecycle](../../reports/checks/20261126T000338747872Z/console.log)
and [saved-anatomy restoration](../../reports/checks/20261126T000401556573Z/console.log)
checks pass.

The route driver additionally retains a bounded in-memory corpus of the exact
posed collision clouds it encounters. After route timing ends, it alternates
original and reduced construction order using fresh resources, three pairs per
cloud. Reduction cost is included. The report stores point counts, cloud hashes
and timings; raw vertices are released without writing a geometry dump. This
allows direct work comparisons even when autonomous AI changes route populations.
It does not convert a mismatched full-world run into a matched frame comparison.

### Final repeatable route results

Both final runs use the same Hidden Meadow save, seed 1703, six 600-tick legs,
1080p viewport, 60 Hz physics and VSync. Both pass the driver, leave the source
save unchanged (`b5c310dba6521eae0219d1cceed7c65022c7178ecf23214e2aca0becd62408ee`),
record 26 ragdoll admissions and zero deaths. The second run matches all recorded
route endpoints and populations. The first has six living actors instead of five
at `site_0_out`; the analyzer rejects full-world equivalence for that run.

| Measurement | Prior residency baseline | Final repeat 1 | Final repeat 2 |
|---|---:|---:|---:|
| Maximum atomic preparation slice | 11.982 ms | 5.234 ms | 4.322 ms |
| Mean ragdoll preparation CPU | 11.136 ms | 9.904 ms | 10.354 ms |
| Frame p99 | 22.272 ms | 23.886 ms | 23.374 ms |
| Maximum frame interval | 34.126 ms | 33.859 ms | 37.372 ms |
| Recorded workload matches baseline | — | No: one population checkpoint | Yes |

[Baseline](../../reports/checks/20261125T231712786293Z/physics_summary.json) ·
[Repeat 1](../../reports/checks/20261126T000420900772Z/physics_summary.json) ·
[Repeat 2](../../reports/checks/20261126T000655907270Z/physics_summary.json).
These are observed slices, not a guaranteed upper bound. Whole-frame p99 did
not improve; the scoped construction result does not establish an FPS gain.

Each final run also compares original and filtered construction of 163 identical
captured posed clouds. The table sums each cloud's median of three alternating
pairs, including filtering, resource creation and attachment, excluding cleanup.

| Paired construction CPU | Repeat 1: original → filtered | Repeat 2: original → filtered |
|---|---:|---:|
| All 163 clouds | 124.668 → 96.214 ms (22.8% less) | 124.366 → 98.847 ms (20.5% less) |
| 13 heads | 66.093 → 43.034 ms (34.9% less) | 65.162 → 44.496 ms (31.7% less) |
| 26 torsos | 28.921 → 23.147 ms (20.0% less) | 29.173 → 23.839 ms (18.3% less) |

The 154,926 total input points fall to 96,732 and 96,750, respectively. Head
inputs fall from 70,304 to about 33,940; torso inputs from 39,416 to about 17,600.
This demonstrates less construction work on the actual encountered geometry,
without shifting that work into later frames or changing collision boundaries.
The paired fixture uses fresh static bodies; the integrated ragdoll measurements
above cover the production physical-bone path and its remaining costs.

Both native build targets pass source-signature checks. Restoring the original
LF source line endings after the playthrough required a rebuild; the executable
`.text` sections are byte-identical to the measured builds. Full hashes and scope
are retained in [the normalization record](../../reports/checks/20261126T000655907270Z/build_normalization.json).
The eleven capture/analyzer/shared-runner Python tests pass. No storage budgets
were raised; older full cadence remains available through receipt-owned archives.
The rebuilt outputs also pass [33 rest/support checks](../../reports/checks/20261126T002034938742Z/console.log)
and [ragdoll reactivation](../../reports/checks/20261126T002200872273Z/console.log),
including player contact, anatomical constraints and bounded motion after waking.

### Remaining limits

Boundary-only clouds gain nothing, and individual engine calls remain atomic.
Preserving the convex boundary does not make all future assets equally cheap.
The scoped CPU-work result cannot close broader draw/physics variability, large
simultaneous combat deaths, long sessions, lower-end hardware or uncapped 60 FPS
headroom. The original human 126/103 ms spikes still lack detailed attribution.
No dependencies, engine patches, imported implementations or assets were added;
the helper and tests are original AI-assisted 0BSD code.
