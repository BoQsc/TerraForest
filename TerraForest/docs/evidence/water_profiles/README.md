# Terrain-derived water capacity profiles and finite settling

2026-10-11. NativeWaterProfiles connects sampled 3D terrain, its regional topology,
and NativeWaterBasins ownership to NativeWaterSettling. Every positive-air tetrahedron
contributes once to its assigned leaf's volume-versus-height curve. The tested
half-space clipping kernel is shared with NativeWaterCapacity rather than duplicated.
Original implementation is 0BSD; no additional dependency.

44 checks pass in debug and a clean release project. A sampled ridge compiles to two
real storage curves; their total matches the separate whole-volume capacity path
to one millilitre. Below the sill, each curve matches separately flooded left/right
terrain volumes. Those comparisons share the geometric integration kernel; the
existing 49-check debug/release capacity suite was also rerun, including independent
exact tetrahedral integrals and point-sampled curved terrain.

Finite addition conserves total plus pending water at every native settling event,
fills both terrain basins to 4 m, and merges them. Withdrawal conserves retained plus
removed water at every event, lowers the targeted basin below the 3 m sill and leaves
the other at the sill. Finished settling performs zero further events. A connected
stacked cave fixture matches whole-volume capacity without counting the solid roof.
Budget 1 and 256 produce identical profiles. Invalid budgets, mismatched source
openings, missing spill anchors, nonzero initial capacity and above-ceiling requests
cannot publish partial/incorrect profiles. Caller edits do not mutate native curves.

Actual native-terrain integration separately carves a radius-4 sphere and samples
its edited density. Its 418 graph nodes become one closed basin. Computed capacity
is 39,843,474 ml; pouring that quantity then removing 1,000 ml leaves 39,842,474 ml.
Every solver step conserves the corresponding quantities. This uses the real native
terrain API, but does not involve gameplay items or a world-save transaction.

## Accuracy is explicit

Profiles currently accept 2..256 caller-selected shared height anchors. All merge
heights must be included exactly; no interpolation of spill thresholds is allowed.
The first anchor is strictly below all rounded-up air floors and the last cannot
exceed the immutable source ceiling. Each geometric anchor uses compensated double
accumulation and rounds once per leaf to integer millilitres. The declared total
anchor rounding bound is 0.5 ml per leaf, excluding floating-point roundoff.
Canonical migration must account for any difference from independently rounded totals.

Between anchors NativeWaterSettling uses linear interpolation. One-metre spacing
produced 1,172,093.75 ml deviation in the measured off-anchor ridge sample. This is
inadequate and is retained in the test, not hidden by a permissive assertion.
Two-centimetre spacing reduced measured deviation to 475.5 ml at the same 2.51 m sample height.
That requires 251 anchors and 1,539,484 compiler operations; it does not establish
an error bound of 475.5 ml for other terrain. The conservative published per-leaf
volume error bound is the largest adjacent-anchor capacity increment plus 1 ml;
aggregate bounds must account for all relevant leaves. Maximum anchor height step
is also reported, but is not an unconditional water-level error guarantee near
zero-area intervals or quantized volumes.

Adaptive/error-controlled curve selection or exact piecewise curves remain needed
for taller/complex domains without increasing the 256-anchor cap indefinitely.
This implementation deliberately does not claim production accuracy from the coarse
fixture. Regional stitching, raw open-terrain admission, edit-driven displacement,
quantity remapping, dynamic world rendering, buckets and atomic saves remain open.

## Scheduling and storage

Compilation validates identities/openings incrementally, then processes one
node/height pair per operation (at most nine clipped tetrahedra). Density clipping
is reused across a node's heights. Calls allow 1..2,048 operations and check 2 ms
elapsed every 32 operations. Not a hard wall-clock guarantee: retained debug calls
reached 5.047 ms, release budget-1 calls 4.700 ms. No game-frame, thermal or sustained
performance claim follows from these short headless checks.

Maximum working profile payload is about 24 MiB for 4,096 leaves x 256 anchors,
plus object/container overhead and retained topology/basin/source data. Setup
allocation and publication are bounded but not independently sliced. Publication
builds at most 4,096 packed-array references. The worker task must be retired after
publication; sleeping water does not rerun compilation. The actual-terrain fixture
uses 61 anchors, 28,112 operations, 110 budget-256 calls, a maximum measured 76 us
call and 1,952 bytes of profile payload (source/compiler ownership excluded).
