# Northern neighborhood expansion — 2026-10-18

New district worlds now compose twelve furnished three-storey buildings on two
parallel streets with cross-connections and twelve entrance approaches. This uses
the existing native prefab composition, block meshing, static attachment batches,
streaming and collision systems; no new runtime updater or raised budget was added.

The building envelope is 61×117 m. Northern placement is centred north/south beside
the arterial, instead of pushing the expanded footprint wholly southwest of the
site. The actual terrain survey must admit the footprint before grading. Preparation
now derives the expected outer building count from district recipes rather than a
hardcoded total. Including the cellar, the integrated world contains 31 buildings.

Evidence: four-rotation composition/grading checks pass; complete seed-42 bake and
fresh-process reopen pass, preserving world component signatures. Ten Python
preparation orchestration tests pass. Saved world northern_district_42_20261018 is
available in Worlds.cmd; older saves and the normal generated_world_v4 are intact.

Read-only graphical review passed in 24.81 s at 1920×1080. Counts by site were
[8,5,2,12,4]. At the northern view, 70 wanted block chunks were settled, zero budget-
blocked/deferred chunks, 1,409,256 bytes of mesh payload and 15,318 triangles in the
resident block representation. These are view-local block metrics, not totals for
all world geometry, furnishings, vegetation or GPU memory.

The 180-frame stationary sample preceded screenshot capture: median 16.666 ms,
p95 16.686 ms, max 16.760 ms; GPU p95 6.194 ms. This short view does not establish
long-run headroom, thermal suitability, dense animated population or city scaling.

The screenshot was inspected: all twelve towers are visible with connected roads.
Facades are repetitive and terrain shoulders are visibly raised/abrupt; streetscape
and landscape integration remain unfinished. Native approach geometry is validated,
but the expanded neighborhood has not yet had a complete on-foot traversal of every
entrance and street. This is a larger initial neighborhood, not a finished city.
