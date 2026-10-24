# Optional impact particles

0BSD. Experimental, cosmetic effects for successful tool contacts. ESC > Session
has **Impact particles (experimental)** and **Extra particles when objects break**.
Both default on; preferences live in `user://impact_effects.cfg`, outside world
saves. Disabling the master switch immediately removes active emitters.

**Impact appearance** selects **Grounded** (new default) or **Original baseline**.
The original feel was accepted as the fallback on 2026-10-24; its full source is
tagged `impact-effects-baseline-v1` at `b245d563`. Its original `motion.gdshader`,
`fragments.gdshader`, meshes, palette and burst tuning remain available in the
baseline path. Selecting a style clears current emitters and saves the choice;
neither style changes attacks, rewards or world saves. Existing enabled/breakup
preferences are honored when upgrading a settings file without a style key.

Grounded uses offline-baked, closed 20-triangle irregular chips, a shared existing
granite texture for small-scale surface detail, desaturated colors and a size
distribution weighted toward fine grit. Three particles per ordinary nonmetal
hit (six on breakup) are soft dust sheets sampled from one native-baked 128px
noise texture. They are included in the same 48-slot budget, not extra particles.
Chips use one opaque pass; dust uses a second small transparent pass. Sparks use
tapered camera-facing ribbons with a pale hot start, orange cooling and shortening
streaks. Ground contact damps spin as well as translation. Baseline rendering
remains one draw pass and does not create dust resources.

Metal blocks, metal props and vehicles produce warm sparks. Soil, rock, concrete,
brick, wood and other terrain surfaces use colored chips, small oval clods or
splinters. Successful excavation/destruction may use a larger burst. No effect
spawns loot, changes damage, creates physics bodies, or survives in a save.

The world attack adapter emits an optional windup query and an accepted-contact
signal at the existing authored tool contact frame. A bounded native terrain
density query prefetches material/depth on the existing worker. Late, mismatched
or stale results fall back to slope-based soil/stone; they never delay the swing.
Natural terrain material zero uses the current terrain biome/depth/slope rules;
explicit native material IDs take precedence. This is visual classification,
independent of damage types and mining reward accounting.

Godot's native GPUParticles3D and `motion.gdshader` own motion on the GPU. GDScript
only handles events, preferences and an eight-emitter pool. Each emitter has 48
slots (384 maximum); overflow drops the cosmetic burst. Meshes/materials are
shared, shadows are off, bursts last under a second, and retired emitters reuse
their allocation. A single local floor ray per burst supplies a cheap bounce
plane; these are visual debris, not general collision-aware objects. There are
no GDScript per-frame or per-particle updates. Burst count, scale, color and
lifetimes are centralized in `impact_effects.gd`; velocity/gravity in the shaders.
Run `python tools/bake_impact_fragments.py` to rebuild the grounded OBJ meshes;
Godot imports their shared GPU buffers. No mesh generation runs on tool contact.

## Disable or remove

- Toggle it off in ESC, or launch with `--no-impact-effects`.
- Set `terraforest/impact_effects=false` to omit loading the module entirely.
- To remove it from the project, delete this addon folder and re-export. The host
  dynamically checks for it, and its menu controls disappear when absent.
  The optional attack signals and material-query argument can remain harmlessly.

Checks: `tests/impact_effects_world.gd` exercises actual tool contacts, excavation,
settings and pool bounds; `tests/impact_effects_visual.gd` captures GPU motion.
Run the world check with `--no-impact-effects` to exercise omitted-module gameplay.
Use `python tools/check_impact_effects.py --baseline` for the preserved profile;
`--pack` checks either profile against the exported game.
These checks do not substitute for the player's visual acceptance or low-end GPU
performance measurements.
