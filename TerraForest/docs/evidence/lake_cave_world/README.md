# Connected cave water in the saved generated world

2026-10-11. Current runtime8aab863, new integration fixtures only. No runtime change
was needed for the tested cave behavior. Actual generated terrain, native lake
sampling/occupancy, collision, player camera and compound persistence are used.
Both processes use fullscreen1920x1080/cap60. Source furnished save is unchanged;
canonical hashes and native binary hashes are retained in run manifests.

Seventeen creation/reload checks pass:

- Four generated lakes publish; normal travel loads lake1 terrain collision.
- A radius3m pocket at(262,30.4663,225), below water elevation36.4663m, is carved
  inside the finite lake bounds. It remains dry while disconnected and has a real
  terrain roof above it.
- A radius2.5m submerged tunnel connects it to the lake seed. Accepted terrain
  editing immediately invalidates old water, then rebaking fills the pocket.
- Actual player chest and camera queries recognize immersion. The production
  vegetation placement mask excludes the submerged floor while allowing a dry
  point above water. This checks the mask, not rendered grass distribution.
- Normal compound save and F9-equivalent reload preserve exact lake definitions
  and pocket water depth6m after terrain/water publication.

A fresh process passes three more checks: exact copied slot restored, depth6m
preserved, and actual player immersion plus terrain roof still present. The
underground screenshot was inspected and shows the flooded tunnel, terrain sides,
headlamp illumination and underwater effect. This is provisional art, not realism
acceptance. Startup logs retain80–83ms controller/world hitches; the60FPS HUD is
not a frame-time or travel qualification.

Reproduce creation with `python tools/run_lake_cave_check.py`, then reopen with
`python tools/run_lake_cave_check.py --reopen`. Requires the local generated furnished
source checkpoint; no other game should run during graphical checks. Each creation
uses a unique copy and fresh derived cache. Reopen uses only that recorded copied
slot; tests reject unrelated slots. Copies/cache are retained, not deleted.
Recorded slot: `lake_cave_20261011T150927714523Z`.

Limits: one bounded generated lake/pocket/connection, no natural cave discovery,
multiple connected regions, lake drainage, water conservation, dynamic simulation,
player traversal through the full tunnel, dense vegetation qualification or thermal
proof. Cave connection fills on rebake using fixed elevation. Existing conservative
voxel queries versus smooth visible shoreline precision remains open. Next measure
that disagreement before changing representations or claiming all water coverage.
