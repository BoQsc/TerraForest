# Woodland shape review, 2026-10-11

Response to the human screenshot: thin identical grass fans looked disconnected
from terrain, crossed dry sticks looked artificial, and bushes were hard to see.

Grass now has 26 wider curved leaves from five offset crowns, varied leaf angles,
heights and olive/green colours. Dry growth is standing forked scrub with tapered
pentagonal woody stems and curled dry leaves. Bushes have taller stems and a fuller
crown of broader leaves. Root shading helps ground contact but is not actual
terrain-material blending. Existing procedural vein shading remains; no new image
textures or external assets. All art is original 0BSD.

This remains a visual iteration: repeated clump silhouettes, terrain integration,
close-up bark/leaf detail and thin distant vegetation aliasing remain visible.
The same deterministic 946-item patch was used; density, identity, save schemas,
proxy bounds and native batch scheduling are unchanged. New shapes fit the old
0.8 x 0.75 x 0.8 metre non-stone semantic envelope. No native rebuild required.

Triangle counts (near/far): grass 468/72 (previous 504/72), bush 638/294,
dry scrub 372/136. The first grass revision used 140 distant triangles and failed
the retained 72-triangle budget. It was reduced to 72; the native LOD test's
expected near count was updated to the intentional 468. Initial failure retained.

Validation: 40 accent geometry/LOD/picking/save/resource checks pass; 28 native
batched LOD checks pass; preview support/publication and player handoff pass.
Full-screen 1920x1080, cap 60, unchanged scene placement and camera views.
Final short sample: frame p95 18.506ms (still fails 18.5ms gate), max19.441ms,
GPU p95 6.327ms. Earlier accent revision GPU p95 was5.395ms; these are short
observations, not an isolated attribution or thermal/endurance qualification.
User closed their game before graphical checks. Command/DLL/source provenance
is retained in run files. Testing occurred on an uncommitted worktree.
