# Integrated mine resource check — 2026-10-18

Generator 12, seed 1703, saved `generated_world_v4`, read-only session.
The older natural-ore gameplay check covered generator 6, so it did not establish
that the current regional mine had reachable resources.

`regional_ore_survey.gd` probes the three owned chamber floors (327 downward rays)
and finds strong natural iron and copper samples 0.5 m below their surfaces.
Iron: (1608, 10.82324, 1037), main chamber. Copper: (1577, 10.82324, 1063), workings.

`regional_ore_gameplay.gd` loads the actual integrated save, stages the player near
each sample, waits for collision, and performs an ordinary pickaxe attack. Each
strike removes one corresponding ore sample. Inventory deltas exactly match all
reported stone/iron/copper/soil rewards, tool wear increases, and the reward inbox
is empty. No inventory or terrain edits are injected to make the strikes succeed.
The run passes in 23.94 seconds at 1920×1080 fullscreen. Saving is skipped.

The retained log uses the inherited COMBINED_RESOURCE_ROUTE completion label;
the checked-in test now has its own REGIONAL_ORE_GAMEPLAY completion label and
explicit read-only cleanup wording. This label-only correction followed the run.

Limitations: viewpoint staging is not walking or human input. This complements
the separate integrated mine walking check; it is not a continuous expedition or
a save/reopen check. Only seed 1703 is qualified here, not every generated seed.
The iron screenshot was inspected: gathering is working, but bright headlamp
glare and dark surroundings make ore identification weak. Visual discovery and
sustained mining performance are not qualified by this check.

Reproduce the headless survey first with `tools/run_godot_check.py
regional_ore_survey --headless --timeout 30 --require failures=0`, then run the
gameplay script with `--snapshot-readonly --world-slot=generated_world_v4
--ground-cover --actors --vehicle-fleet --gameplay-construction` in fullscreen
1920×1080. The gameplay script rejects sessions lacking read-only mode.
