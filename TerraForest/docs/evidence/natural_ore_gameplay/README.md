# Natural cave ore: gameplay and compound persistence

2026-10-15, report geology_rewards_route/20261015T191659635079Z.
The original cave preparation stage was cloned to an exclusive disposable world.
Its source hash remained unchanged. No human save was modified.

A read-only native generator6/seed1703 survey checked 18,714 downward rays
inside the existing cave capsules. Naturally exposed floor candidates have
upward normals, headroom and solid ore half a metre below the surface. Iron:
(722.286,82.385,399.914), capsule0. Copper:
(1457.034,74.697,1455.276), capsule16. No access tunnel, ore brush or terrain
generation change was used. This is an offline test survey, not runtime work.

The normal world scene loaded the copied save. The fixture relocated the player
to each candidate, awaited actual collision, found nearby floor by physics ray,
equipped the pickaxe and called the ordinary WorldAttack attack path. One iron
strike removed two iron samples and delivered two iron items; one copper strike
removed one copper sample and delivered one copper item. All four reward types
were compared against native removed-sample counts, including zero changes.
Pickaxe wear increased and no material remained pending with available space.

Each strike changed a 27-point authoritative density sample around the surface.
After ordinary compound saving and a fresh-process reopen, exact inventory bytes
(including tool wear) and both sets of edited density values matched. The inbox
remained empty. The source canonical hash was checked again after both phases.

Both graphical phases passed the fullscreen1920x1080/full-render-scale check.
Screenshots were inspected: ore material colors and excavation are visible, but
headlamp highlights are strong and the exposed geometry remains visibly faceted.
The HUD showed 30 and 46 FPS at the captures; this is NOT a 60 FPS qualification.
Fresh reopen retained a 153.64 ms terrain receive hitch. No runtime optimization,
art acceptance or sustained-mining claim is made.

This verifies natural ore interaction and sampled edit/reward persistence at
two sites. It does not establish a continuous walking/discovery route from the
entrance, all-seed coverage, every mesh vertex or collision after reload, or
long-session behavior. Existing 60 m cave walking evidence remains separate.

Reproduce: python tools/run_geology_rewards_route.py --natural --source
cave_stage_7715b685870243ae972039d1ac7294de

The final fixture additionally rejects non1703 source seeds explicitly; the
recorded successful source is1703. Water and actor runtime remain unchanged.
