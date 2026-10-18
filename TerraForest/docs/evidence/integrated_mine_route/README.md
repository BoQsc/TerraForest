# Current integrated mine traversal and headlamp

The traversal check now reads the loaded generator identity (11 or 12), validates
the seven mine primitives, and optionally visits both branch chambers. On the
current generated_world_v4 save, the player reached the main chamber, side workings,
main chamber, smaller side chamber, main chamber and surface entrance. No jump,
flight or position correction was used after initial entrance staging. The harness
supplies movement direction to the production native walking/grounded controller;
this is a collision route check, not a human input test. 2,902 physics ticks, 2,882
grounded; all six waypoints passed. Paved access rejects vegetation roots while
adjacent natural terrain remains eligible. Whole check: 72.46 seconds including
loading, at 1920x1080. Source save is read-only.

The screenshots exposed inadequate headlamp reach: the prior 14 m range could
not illuminate the largest chamber's 18 m-radius walls from its centre. The same
single shadowed spotlight now reaches 24 m; energy, angle and shadow settings are
unchanged. A same-view comparison confirms visible chamber walls and passage
edges with the longer range. Initial captures were taken during continuing terrain
publication; the follow-up waits 300 frames before comparing. These are visual
checks, not GPU/thermal or sustained FPS qualification. A final settled 120-frame
sample at each range (14, 24, 32, 14 m) measured p95 16.684, 16.684, 16.683 and
16.699 ms respectively. An earlier 32 m screenshot showed 53 FPS; the final
comparison did not reproduce a range-related slowdown. The shorter 24 m range
already reveals the wall and was selected. Capped samples do not measure GPU
headroom. A larger light range may
include more shadow casters; no performance reduction is claimed.

No cave generation, water, terrain meshing or user save was changed. Mine location
art, ore gameplay and wider world qualification remain separate work.
