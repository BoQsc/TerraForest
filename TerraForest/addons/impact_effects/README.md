# Optional impact particles

0BSD. Experimental, cosmetic effects for successful tool contacts. ESC > Session
has **Impact particles (experimental)** and **Extra particles when objects break**.
Both default on; preferences live in `user://impact_effects.cfg`, outside world
saves. Disabling the master switch immediately removes active emitters.

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
lifetimes are centralized in `impact_effects.gd`; velocity/gravity in the shader.

## Disable or remove

- Toggle it off in ESC, or launch with `--no-impact-effects`.
- Set `terraforest/impact_effects=false` to omit loading the module entirely.
- To remove it from the project, delete this addon folder and re-export. The host
  dynamically checks for it, and its menu controls disappear when absent.
  The optional attack signals and material-query argument can remain harmlessly.

Checks: `tests/impact_effects_world.gd` exercises actual tool contacts, excavation,
settings and pool bounds; `tests/impact_effects_visual.gd` captures GPU motion.
Run the world check with `--no-impact-effects` to exercise omitted-module gameplay.
These checks do not substitute for the player's visual acceptance or low-end GPU
performance measurements.
