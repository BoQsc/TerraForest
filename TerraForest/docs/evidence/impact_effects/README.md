# Optional material impact particles — 2026-10-24

The experimental addon emits sparks on metal blocks, metal props, vehicles and
native metal terrain. Dirt/topsoil, rock, brick, concrete, wood, sand, snow and
ore have small colored fragments. These use shared low-poly oval/box meshes with
random size, aspect, velocity, rotation and lifetime. Sparks fade sooner than
clods; fragments scatter, fall, make a short local-plane bounce and fade.

Effects run at the existing authored contact frame after an accepted interaction.
There is no change to damage balance, inventory transactions, mining rewards or
save format. Native terrain material/depth prefetch is optional, bounded and
asynchronous; a late/stale result uses a cosmetic slope fallback. Particle motion
runs in Godot's GPU particle shader, with at most eight emitters and 48 slots each.
Emitters retire/reuse, cast no shadows, and create no CPU debris bodies. The master
toggle removes all emitters immediately. Detailed settings and folder removal:
[addon README](../../../addons/impact_effects/README.md).

## Evidence

- `source/`: 34 passing world checks before the final size/color adjustment.
- `packaged/`: 34 passing checks using the final exported pack: actual metal
  contact, no windup/cancel effects, disabled damage/wear, accepted destruction,
  smaller breakup-off burst, native terrain sampling, shovel excavation/rewards,
  bounded overflow/expiry/reuse, saved preferences and clean shutdown.
- `packaged_off/`: five passing checks with `--no-impact-effects`, including
  ordinary attacks and absent module controls.
- `visual/`: GPU fixture and sampled motion frames. The first source screenshots
  showed thick sparks and oversized clods; final scale is smaller, sparks thinner
  and fragment aspect more varied. Early, middle and late final frames were
  inspected, as were final packaged metal/terrain contact and ESC screenshots.
- `retained_failure/`: compressed logs and manifest from the initial shader
  compilation error (Godot does not allow `return` in particle processors) and a
  fixture-only call to nonexistent inventory `add_item` instead of `grant`.
  Both were corrected. The test timed out after that fixture error; it is not
  counted as a successful run. The initial compile error caused repeated renderer
  diagnostics; the successful reruns have none.

Source runs: `20261024T160508516105Z`; GPU fixture: `20261024T160740439253Z`;
packaged: `20261024T160904300350Z_impact_effects_pack`; omitted module:
`20261024T160944413607Z_impact_effects_pack_off`. Manifests record commands,
source/test/engine and package provenance. Export produced a 280,660,672-byte PCK
and its startup check passed with fourteen external native libraries. Tests used
temporary worlds, isolated derived caches and separate/empty effect settings;
existing player saves and preferences were not used.

These checks cover engineering integration and inspected appearance, not the
user's visual acceptance or sustained frame times on low-end hardware. The effect
remains explicitly experimental. Its single floor plane cannot follow detailed
terrain or collide against arbitrary objects. Natural terrain classification is
an approximation when no current worker sample is available.

```powershell
python tools/check_impact_effects.py
python tools/run_godot_check.py impact_effects_visual --timeout 25 --require 'IMPACT_EFFECTS_VISUAL failures=0'
python tools/export_pack.py --godot $env:GODOT_EXE
python tools/check_impact_effects.py --pack
python tools/check_impact_effects.py --pack --off
```
