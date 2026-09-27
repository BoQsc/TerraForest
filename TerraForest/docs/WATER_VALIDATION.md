# Static volumetric water validation — 2026-09-27

Historical first-water-stage report. The session-only storage limitation below has since been resolved by compound snapshots; see WORLD_STORAGE.md and STORAGE_VALIDATION.md for current persistence behavior.

This report covers the first bounded static-lake implementation, not the full requested world-system expansion.

## Correctness

- Native debug: 34 checks passed.
- Native release DLL loaded in a clean project: 34 checks passed.
- Real terrain/forest scene: 13 checks passed.
- Water addon starts and bakes a density field without either terrain or forest installed.
- Existing terrain/forest integration: 31 checks passed after adding water hooks.
- Resource pack starts with five external Windows DLLs (terrain, two runtime variants, two water variants).

Tests cover allocation caps, invalid dimensions/coordinates/density, immutable publication, finite depth queries,
open-boundary rejection, blocked seeds, disconnected chambers, water below a cave roof, negative coordinates,
scratch reclamation, actual native terrain sampling, revision and cancellation mismatch, edit invalidation,
rebaking and removal while sampling. Water data in the demo basin occupies 20,480 resident bytes;
this excludes rendering resources and scene/bookkeeping overhead.

## Measured costs

Headless debug measurements: 262,144-cell flood bake 16.588 ms; actual terrain sampling/bake
62.044 ms across 48 bounded slices. These are CPU test timings,
not guarantees for every machine, and not per-frame fluid simulation costs.

The graphical run used 4.7.2-stable (steam), Forward+ on the GTX 1060 Max-Q, **1920×1080 exclusive fullscreen**,
100% 3D scale. In a fixed warmed view of one lake and the surrounding forest, 600 uncapped frame samples:

| Median | p95 | p99 | Maximum |
| --- | --- | --- | --- |
| 6.557 ms | 8.961 ms | 9.720 ms | 87.882 ms |

The maximum is retained rather than discarded. This short sample excludes bake/travel timing and is not a matched baseline speedup,
multi-hour soak, multiplayer capacity result, or evidence of worst-case frame headroom.

## Visual and release limits

The actual screenshot in evidence/water/water_lake.png was inspected. It shows the excavated basin and bounded water surface.
Shorelines remain visibly voxel-stepped; the shader is opaque with lighting ripples and no refraction/underwater effect.
This is a development feature, not a finished water visual treatment.

Lake definitions are session-local. Terrain excavation can persist independently; use the temporary-world launcher for experiments.
There is no atomic shared world save, water cache, automatic lake placement, mass-conserving flow, swimming, buoyancy or water replication yet.
Opening the basin rejects a rebake instead of simulating drainage. A blocked seed also rejects the bake.

Builds use Zig and the pinned prebuilt godot-cpp libraries; no local godot-cpp compilation was performed.
Run the commands in addons/volumetric_water/README.md to reproduce these checks.
