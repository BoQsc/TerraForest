# Flesh hit blood, 2026-10-24

Adds brief dark-red droplets and a small mist spray at accepted flesh contact
points. Zombie bodies use their evaluated surface hit; damageable props opt in
with an explicit cosmetic material marker. Overall/limb health, tool wear,
animation contact timing, durability and saves retain their existing ownership.
Both impact appearance modes support blood, using the existing master toggle
and the same eight-emitter / 384-slot GPU pool. No new physics bodies,
persistent decals or per-frame GDScript particle work.

## Checks

- `visual`: 46 checks, including classification, invalid/repair rejection,
  changing flesh/stone/metal within a reused emitter in both appearance modes,
  expiry, saturation and immediate disable. Timed captures were inspected:
  local dark-red spray, falling droplets, short fade, no glowing red chips.
- `grounded` and `baseline`: 39 existing world-impact checks each, covering
  actual metal and terrain contact, destruction, cancelled swings, damage/wear,
  menu preferences, emitter limits and resource reuse.
- First visual run `20261024T193237448679Z` exposed an out-of-range draw-pass
  access when clearing an already removed dust pass. The redundant access and
  its matching test getter were removed. The corrected visual run
  `20261024T193402060796Z` passes without engine/script errors.
- Initial live-world run `20261024T193303843355Z`: 17 checks, including a real
  zombie hit, impact timing/position, unchanged damage/wear, misses, cancellation,
  master disable, a tagged native prop, repair/rejected-damage suppression and
  return to a nonblood material. Its screenshot was inspected in forest lighting.

- `source_world`: the final corpse-inclusive run
  `20261024T193515799985Z` passes all 20 checks without engine/script errors.
- `packaged_world`: `20261024T193647660894Z_blood_pack` passes the same 20
  checks against the exported game, including a real corpse contact. Live and
  corpse screenshots were inspected. Export and startup smoke both pass;
  `dist/TerraForest.pck` and its 14 external native libraries are updated.

The synthetic prop fixture is not a newly added flesh asset. No performance claim
is made for low-end hardware, and visual feel still needs player acceptance.
The previously recorded full-world ragdoll settling failure is outside this
cosmetic change; a corpse hit check is not a settling qualification.

## Reproduce

Run from the TerraForest project directory:

```powershell
python tools/run_godot_check.py blood_effects --timeout 60 --require 'failures=0' -- --effects-evidence=res://reports/blood_effects/visual
python tools/run_godot_check.py blood_effects_world --timeout 100 --require 'failures=0' -- --world-generator=21 --gameplay-construction --zombies --nearby-first --effects-evidence=res://reports/blood_effects/world
python tools/check_impact_effects.py
python tools/check_impact_effects.py --baseline
```

Checks use temporary worlds and isolated effect preferences, not player saves.
Package verification uses the same external test script with `dist/TerraForest.pck`;
the retained manifest identifies its command, source/test/pack hashes and result.
