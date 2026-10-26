# Mining black-face diagnosis — 2026-10-26

## Reproduction

Wild_Ridge, seed 1703, saved player position (990.1828, 32.32577, 1081.846).
`before.png` and `after.png` use the identical saved camera and density state.
`sky_before.png` / `sky_after.png` isolate the cached diffuse-sky channel.
The original screenshot was taken before the player saved; this is the nearby
saved view that reproduces the same pure-black face defect, not the exact original
pixel framing. The flashlight is OFF in the before/after images.

Albedo and normal diagnostic views showed intact geometry/textures. Turning the
flashlight on lit the black surface, with or without spotlight shadows. The sky
diagnostic reproduced its silhouette, locating the fault in native baked vertex
visibility rather than texture loading, missing triangles or spotlight bias.

## Cause and correction

- The density surface treats zero as air. Probe projection instead required a
  positive 0.015 clearance, so it marched through valid zero-density excavations.
- Fixed smooth-normal projection also failed on concave faces: for example the
  representative near (990.4, 33.4, 1080.6) ended inside rock at density -0.16143.
- Native projection now follows the local trilinear gradient, accepts zero air,
  and stops at cell boundaries rather than stepping across a narrow cleared area.
- Eight iterations remain the limit. If necessary, at most eight corners of the
  represented surface cell are considered; retained contour-component edges
  restrict that fallback for component representatives.
- Canonical probes and connecting-air checks now share the zero-air convention.
  Negative-density walls still forbid reuse. No brightness floor, disabled
  shadows, extra sky rays, geometry changes, or shader/frame-loop work was added.
- Existing DLL-hash compatibility invalidates old derived lighting caches. No
  regeneration or mutation of player worlds is required.

## Verification

- Native synthetic zero-density excavation: 44/44 old buried starts repaired;
  all 49 initially-zero starts stay put. Cold/warm results and saved bytes match.
- Native `regression_044.cpp`: 19/19. Sealed chamber sky/sun stay 0/0; a side-open
  roofed chamber receives nonzero sky; LOD and save/edit checks pass.
- Native `regression_045.cpp`: 21/21. Cache determinism, edit invalidation,
  shadow-ray budget reporting and mesh/cache/save checks pass.
- Source run `ec1e94d7a9ea4a21`; packaged run `f3b30862c75642c9`: all nine captures
  and read-only restoration pass. These checks verify capture execution, not
  automatic aesthetic acceptance. The final source and packaged images were
  visually inspected.
- In the specified 400x600 comparison crop, 160,077 baseline near-black pixels
  reduce to one remaining near-black pixel; see `pixel_comparison.json`. This is
  a local image check, not a claim that every cave pixel must be illuminated.
- Baseline/source/package serialized density SHA-256 is identical:
  `f53cc7578a6b6e54b1f1a659fcee0ad8d16f2ee7be01768cc900154330932bd5`.
- Each run checks hashes of the original save and its data files. None changed.
- Both debug/release DLLs rebuilt, resource pack exported, startup check passed.
  Final installed DLL identities are recorded in source/pack manifests.

Rejected diagnostic trials included sign-only stopping (left concave probes in
rock), immediate nearest-edge projection (over-darkened other faces), and gradient
projection without boundary/fallback safeguards (failed 28 synthetic cases).
The final bounded implementation passes those cases. Early probe/capture outputs
remain under ignored `reports/mining_darkness`; full private world copies are not
committed. The standalone probe is specific to this report's neighborhood.

## Re-run

`python tools/check_mining_darkness.py --slot Wild_Ridge`

Add `--pack` to exercise the installed pack. Each run makes a fresh named copy,
uses read-only/temporary mode and a fresh derived cache, and retains its evidence.
It never loads the player's original save for writing.

Compile `tests/native/mining_light_regression.cpp` with the pinned Zig C++ compiler,
`-std=c++17 -O2 -ffp-contract=off`, then run the resulting executable. It includes
the production core directly to test private probe-placement helpers. Compile the
two existing regression sources with `addons/volumetric_terrain/native/core.cpp`.

Still intentionally unsupported: full multi-bounce GI. Sparse sky samples can
miss very small openings, and genuinely sealed areas should remain dark. Any new
false-black report needs a saved viewpoint and the same diagnostic comparisons;
do not globally brighten caves to hide it.
