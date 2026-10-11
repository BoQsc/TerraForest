# Optional generated grass texture, 2026-10-11

Generated using the built-in image_gen tool, not procedural image synthesis or
external stock. Full prompt: ../../../addons/world_ecosystem/art/grass_detail_v1.prompt.json
Generated original PNG bytes: ../../../addons/world_ecosystem/art/grass_detail_v1.trtex
The extension matches existing runtime image-loading conventions; the payload is PNG.
Source is copied into the project; no dependency on the generation output directory.

Texture is a full-coverage leaf surface with subdued longitudinal variation,
a warm tip and dark base. Existing opaque geometry and vertex colours remain.
Only the grass material can enable it. F7 toggles it in ground-cover-enabled worlds,
including Play Woodland Preview.cmd. Default is off; setting is session-only.
No alpha cutout, extra geometry, per-instance texture, or normal-map pass.
One shared lazily loaded ImageTexture, resized once to256x256 with mipmaps and
anisotropic filtering. Shader strength0.35, bounded colour modulation +/-12.25%.
Foliage/stone materials remain at zero strength; disabled branch skips sampling.
Toggling off retains the small shared texture for reuse until process exit.

44 asset/catalog/geometry/save/interaction checks and28 native batch LOD checks
pass. Preview compares off/on/off at the same camera and population, with grass
wind disabled, unchanged placement snapshot, fullscreen1920x1080 cap60. Other
world animation continues; screenshots are not pixel-isolated comparisons.
Initial headless test queried an unset shader parameter and got null rather than
its shader default; factory now explicitly sets zero. Failed test is retained.

GPU p95 milliseconds: off6.276, on6.171, off7.273 (90frames each). No clear
increase observed; do not interpret lower on-time as a speedup or precise overhead.
Whole-frame initial sample p9518.827ms still fails18.5ms gate. No thermal or
sustained60FPS qualification. This is optional art review, not a new default.
