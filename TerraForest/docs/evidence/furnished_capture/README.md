# Furnished building capture — 2026-10-15

Previously the world editor called the block-only capture function and saved no
model attachments. It now passes its registered model collections to a native
capture query before publication. Region visual bounds reject distant groups;
intersecting model meshes must be wholly inside the block-local selection.
Relative model transforms account for parent frames and the capture origin.
Unavailable regions or active transfers reject rather than omit objects; the
existing 4,096-attachment bound applies. No source object IDs or live state are
copied. Storage contents are not duplicated; new instances receive fresh IDs.

Checks place the production enclosed cottage, capture all 13 objects and its
blocks, compare expected relative poses under a rotated/translated parent, reopen
the library with exact attachments and place the result through the normal native
combined transaction with a quarter-turn. Source block/model snapshots remain
unchanged. Partial selection and an actually unloaded table region reject.
Existing block-only library capture/archive/restore/stack regression also passes.

Both native builds compiled against the prebuilt SDK. Runtime verification used
debug, headless correctness. The main-world capture call is wired to the query;
this turn did not automate mouse corner selection or run a new visual review.
No dense-world capture latency or release-runtime qualification is claimed.

Geometry/pose is captured, not chest contents, wear, door hinge records or other
per-instance simulation state. Object-only selection still requires a block.
The query scans collection region bounds then candidate records, not every mesh
vertex; extreme collection populations still need timing qualification.
