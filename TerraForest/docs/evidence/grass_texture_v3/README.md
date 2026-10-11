# Grass surface grain v3, 2026-10-11

Human request: fine grain, small realistic surface marks and darker tones instead
of cartoonish vein stripes. Generated with built-in image_gen. Source PNG bytes:
`../../../addons/world_ecosystem/art/grass_detail_v3.trtex`; exact prompt:
`../../../addons/world_ecosystem/art/grass_detail_v3.prompt.json`.

Optional F7 trial, default off. Shared256x256 mipmapped texture, one texture read,
unchanged shapes, population, save data and native interaction. Existing generated
v1 is preserved; rejected v2 remains archived. No external stock or new dependency.

Material adds fine irregular mottling and aged brown marks; reduces the old
procedural bright rib, lowers specular/backlight and increases matte roughness.
A narrow20%-width texture strip preserves the scale of grain on slender blades;
whole-square mapping was found to stretch grain into vertical streaks. Strip
position varies per clump using its existing stable world-position variation.
One-time colour calibration normalizes the source; a0.90 factor warms down the
base without treating uniform dimming as detail. Blend strength0.8. Mean brightness
can vary by sampled strip: the tested clump is2.7% brighter overall despite darker
local flecks. This is not a claim of globally darker rendered grass.

8 close-up checks pass: exact off restoration and non-uniform detail beyond a
brightness shift (11.9% residual relative to baseline brightness).44 existing
asset/interaction checks pass. Full world support/publication and toggle checks
pass; fullscreen1920x1080 cap60. GPU p95 off/on/off6.474/6.728/6.574ms;
medians6.337/6.263/6.382ms. Short samples do not establish precise overhead or
thermal safety. Frame p9519.062ms still misses18.5ms gate. Static images inspected;
mipmaps remain enabled, but motion shimmer and final realism require human review.

Source/run provenance retained. Shared preview report may be overwritten by
another play session; world_result.json here is extracted from this run's log.
