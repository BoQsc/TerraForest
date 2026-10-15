# Tower stair-flight rails

New furnished towers now include a rail on each side of every ascending flight,
in addition to the existing horizontal opening guards. Three floors have 70
attachments (previously 66). Four added instances reuse the 84-triangle guardrail
mesh through a separate native batch identity, `architecture/metal_stairrail/v1`.
The transformed span rises 1:1 with vertical posts. Each costs four metal and
salvages two through the common construction catalog.

Collision uses four thin top-bar proxy sections per sloping rail. This adds 16
shapes to a three-floor tower, not active rigid bodies or per-object scripts.
Standing player capsules are blocked; the open space below the bars is not a
solid wall. The new collection caps residency at 128 instances / 512 shapes,
builds at eight instances / 32 shapes per tick, within 64 m. These are bounds,
not proof of acceptable dense-city timing.

The first attempt reused the horizontal guard's full box. Conservative prefab
validation correctly rejected overlap with stairs/floors. Its failed log is
retained. The test now exits immediately after placement failure rather than
continuing into missing door data and waiting for timeout. The correction uses
segmented top-bar collision and puts the rails just inside the shaft.

Graphical `tower_traversal --furnished --all-floors --visual` passes at 1080p:
complete prefab placement, door entry, both flights up/down without jumping,
four sideways fall attempts, existing landing guards, tall-wall rejection and
low-ceiling rejection. Report `20261015T212537827904Z`; screenshot
`reports/tower_stair_rails.png` inspected. `pass.log` and `traversal.json` retained.

Existing saved towers are unchanged. New placed tower prefabs and newly prepared
neighborhoods receive rails. This is an isolated structure/player test, not a
main-world save/reopen, rotated-tower, full density or thermal qualification.

Follow-up: `../tower_rail_persistence/` verifies rotated placement and exact
full-world save/reopen with restored rail collision. Dense performance remains open.
