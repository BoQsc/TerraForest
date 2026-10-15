# Persistent natural-cave checkpoint

Run **Play Natural Caves.cmd**. It prepares a separate `natural_cave_gameplay`
save only when absent, verifies it in a fresh process, then launches normal
resource-cost gameplay at 1920x1080 fullscreen with a 60 FPS cap. Preparation
can take longer on the first launch; subsequent launches reuse the save.

You start on foot outside the generated entrance, facing inward. Walk toward
the opening, select the pickaxe from the toolbelt to mine, and use the inventory
for collected resources and crafting. Esc provides the normal controls menu;
F toggles the headlamp. F5 saves progress. Existing gameplay worlds and the
disposable **Review Natural Caves.cmd** are preserved.

This checkpoint uses existing generator 6, seed 1703, and its native cave
description. It does not excavate an artificial entrance or grant mined ore.
Its ordinary starter inventory is unchanged. It starts at the cave, so it does
not demonstrate discovery or travel from the settlement.

Verified preparation: grounded entrance placement; compound save; fresh-process
restoration of generator/seed, on-foot player position and exact inventory/tool
wear; repeated preparation leaves the published save hash unchanged. Three
protection tests cover existing progress, failed-reopen publication and lock
ownership. Screenshots show the exterior entrance; no new art acceptance or
performance qualification is claimed.

Remaining integration gate: mine and collect naturally exposed ore in this
specific persistent cave world, then reopen and verify the terrain edit and
reward together. Existing authored iron/copper mining/crafting checks and the
60 m natural cave walk are supporting evidence, not that combined gate.

Startup retained existing generated-component capture rejections while the
world was incomplete; the final compound save and fresh reopen succeeded.
Reopen also recorded a 123.45 ms terrain receive hitch. These are not resolved
by this launcher. See `evidence/natural_cave_preparation` for retained logs.
