# Bounded measurement of terrain-connected water volume

2026-10-11. NativeWaterCapacity measures an immutable NativeLakeVolume by clipping
its connected tetrahedra first to positive terrain density, then to fill elevation.
It sums their geometric volumes in double precision with compensated accumulation,
and rounds to integer millilitres once on completion. Connectivity, surface queries,
meshing and integration now share one tetrahedral-layout declaration. No third-party
code or new dependency was introduced; implementation remains0BSD.

The worker-owned task processes at most the caller's1..2048 cells per call, with a
2ms elapsed-time check every32 processed cells. Each partial cell has at most six
tetrahedra, each clipping stage creates at most three pieces. Scratch is fixed-size
stack storage; the task retains its immutable source rather than copying all cells.
Completed tasks do zero further cell work. The time check is not a hard wall-clock
scheduler guarantee. No task is automatically run each frame.

49 checks pass in debug and a clean release project. Exact nonnegative-node tank
integrals cover disconnected half-basins, a separating roof, scaled coordinates
and the262144-cell cap. Budget1 and2048 produce identical results. The curved case
measures333.016443m3; independent quarter-metre point integration gives331.90625m3,
a0.335% difference within the declared0.5% sampling tolerance. Cold/restored volume
measurements match exactly. A measured quantity initializes a native ten-litre
scoop transfer without changing the aggregate amount. Existing shoreline checks
also pass after sharing the geometry definition.

The maximum-cell debug fixture uses1024 calls with budget256, largest call1.407ms,
and23.073ms total including script overhead/logging. Raw release timings are retained
separately. These are current-host headless measurement costs, excluding terrain
sampling/connectivity bake and all rendering; they are not fluid-solver performance.

The first fixture incorrectly expected a perfect box from nodal zeros on all walls.
Some tetrahedra at corners have four zero vertices and therefore represent no air.
Those failures remain in initial_box_assumption files. reference.py independently
integrates the corrected field using exact rational Beta-distribution polynomials,
not the production clipping implementation. No tolerance was relaxed for these
exact checks. Whole-cell counts would overestimate the represented volume.

An additional required shallow-source gate fails as expected: a2cm-deep curved
puddle has positive-density seed air but the static lake builder returns-2 because
all eight seed-cell corners are not air. This remains an explicit implementation
blocker for small pours; do not call the lake builder bucket-ready. Its test and
failure evidence are retained. Next remove that full-cell admission dependency
while retaining solid/open-edge rejection and cache correctness, then build the
submerged-connection redistribution fixture.

This is geometric measurement, not changing lake levels, drainage or bucket
 gameplay. Mid-task results expose no authoritative quantity; only completion may
initialize a quantity record. World migration must be transactional and one-time.
Pressure, evolving connectivity, active flow scheduling and playable interaction
remain requirements in ../../FINITE_WATER.md.

Design reference: Robert Bridson's fluid-simulation course notes,
https://www.cs.ubc.ca/~rbridson/fluidsimulation/ . Pressure/free-surface obligations
inform the future submerged-passage gate; no solver implementation was copied.
