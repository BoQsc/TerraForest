# Near vegetation cast-shadow correction

2026-10-18. Saved southern world, fullscreen 1920x1080, 60 FPS cap. Compare unchanged density/models at the same camera pose within each run; vegetation wind disabled for comparison. Existing near cast-shadow residency is unchanged.

Production now explicitly uses four blended directional cascades with split fractions 0.035/0.12/0.35 over the existing 256 m range and a 4096 atlas. The old first split was 0.1 with a 2048 atlas. This concentrates resolution close to the player, resolving cast shadows better than the previous broad, soft silhouettes. Images were inspected; production focused_4096 was inspected after final configuration verification. Terrain bias 0.1 / normal bias 2.0 retained. Lower normal bias 0.7 showed insufficient benefit to justify reintroducing known broad-terrain acne risk.

Latest sequential GPU medians: baseline 10.144 ms, focused 2048 10.198 ms, focused low bias 10.582 ms, focused 4096 10.391 ms. Prior comparison was 10.457/10.173/10.540/10.709 ms. These short samples suggest a modest cost, not a reliable fixed delta or thermal qualification. Atlas pixel storage is four times the previous size. Screenshot readback excluded from samples.

Test verifies production settings and world loading/cover publication; numerical success does not prove subjective quality. Moving-view cascade stability, slopes and broader terrain-acne checks remain open. No density reductions, altered models, lower-detail nearby shadow replacement, or user-save writes.
