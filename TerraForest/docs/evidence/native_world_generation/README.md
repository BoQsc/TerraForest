# Native generation backend, 2026-10-22

Production regional road search, corridor surveys, street grade constraints,
lot candidate evaluation and entrance fitting now run in C++. The bake calls
these implementations. Unused scripted route/frontage algorithms were removed.

A shared versioned plan supplies the generator preview and bake. The preview map
rasterizer runs natively. Plans store values, not serialized executable objects;
prefab resources are reconstructed from the versioned recipes. Cache entries are
SHA-256 checked, capped at 8 MiB each, atomically renamed after verification, and
limited to 32 entries / 64 MiB. This is a derived planning cache, not new
canonical world storage. Increment VERSION when planner/terrain/recipes change.

## Verified

- Native road earthworks application and surface probes passed.
- Existing multi-seed lot terrain-fit checks passed, retaining 2m fill / 3m cut.
- Cold planning, identical warm reconstruction, asset footprint reconstruction,
  corrupt-cache rejection/regeneration, invalid native inputs, cache quota and
  unrelated-file preservation passed. Planning: roughly 6.4–6.7s cold, 18ms warm
  on the current computer. These are planning timings, not gameplay FPS claims.
- 1920x1080 generator preview inspected: actual 20 building footprints and road
  layout are shown. Non-integrated presets retain terrain-only preview.
- Full create and separate-process reopen passed for
  `native_world_rewrite_42_20261022`: 20 buildings, 363 earthwork segments,
  2 public places, 441 saved navigation roads. Preview, bake and reopen use
  digest `22f5c682d8d7da07af97491e02817cd9868a3c7e4983cb2aa14cd63d8e4cc28e`.
- Saved buildings, furnishings, paving and navigation matched on reopen;
  road/tree overlap check returned zero. Actual cached loading photo inspected.

Full run: reports/combined_preparation/20261022T202644140392Z.
The new optional .generation.json publication was added afterward and syntax
checked; the tested bake already writes generation_plan_identity.json in its
report. Its publication copy needs the next create run, not a claim here.

## Still open

This preserves current recipes; it is not a new artistic world layout. Street
view still has broad pale shoulders, repetitive buildings and sparse surroundings.
One street screenshot reads 38 FPS; it is a capture during preparation, not a
controlled performance sample and does not qualify sustained 60 FPS.

Region candidate orchestration, prefab recipe assembly, earthwork assembly and
publication still use scripts. Compute generation jobs, standalone removal of
Python, richer settings, cancellable native stages, complete water/POI preview,
authoritative regional-storage/capacity work and sustained performance remain
required in WORLD_WORKFLOW_REDESIGN.md. No new compute shader is claimed.

A headless invocation of the visual UI-bounds test failed because it had no
1920x1080 display viewport (reports/checks/20261022T203352309354Z). The actual
1920x1080 graphical rerun passed (20261022T203419005340Z). This does not establish
support for smaller UI resolutions; 1920x1080 remains the requested test target.
