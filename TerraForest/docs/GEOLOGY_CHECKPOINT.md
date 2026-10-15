# Underground geology checkpoint

On a new installation, run `Prepare Geology Checkpoint.cmd` once, then `Play Geology Checkpoint.cmd` from TerraForest. Preparation authors the two access tunnels in a unique staging save, walks both, reopens and walks them again, then publishes `geology_gameplay` only if absent. Existing gameplay progress is never regenerated. It opens a separate locally saved world in gameplay mode, at the iron tunnel entrance, facing into the tunnel. Your settlement checkpoints are unchanged. The launcher preserves the historical checkpoint if it exists; otherwise it uses the reproducibly prepared save.

Press **F** to turn on the headlamp, then walk forward along the sloping tunnel. The grey iron vein is at the end. Equip the pickaxe and hold left mouse to mine. Mined resources enter inventory automatically when space is available; open **Tab** to inspect them and use the crafting panel. **F5** saves. The headlamp starts off each launch and uses one 14 m shadowed engine spotlight; its GPU cost has not yet been qualified.

A second authored tunnel exposes copper. Its entrance is at [328.0, 90.28734, 332.0], with ore at [368.0, 109.0, 332.0]. Both entrance-to-face routes passed automated on-foot movement without jumping, including after a fresh-process reload. The terrain between the two entrances has not been route-tested.

These are authored access tunnels to seeded deposits, not proof of natural cave discovery. Ore colour and texture are visible, but exposed faces remain visibly faceted. Mining continuity and sustained frame/thermal qualification remain open. The screenshots' 60 FPS HUD is not a performance test.

Prepared slot: `geology_gameplay`. Historical slot: `geology_access_1791586170375323500`. Preparation evidence: `docs/evidence/geology_preparation`; historical route samples: `docs/evidence/geology_access`. The new preparation check covers access and disk reopening, not reward amounts or sustained mining.

2026-10-15 interaction check: in a disposable copy, a normal pickaxe attack at each exposed face yields one iron ore and one copper ore respectively. Both items appear directly in carried slots; tool wear and exact inventory persist after a fresh-process reopen. Evidence: `docs/evidence/geology_rewards_route`. This is a two-strike correctness check, not sustained mining or a performance qualification.
