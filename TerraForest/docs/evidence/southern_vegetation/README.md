# Southern world vegetation diagnosis — 2026-10-18

Readonly southern_mixed_42_20261018, seed42/generator13, 1920x1080 cap60,
Godot4.7.2 RTX4050 laptop. Existing models, distribution and shaders unchanged.

The previous southern overview used a short fixed delay. This test instead waits
for all 49 cover owners, dirty owners, requests, scatter and support jobs to settle,
then captures overview and actual terrain-picked eye height. The ground pick is
asynchronous and must be awaited. Native render statistics check page admission.

Final run: 7016ms cover settling after destination readiness; 49 residents, no dirty
owners or pending scatter/support. 23442 resident grass instances, 1834 ferns,
219 bushes, 165 twig clusters; all species zero budget-deferred pages. Counts
cover the resident region, not only pixels visible in the screenshot.

Both final images inspected. Ground cover is populated but visibly regularly
spaced, with broad exposed spaces and weak ground integration in open daylight.
Increasing page budget is not justified by this sample. The next art/distribution
work should address this pattern without blindly multiplying geometry or replacing
accepted models. Neither visual quality nor performance is accepted by this check.
HUD frame rates in captures are not a benchmark and do not prove steady60.

Two failures are retained: first test waited for global terrain idle and read an
asynchronous pick immediately. Corrected cover-only wait still failed once at45s.
A diagnostic rerun with a15s deadline passed in7s; this does NOT establish why the
previous cover wait failed. Intermittent publication/settling remains unresolved;
the test logs owner/request/job state on failure for the next reproduction.
