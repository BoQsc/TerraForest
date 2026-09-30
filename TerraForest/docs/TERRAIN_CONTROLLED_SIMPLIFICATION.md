# Explicit native simplification controls

The isolated C++ probe now calls meshoptimizer directly, with border locking and
absolute error enabled and component pruning disabled. The unmodified MIT-licensed
source subset is pinned to the same Godot revision as the importer comparison;
file SHA-256 hashes are verified before compiling. The API/flags are defined in
the [pinned header](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/thirdparty/meshoptimizer/meshoptimizer.h).
Nothing is linked into the runtime addon yet.

Each of the 15 candidate meshes is simplified independently from its original
geometry at requested errors 0.01, 0.05, 0.1 and 0.25 world units. The target is
approximately 1/16 of the original triangles; a target is not forced when the
simplifier stops earlier. This is position-only simplification, without material,
UV or normal weighting.

## Result

**All 60 outputs preserve exact region boundaries and the tested topology counts.**
Component counts, Euler characteristic and absence of overused edges match the
input. This resolves the previously observed component-pruning problem in this
corpus. It does not constitute full topology or self-intersection certification.

At the 0.25 setting, the three 32 m parents produce:

| Input | Triangles before → after | One simplification ms | Sampled maximum surface distance |
|---|---:|---:|---:|
| Cave | 40,858 → 2,552 | 20.53 | 0.10711 |
| Mountain | 16,384 → 1,024 | 8.55 | 0.04631 |
| Edited mountain | 17,100 → 1,068 | 8.95 | 0.12615 |

Timings exclude distance validation, copying, materials, shading, publication and
rendering. These are individual observations. They must not be presented as a
speedup relative to the importer's complete LOD-chain timing.

## New rejection: reported error is not our acceptance bound

The independent distance check samples **all used vertices and all triangle
centroids in both directions**, using a triangle BVH and double-precision distance
calculations. **39 of 60 outputs exceed the requested error plus a 0.0005-unit
numerical allowance.** The probe intentionally exits 1.

For example, the cave parent at requested error 0.01 reports approximately 0.010
from the simplifier but reaches about 0.044 in the independent surface-distance
samples. The direct control solves pruning, but its reported error cannot be
used as a strict maximum terrain displacement guarantee.

The checker includes analytic face/edge/vertex-distance cases, self-distance
checks on every original mesh, and 16 exhaustive triangle searches per generated
LOD to cross-check the BVH (960 queries total). Self-distance and BVH/exhaustive
differences are below the report's eight-decimal printed precision in the retained
run. An initial float-precision distance implementation failed the self-distance
check on thin triangles; final rejection results use the corrected double-precision
implementation. The mesh inputs and simplifier still use float32 positions.

These sampled distances are **lower bounds on continuous worst-case surface
error**, not a Hausdorff certificate. Passing means no tested point violated the
budget; it does not prove every point passes. Errors here are against the candidate
mesh, not the original density field, so they do not eliminate the candidate's
previously measured interpolation deviation.

## Decision

Keep native simplification with explicit controls as the working direction.
Do not publish LODs solely because the library reports an acceptable error.
The admission step must independently validate shape error, tighten simplification
when needed, and retain finer geometry when validation cannot establish acceptance.
Continuous error bounds, material constraints, mixed LOD rendering, bake/streaming
budgets and integrated 1920×1080 performance remain unqualified.

```text
python tools/probe_terrain_tetra.py
python tools/probe_terrain_simplify.py
```

The second command currently rejects 39 outputs. Original importer behavior was
also rechecked after sharing the boundary checker and still rejects six outputs.
Raw reports are retained in `docs/evidence/terrain_controlled_simplification/`.
They contain source/vendor hashes, build command, input/output hashes, requested
and reported errors, both sampled directions, validation controls and timings.
