# Reject conservative coverage admission for live editing

The standalone C++ experiment adds a bounded validation and retry stage to the
controlled native simplifier. It is not part of the game DLL.

The retained run tests 15 original meshes at two distance budgets, 0.05 and 0.25
world units. It accepts 12 reductions and falls back to the byte-identical input
in 18 cases. All 18 fallbacks exhaust the 200,000 coverage-cell allowance.
Boundary and topology-count comparisons, sampled distances and exact fallback
checks pass for all 30 final outputs. This is safety through fallback, not
successful reduction of all inputs.

Admission takes **37.40–516.18 ms**. Eighteen outputs exceed **150 ms**, the
existing whole-interaction rejection ceiling, before extraction, queueing,
publication or collision costs. All six 32 m parent outputs fall back. The
runner intentionally exits 1 for the latency rejection despite zero geometry
gate failures. Increasing the coverage allowance is not an acceptable live-edit
fix; this implementation already spends too much time.

## What the check establishes

For each source triangle, find a target triangle near its centroid and measure
all three source vertices against that same closed target triangle. Distance to
a convex set is convex, so in real arithmetic the largest vertex distance bounds
the entire source triangle. If this is inconclusive, bisect the longest edge and
repeat. A centroid outside the budget immediately rejects the candidate.
Run this coverage check in both directions.

The implementation uses double precision and a 1e-7 numerical reserve, not
interval arithmetic or a formal floating-point proof. It allows three attempts,
200,000 coverage cells shared across retries, and depth 20. These limit search
work; they do not bound BVH node visits or guarantee a wall-clock deadline.
Failure retains the exact original indices and positions. Analytic controls
exercise identical and displaced triangles and zero work allowance; the corpus
also exercises end-to-end fallback 18 times.

Admission time includes simplification, candidate BVHs and coverage. It excludes
the shared reference BVH, subsequent independent sampled verification and file
output. Thus the reported cost understates a standalone complete invocation.
Geometry comparisons occur in the Python harness after native admission; this is
not a complete production publication gate. Component/Euler/edge counts do not
prove absence of self-intersections or every topological defect. Distance is
relative to the tetrahedral input, not the original density field.

## Consequence for the foundation

Reject this admission implementation on the live mutation path. Preserve the
controlled simplifier and failure witnesses as evaluation tools. Offline baking
may tolerate more validation, but neither bake throughput nor cache invalidation
has been qualified here. No larger runtime rewrite is justified by these results.

The next architectural experiment must demonstrate bounded local replacement
and safe delayed distant updates without waiting for this expensive validation.
First measure a single edit crossing region boundaries, including visible mesh
and collision publication. Retain a known-valid visible representation during
pending distant work and explicitly measure how long it can remain stale; do not
silently count stale terrain as responsive editing. Correctness, queue bounds and
latency are acceptance requirements before expanding the streaming integration.

Reproduce with `python tools/probe_terrain_simplify.py --admission` after generating
the tetrahedral fixture binaries. Evidence is in
`docs/evidence/terrain_lod_admission/`. The original simplification regression was
also rerun after sharing the distance checker: it still rejects the same 39 of
60 settings. These are native probes, not fullscreen rendering qualification.
