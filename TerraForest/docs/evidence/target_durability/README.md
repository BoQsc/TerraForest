# Target durability beside the crosshair

2026-10-23. A reused, mouse-transparent HUD panel shows the last successfully
damaged target's name, current/max durability and green/amber/red bar. It lasts
2.2 seconds, fading over the last 0.35 seconds. Hits refresh the same control;
destroyed targets show zero. Inventory clears it immediately. Menu, development
and released-mouse focus suppress it. Idle processing is disabled.

World attacks reuse the native durability transaction result after acceptance.
Character attacks use the struck region's existing health after the accepted hit.
No raycasts, native health polling, target nodes or per-hit tweens are added.
Damage amounts, targeting, tool wear, storage and destruction rules are unchanged.

## Verification

- `world_attack`: 73 checks, zero failures. Real block picking/hits, all four
  tools, exact current/max values, zero on destruction, cooldown rejection,
  protected furniture rejection, expiry, inventory/menu clearing, refreshed hits,
  tree harvest, furniture salvage, actors, vehicles, cover and terrain excavation.
- `character_world`: 19 checks, zero failures. A strike through the actual world
  picker displays the live hit region's health and preserves existing tool wear.
- `block_hit.png` and `object_hit.png`: full 1920x1080 rendered captures inspected.
  The panel is readable, above/right of the crosshair and outside the toolbelt.

These are finite functionality and visual checks, not sustained performance or
thermal qualification. Generation quality is outside this presentation change.

```powershell
python tools/run_godot_check.py world_attack --timeout 90 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py character_world --timeout 90 --require 'failures=0' -- --gameplay-construction --zombies
```

## Earlier failures

The first launch could not load missing local imported textures/player model.
A headless editor import rebuilt that disposable cache. The next launch omitted
the documented gameplay/cover flags and ran in development mode: 30 failures,
including intentionally disabled gameplay attacks. The correctly configured run
passed all but inventory clearing: the panel remained visible until its next
process tick. Inventory opening now clears it synchronously; the final run passes.
Retained manifests and logs identify these attempts separately from the passes.
