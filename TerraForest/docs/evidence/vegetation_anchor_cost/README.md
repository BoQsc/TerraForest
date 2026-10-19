# Vegetation anchor generation cost — 2026-10-19

Native scatter now validates and copies up to 144 tree anchors once per 64-point
batch, instead of repeating PackedVector access and finite validation per plant.
The exact nearest-anchor order and arithmetic are preserved. Both native targets
built against the pinned prebuilt SDK; no godot-cpp rebuild.

A pre-change capture hashes generated IDs/positions across four seeds and five
owners (interior and map corners), all 16 layers, with 144 anchors. Post-change
SHA256 matches exactly: ad79424d62afe690c4b8321c73c36a5121a55b7ccb8bf522ce8ac65fc22c3e6a.
The test retains this oracle and checks nonfinite anchors are ignored equivalently.
World and owner bounds, counts, per-ID removals, storage and streaming checks pass.

Short headless debug measurements: 243 complete owner generations per anchor count.
Median milliseconds for 0/36/144 anchors before: 0.139/0.607/2.047;
after: 0.138/0.337/0.861. Maximum-anchor p95 before 5.935, after 1.322 ms.
Timing varies with host scheduling (see earlier result in reports); no hard timing
gate, old-laptop claim or overall frame improvement is inferred. Production admits
up to four 64-point layers per wave, not all 16 in one call. Terrain support,
publication, rendering and tree-recipe generation are outside this microbenchmark.

Visual output was not re-rendered because candidate bytes match the prior inspected
production distribution. This does not close sustained 60 FPS, distant silhouette
quality or human acceptance. Current sparse density is now also reflected in the
world-building standard, superseding the obsolete dense-reference requirement.
