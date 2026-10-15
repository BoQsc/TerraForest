# Saved cave entrance to natural iron

2026-10-15. Report geology_rewards_route/20261015T195652379214Z.
An exclusive clone of cave_stage_7715b685870243ae972039d1ac7294de starts at its
saved exterior entrance. The fixture verifies that position before walking.
No player relocation, flying, jumping, access excavation, ore injection or
reward grant is used in the walking branch. Water and runtime code are unchanged.

Normal player physics and held-W input follow the native entrance corridor,
then approach the iron-bearing floor. Corridor travel took25.140 seconds;
the final lateral approach took.364 seconds. All101 retained quarter-second
samples report grounded and not loading. This samples contact rather than
proving every intervening physics tick; both endpoints also require grounded
arrival within.4 m. Waypoint Y is ignored for horizontal steering: vertical
movement comes from normal player collision and gravity.

One ordinary pickaxe attack removes two native iron samples and puts two iron
items into inventory, with increased tool wear and no pending rewards. The
27-point authoritative terrain sample changes. Ordinary compound save completes.
Fresh-process reopen restores exact inventory/tool wear and all27 edited density
values. Source save hash remains unchanged. The prior two-site test still covers
copper interaction separately; this new continuous route covers iron only.

Fullscreen1920x1080 at full render scale checks pass. Screenshot inspected:
iron inventory icon and excavation are visible, with the existing faceted
terrain and strong headlamp highlight. HUD53 FPS at capture; startup receive
hitches120.21 ms /134.51 ms. This is correctness coverage, not a sustained
60 FPS or thermal pass.

Remaining: human acceptance, unassisted visual ore discovery, return traversal
after mining, continuous copper route and broader seed/cave coverage. An
automated known waypoint is not proof that a player can easily recognize ore.

Reproduce:
python tools/run_geology_rewards_route.py --walk-iron --source cave_stage_7715b685870243ae972039d1ac7294de

--walk-iron implies --natural; ordinary --natural keeps the separate relocated
two-ore test. The shared completion marker remains COMBINED_RESOURCE_ROUTE.
