# Regional mine ore coverage — 2026-10-18

Generator 12, seven seeds: 0, 1, 42, 50, 141, 1703, 9999. Native read-only surveys
take less than two seconds for the complete seven-process batch. No worlds or
inventories are edited. Run regional_ore_survey.gd with --survey-seed=N and
--survey-deeper to reproduce an individual seed.

The default survey remains the original 0.5 m floor check used to stage seed-1703
gameplay tests. The deeper mode examines 327 floor rays and 96 radial wall rays
across the three chambers. Samples are 0.5, 1, 2, 3 and 4 metres into solid rock;
walls are queried at 1.5 m above the chamber floor. It requires material ID 8/9,
negative solid density and vein weight magnitude above 0.9.

| Seed | Strong nearby iron | Strong nearby copper |
| --- | --- | --- |
| 0 | No sample | Yes |
| 1 | No sample | No sample |
| 42 | No sample | No sample |
| 50 | No sample | Yes |
| 141 | No sample | Yes |
| 1703 | Yes | Yes |
| 9999 | Yes | Yes |

All 327 floor rays hit supported floors for every seed. Thus the failed resource
criterion is not simply a missing-floor ray result. This does not prove that a
whole mine/world lacks ore: grid sampling can miss small deposits, weaker vein
edges are excluded, and upper walls/deeper excavation are outside the survey.

Source inspection: geology.hpp creates seed-derived capsules per 32 m cell; mine
chambers in core.cpp are independently positioned and lowered to preserve surface
cover. No constraint brings veins into the intended mining location. Seed 1703's
successful gameplay check therefore cannot qualify seeded resource-location design.

Next implementation requirement: deliberate resource-bearing workings in the new
generator recipe, using the same authoritative material field as rendering and
mining. Preserve existing generator identities/save geometry rather than silently
changing older worlds. Verify seeded location access plus actual excavation and
rewards; do not substitute chest ore for terrain deposits or reject most seeds just
to make the existing floor test pass. This finding remains open.
