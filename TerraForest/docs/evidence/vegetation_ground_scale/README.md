# Ground vegetation texture scale — 2026-10-18

Readonly combined world northern_common_42_20261018. Fullscreen 1920x1080 cap60,
RTX4050 laptop. Tests/vegetation_ground_scale.gd compares grass texture scale
multipliers 1, 2.5, 4, 1 with identical selected understory shadow casters.
Inherited phase-name suffixes do not indicate changes to shadow settings.

Inspected 2.5 and 4 against the existing ground view. Selected 2.5: the texture
repeat is now 2 metres rather than 5, reducing the oversized tangled turf pattern
between half-metre plant models. 4 loses more visible ground detail. The change is
limited to the grass-biome texture coordinates and matching explicit gradients;
rock, sand, snow, asphalt, models, lighting, density and gameplay are unchanged.
It adds no texture fetches, assets, geometry, passes or CPU work.

GPU medians 7.836 / 7.811 / 7.796 / 7.808 ms; no meaningful cost difference proven.
Selected phase frame p95 17.904 ms, worst18.723 ms. No strict 60FPS/thermal claim.
Shader compiles and runs in the saved world. The inherited travel check occurs
at the restored baseline scale, so is not additional selected-scale evidence.

This modest correction does not settle overall vegetation art direction. Existing
clump repetition, landscape design and performance goals remain open. Human
review is still needed; the original texture/model assets are retained.
