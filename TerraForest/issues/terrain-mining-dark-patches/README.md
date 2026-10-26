# Black terrain patches while mining

- **Status: Improved / partial.** Reproduced excavation repaired; broader limits remain.
- Updated: 2026-10-26. Fix `f28859c2`; comparison baseline `72951f9e`.
- User review: 2026-10-26, "I think it's better"; not universal lighting approval.
- Symptom: Mined faces turn flat black until lit by the headlamp.

## Before / after

Hidden_Hills, seed 1703; saved feet (986.2361, 39.93774, 1023.084).
Same saved camera/density; headlamp **off**. This is the nearby F5 reproduction,
not the exact framing of the original user screenshots.

**Before:** false-black band across intact rock.

![Before: black band across excavation](images/before-72951f9e.png)

**After:** shaded texture without the headlamp; real shadows remain.

![After: textured, shaded excavation](images/after-f28859c2.png)

[Image provenance](images/manifest.json).

## Changes / verification

- Earlier repair kept visibility probes in air rather than neighboring rock.
- Follow-up adds bounded sky sampling near edited pages, avoids sharing a nearby
  dark result, and caches exact-position results. No ambient brightness floor.
- Saved-view/package, sealed/open chamber and cache checks pass; 1,200-edit workload
  passes existing gates. Player saves and serialized terrain remain unchanged.

## Remaining / resume here

- Tiny openings can evade finite samples; untouched caves retain the old sampling.
  No bounced GI; sealed caves should stay dark.
- For recurrence, compare albedo, sky visibility and headlamp-off/on at the F5 pose.
  Preserve native baking/cache budgets rather than globally brightening caves.
- Code: [lighting core](../../addons/volumetric_terrain/native/core.cpp),
  `visibility_origin`, `diffuse_sky_visibility`, `shade_visibility`.
- Tests: [native regression](../../tests/native/mining_light_regression.cpp),
  [saved-view diagnostic](../../tests/mining_darkness.gd).

## Reproduce / history

`python tools/check_mining_darkness.py --slot Hidden_Hills --pack`

Requires the local save; harness uses an isolated read-only copy and fresh cache.
New reports need their own saved viewpoint. No private world data is committed.

- [Initial probe-origin repair](../../docs/evidence/mining_darkness/README.md).
- [Refinement, timings, rejected trials](../../docs/evidence/mining_darkness/refinement/README.md).
- [Build/test provenance](../../docs/evidence/mining_darkness/refinement/qualification.json).
