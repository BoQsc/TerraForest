# Far-cover LOD and MSAA comparison — 2026-10-19

Same saved world, camera, frozen wind and candidate population as the earlier
fade diagnostic. Inspected higher_lod_detail and msaa4 captures: neither removes
the conspicuous speckled pattern. LOD threshold 0.25 costs 11.652 ms median GPU
versus normal 6.527 / repeated normal 6.531. MSAA4 costs 7.039 ms. Both are rejected
as blanket production fixes. No production changes. Test is stationary, despite
the initial intention to include movement; temporal stability remains untested.

Companion depth diagnostic temporarily adds 0.75 m vertical offset beyond 40 m
with a 20-40 m blend. Its inspected result still contains the pattern. This does
not support a simple support-height offset as a fix and is not proof that every
plant matches every terrain LOD. Floating cover is not an acceptable correction.

Next work must test temporal stability and quantify coverage in defined distance
bands before altering assets. Current evidence does not establish a unique cause.
Keep native identity/placement, sparse density, nearby models, shadows and fade
policy intact. No whole-world performance qualification follows from these tests.
