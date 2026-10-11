# Regional basin hierarchy from 3D terrain connectivity

2026-10-11. NativeWaterBasins consumes NativeWaterTopology output, sweeps air-node
activation and face-opening heights, and produces a compact merge forest. A complete
height plateau is processed before creating local minima. This avoids one basin per
tetrahedron: the flat fixture reduces 6,030 nodes to one leaf; the ridge fixture
reduces 5,974 nodes to two leaves meeting at the measured 3,000 mm sill.
Original implementation is 0BSD and adds no dependency.

58 checks pass in debug and a clean release project. They include 250 known-graph
and 20,592 seeded random-graph flood comparisons, boundary heights, shuffled edge
order, exact budget-1 versus budget-512 output, caller mutation, malformed input,
external ports, disconnected forests, explicit minimum/depth limits and a maximum
24,576-node plateau. The emitted nested hierarchy passes NativeWaterSettling entry
ownership validation and conserves a 5,000,000 ml addition with supplied profiles.
Those profiles are synthetic; terrain-derived storage curves are still missing.

Actual native-terrain integration excavates a sphere, samples its density, and
reduces the resulting 11,636-node regional graph to one basin. All 640 outgoing
ports survive. It correctly refuses closed-solver eligibility until those ports
are stitched. This takes 92,422 bounded operations in 181 budget-512 calls;
largest measured call 103 us, retained compiler buffers 1,438,472 bytes.

## Contract and limits

Node IDs remain scoped to one immutable source grid and edit version. Input identity
must be strictly increasing. Each edge has sorted distinct endpoints and an opening
at or above its owned node floors. External edges are retained explicitly, and
neither endpoint belonging to the region is an error. The compiler publishes nothing
until all phases finish; failure exposes an error and no partial hierarchy.

Output owners parallel input IDs, mapping geometry to a local minimum. Leaves are
numbered first; merge tuples follow as (left, right, opening_mm, entry_leaf). Roots
may form a forest. Only a single root without external ports and depth at most 64
is marked eligible for the existing settling solver. Storage profiles still need
to be supplied. Depth beyond 64 is reported, not silently truncated or accepted;
a later compact multiway representation may be necessary for complex worlds.

Limits: 24,576 nodes, 98,304 edges, 4,096 minima and 8,191 hierarchy nodes. A call
accepts 1..2,048 operations; heap operations are logarithmic, disjoint-set unions
use size balancing/path compression, and allocations are reserved before stepping.
Elapsed time is checked against 2 ms every 32 operations. This is not a hard time
guarantee: release budget-1 calls reached 4.168 ms and the maximum plateau run
reached 3.312 ms. Retain those observations; do not reinterpret this as a game
frame or thermal qualification. Completed tasks perform zero further work.
Setup allocation and final array trimming are bounded but not independently sliced.
Compiler scratch remains until its object is retired; bounded compiler concurrency
and timely retirement are required. Buffer statistics count array payloads and
vector capacity, not allocator/object overhead or the source volume.

## Remaining full requirement

Compile actual geometry storage curves with explicit approximation bounds, stitch
open terrain regions with versioned ownership, remap quantities after terrain edits,
and commit fluid/item/save changes atomically. World runtime, water rendering,
bucket tools, transient flow and dynamic drainage are not integrated here. Playable
lakes retain static fill levels. See ../../FINITE_WATER.md for the complete gates.
