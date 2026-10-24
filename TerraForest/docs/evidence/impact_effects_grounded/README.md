# Grounded impact appearance and preserved baseline — 2026-10-24

The user accepted the original feel as a useful fallback but found its appearance
too cartoonish. The full baseline is tagged `impact-effects-baseline-v1` at
`b245d563`. The baseline particle/spatial shader files are unchanged, and its
original geometry, color, counts, sizes and motion remain selectable without
reverting code. **ESC > Session > Impact appearance** offers **Grounded** and
**Original baseline**. Switching clears current emitters and persists the choice.
The master and breakup switches continue to work independently.

Grounded replaces uniformly round clods with offline-baked closed 20-triangle
chips and a size distribution weighted toward grit. The already imported boulder
granite supplies mineral surface detail; muted material colors tint it. No new
AI image was generated for this revision. UV offsets vary between fragments.
The mesh baker is `tools/bake_impact_fragments.py`; shared meshes are loaded once
per style/shape, with no runtime vertex loop. Spin is integrated on the GPU and
damped by ground friction. The two original baseline shaders remain unmodified.

Nonmetal bursts dedicate three slots (six for breakup) to small translucent dust
sheets. One native-generated 128px noise texture and a soft radial mask prevent
rectangular borders. Dust is included in the existing 48-slot emitter capacity.
Its second draw pass adds some transparent rendering cost; no claim of zero cost
or low-end qualification is made. Sparks use camera-facing tapered ribbons,
pale hot centers, orange cooling and shortening streaks instead of solid yellow
boxes. Effects stay under one second, with eight pooled emitters (384 slots), no
particle physics bodies and no per-frame/per-particle GDScript.

## Checks and visual review

- `source_grounded/`: 39 passing checks, run `20261024T162124409609Z_impact_effects_source`.
- `source_baseline/`: 39 passing checks, run `20261024T162216593270Z_impact_effects_source_baseline`.
- `packaged/`: 39 passing checks on the final exported shaders, run
  `20261024T162619160282Z_impact_effects_pack`. Package hash and launch/test provenance
  are retained. Both source and packaged tests use temporary worlds, isolated
  cache folders and empty/separate effect settings, not existing saves/preferences.
- `visual/`: GPU fixture run `20261024T161933816943Z`, with early/middle/late motion
  frames. Source fixture captures precede a small correction to dust/fragment
  lighting normals; the packaged captures contain that correction.
- Export/startup passed with fourteen external native libraries; final package
  size at verification was 280,678,208 bytes. No native rebuild was required.

The integrated tests cover actual tool contact, damage/wear with effects disabled,
cancelled swing suppression, breakup toggle, native material prefetch, excavation
and rewards, pool overflow/reuse/retirement, live ESC style switching, saved style
restoration and shutdown. Both styles' in-world contact captures and the grounded
settings UI were inspected. Grounded shows fine pale sparks, smaller irregular
chips and subtle dust; the baseline retains its round brown clods. New-style user
acceptance remains open. These are visual feature checks, not sustained frame-time
measurements. Ground-plane and fallback-material limitations remain unchanged.

The shared checkout contained separate pickaxe experiments during verification;
their paths appear in manifests. They were not changed or staged by this feature.
Earlier baseline failures remain documented in
[the original evidence](../impact_effects/README.md); this revision had no failed
feature checks. An editor import reported the existing nested ZombieLab project
being ignored; no impact shader/runtime errors occurred in the checks.

```powershell
python tools/check_impact_effects.py
python tools/check_impact_effects.py --baseline
python tools/run_godot_check.py impact_effects_visual --timeout 25 --require 'IMPACT_EFFECTS_VISUAL failures=0' -- --effects-evidence=res://reports/impact_effects_grounded/visual
python tools/export_pack.py --godot $env:GODOT_EXE
python tools/check_impact_effects.py --pack
```
