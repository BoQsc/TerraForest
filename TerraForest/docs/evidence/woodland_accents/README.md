# Woodland accents, 2026-10-11

Adds white, gold and violet wildflowers, a low leafy bush, and dry twig clusters.
Original procedural 0BSD assets, opaque shared meshes with a cheaper distance LOD.
No per-plant nodes or physics bodies. Mesh generation is startup authoring only.
Native scatter, state, picker and batched rendering retain the same total candidate,
owner and authored-item caps. Eight species collections replace three.

Natural accents replace a small subset of grass, preserving IDs/positions and all
removal masks. Existing stone/fern assignments and authored species stay unchanged.
At 16,384 deterministic candidates: 165 flowers (1.01%), 288 bushes, 336 twigs.
Flowers have independent inventory items; twigs yield one existing wood (102),
and gameplay twig placement costs the same one wood. Free editor placement remains free.
H selects ground cover; keys 1-8 select stone, fern, grass, white/gold/violet flower,
bush and twigs. Inventory flower/bush items can be equipped as before.

Storage component key remains ground_cover_edits_v1 for archive lookup compatibility.
Its internal native format writes version 2 and reads both versions 1 and 2.
Version 1 cannot encode the new species. New saves are not backwards readable by
older binaries; new binaries restore old saves without changing authored identities.

Checks: 32 accent checks (bounds, triangles, all eight picks, v1/v2 restore,
rarity, UI catalog contract, actual wood reward and duplicate collection rejection);
27 release-DLL state checks; scatter/picker/stream regressions; full world interaction
check passes with all eight inventory selections, rejected actions and terrain,
building and water disturbances. Four packaging contract checks pass.

Preview: 946 supported published records: 18 stones, 63 ferns, 818 grass, 12 flowers,
16 bushes and 19 twigs. Fullscreen 1920x1080, cap 60. Frame p95 18.768ms misses
18.5ms gate; GPU p95 5.395ms. This short visual sample is not sustained performance
or laptop thermal qualification. Existing thin-grass aliasing remains visible.
The logs retain source/DLL provenance; testing occurred on an uncommitted worktree.
