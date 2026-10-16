# Road surface paint — 2026-10-16

The combined settlement had a grass-coloured strip across asphalt. Grading already wrote asphalt material into occupied lattice samples even when density did not change. Native mesh colouring, however, suppressed material at unchanged natural surfaces. The regression reproduced nine road-interior vertices with minimum asphalt weight 0 before the fix and 1 afterwards.

The existing eight-sample native shading loop now also computes occupied asphalt coverage and blends that into the normalized material weights. Other terrain material displacement rules stay unchanged. No new shader, draw call, runtime script loop, simulation or save schema is introduced. Both Windows native variants rebuilt with the pinned Zig/prebuilt SDK. The derived-cache compatibility hash includes the DLL, so old mesh colours invalidate automatically; existing saved pavement needs no migration.

Checks: unchanged-height road material, normalized weights, exact mesh after terrain snapshot restore, repaint-to-stone removal, and the existing graded road bed/mining/worker test pass. The first fixture incorrectly requested a non-32-m vertical region and is retained separately; after correcting the fixture, the real pre-fix material failure was captured before modifying native code.

A fresh copied prepared settlement was opened graphically at 1920x1080. The same view now has continuous asphalt across the street (before/after PNGs inspected). Both patrol residents still walk and reverse, duplicate population is rejected, and compound save/fresh-process reopen pass. Source save SHA-256 remains unchanged. Grass outside the pavement and on the building-side verge remains expected here; this is not a claim of finished road art, large-scale performance or release-DLL runtime qualification. Startup hitches remain outside this fix. Water was untouched.

Reproduce: `python tools/run_godot_check.py road_surface_paint --timeout 30 --require "ROAD_SURFACE_PAINT failures=0" --headless`. Actual-world check: `python tools/run_settlement_population.py --source YOUR_PREPARED_SLOT`.
