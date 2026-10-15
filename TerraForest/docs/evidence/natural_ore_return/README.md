# Natural iron trip: return after mining

2026-10-15. The entrance-to-iron test now walks back to the surface and checks
the saved on-foot return position on fresh-process reopen, alongside exact
inventory/tool wear and the27 sampled edited terrain density values.

First run20261015T200017237247Z FAILS: returning along the immediate direct line
stops near the newly excavated floor at (722.939,82.636,399.092), grounded.
Thirty seconds does not clear this obstruction. Arbitrary excavated floor lips
are not automatically traversable; this failed direct route remains recorded.

Run20261015T200253925389Z instead walks two metres to the side, then three
metres uphill before returning through the original entrance. It PASSES without
teleporting, filling terrain, jumping or changing collision/movement code. The
uphill leg takes.512 seconds and the remaining ascent22.010 seconds. Of193
retained quarter-second walking samples,192 report grounded; endpoints require
grounded arrival. This is not continuous per-tick contact verification.

One ordinary pickaxe strike yields two iron items with wear. Compound save and
fresh-process reopen restore exact inventory, edited density samples and surface
position within.1 m. The original cave staging source hash remains unchanged.
No human save or runtime water behavior is modified.

Return screenshot inspected; camera faces outward from the entrance. Existing
faceted terrain/headlamp appearance remains. Reopen retains a132.77 ms terrain
receive hitch. This is correctness evidence, not a frame-time, thermal,
all-seed, copper-route or unassisted-discovery qualification.

Reproduce:
python tools/run_geology_rewards_route.py --walk-iron --source cave_stage_7715b685870243ae972039d1ac7294de

The walking case has a120-second process ceiling for startup, descent, mining
and ascent; individual walking legs retain their30-second limit. The earlier
failure is retained, not relabelled as a pass.
