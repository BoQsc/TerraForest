# Seeded integrated generation

Added seed selection to the existing offline generator. Seed 42 produces a separate
23-building integrated world, including prepared roads, entrances, cellar, owned
mine, lakes and residents. Exact addon state and seed/generator identity survive
fresh-process reopen. 9 launcher tests pass, including pre-write seed validation.

A second seed exposed a connection-height error: a surveyed district can be below
the generated regional road. The connector now finishes at the regional road's
actual height. A targeted three-grade test passes. Existing saves are not migrated.

Corrected bake retained its successful staging save when reopen failed on a helper
script formatting error. Formatting was fixed and the same stage reopened/published
without regeneration; both original failure and successful recovery are retained.
Final saved-world district check passed in 24.05 s; north/south screenshots inspected.
The northern district has a visible graded terrace. No all-seed suitability, smooth
road curvature, vehicle route or sustained performance claim is made by this check.

Published development slot: regional_seed42_access_20261018. Default review remains
seed 1703. The regional topology and prefab vocabulary remain a fixed initial design.
