# Sparse vegetation distribution — 2026-10-19

User direction: retain sparse cover and improve placement, superseding the earlier
proposal to increase production density to the woodland showcase reference.

Native detail placement now gathers existing identities into irregular pockets,
with gentle attraction to stable procedural tree anchors and existing stone
positions. Rare flower colours group locally. Base-layer positions (including
stones), candidate counts, LOD distances, rendering budgets and models are unchanged.
Existing terrain/structure/water exclusions still apply. This is deterministic
placement at cell generation, not per-frame movement or regrowth. Tree anchors use
the seed recipe, independent of current residency or tree harvesting.

One-time compatibility: existing unharvested natural detail may move when an owner
regenerates under this recipe. IDs and saved removals persist; authored placements
are untouched. No source save was written by these checks.

Engineering: ground_scatter, ground_cover_stream, woodland_accents and new
 ground_distribution pass. The new test checks 1024 stable identities per full owner,
owner bounds, unchanged base positions, deterministic anchors, per-ID removal,
storage roundtrip, and the 144-anchor work limit. Representative owner: 560 occupied
one-metre cells, 120 with at least three candidates, 131 anchor-influenced positions.

Visual: inspected normal.png and travel_end.png from the actual saved southern
world at 1920x1080. Loose groups/openings are visible and the sparse character is
retained. This accepts the distribution change only; the distant vegetation still
has noisy silhouettes and the surrounding building/landscape design is not newly
accepted by this test. Final aesthetic acceptance remains with the user.

Timing: clean run median GPU 10.92/10.82 ms, stationary frame p95 19.56/20.23 ms,
worst 21.09/22.06 ms. Six-metre camera travel p95 21.68 ms, worst 29.42 ms.
These are short capped samples, NOT a sustained 60 FPS qualification or an A/B proof
of unchanged cost. An initial run competed with an owned editor import and is
excluded. Screenshot readback is outside timing. No older-laptop thermal claim.

Actual-world collection regression also passes: two collected plants, survivor
transforms and fade ages unchanged immediately and through three subsequent frames.
Collection calls took 6.389 and 3.367 ms. Captured after image inspected; surrounding
cover remains present. These timings are not a claim of improved collection speed.
