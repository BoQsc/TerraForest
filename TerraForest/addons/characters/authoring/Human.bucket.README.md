# Water bucket presentation, hand/use revision 2

The user rejected the first version's hands and fill/pour animation. This revision
rebuilds the hold and action poses; it awaits a new visual review.

The former 16-sided procedural bucket is replaced by a Blender-authored metal
pail with 16,700 triangles: a continuous thick shell and recessed inner floor,
rolled mouth/foot, reinforcing beads, round wire bail, stamped ears/rivets and
a turned wooden sleeve. Steel and wood have embedded 1024px base-color,
roughness and tangent-space normal maps. This artwork is original 0BSD code-generated
geometry/materials; no external texture dependencies are required.

`Human.bucket.blend` contains the editable geometry, packed maps and original
59-bone R11 rig. `Bucket.glb` exports separate pail and bail meshes; `Human.bucket.glb` exports only
the body/rig animation. `tools/import_water_bucket.gd` verifies the unchanged rest
bones, maps bone tracks and clears source pose-specific morphs. The imported
`Human.bucket.res`, `Bucket.held.res`, `Bucket.bail.res` and `Bucket.pickup.res`
are self-contained runtime resources. Pickup geometry combines both parts, translated to centre
its bounds for the existing native pickup renderer.

The right hand holds the sleeve from above with a near-neutral wrist, retaining
the axe's fitted finger curl and the accepted unarmed pose's closed thumb. The
left hand rests low, approaches the base, supports it with a flat palm, then
releases after the pail is lowered. Its transform relative to the pail stays fixed
through the support interval. Its finger directions are explicitly flattened and
the palm offset is fitted to the evaluated skin, preventing fingertips through
the floor. Continuous elbow-roll signs prevent twists between baked keys.
A taller bail gives the forearms clearance when
the base rises. The bucket selects the already repaired
unarmed finger-weight mesh with original materials; other tools restore their
original mesh. `Weapon_Axe` carries the bail/grip, and `Weapon_Pickaxe` carries
the pail. Both ear pivots coincide while the pail tips independently. No new rig
bones or edits to accepted axe/pickaxe animations are required. Arm lengths stay
fixed; elbow paths and forearm roll are solved in Blender and baked, without runtime IK.

Actions, baked at 60 FPS:

- `FP_Bucket_Idle`: two-second static hold.
- `FP_Bucket_Walk`/`Run`: one-second/0.8-second carry cycles, fixed grip and
  original in-place leg gaits. Velocity selects running above 6.5 m/s.
- `FP_Bucket_Jump`: 1.5-second airborne hold/settle.
- `FP_Bucket_Scoop`: 2.4 seconds, with approach, supported forward/down dip,
  lift, return upright and release.
- `FP_Bucket_Pour`: 2.8 seconds, with support, a 100-degree tip away from the
  eyes, a deliberate hold, upright recovery and release.

The pose tables use monotone cubic interpolation and are sampled at 60 FPS.
They replace the original single sine pulse. Grip, hinge, support, wrist and
forearm-volume checks sample the imported clips at 120 Hz, including interpolation.

Use clips follow the existing successful water transaction. They do not delay,
authorize or repeat transfer, emit attack events, consume wear, or move the motor.
Both immediate and pending completions already refresh equipment before calling
the presentation gesture. `demo/world.gd` now passes the active slot's `water_ml`
to the view, since current empty/full buckets both use item 401. Legacy IDs
401–411 remain supported. The interior surface shows empty/full/older partial
state and hides on tool switches or placement. Only the visible fill follows the
gesture: a pour empties at 0.60–1.00 seconds and a scoop fills during the upright
lift at 1.65–1.90 seconds. Inventory and native water already contain the confirmed
result; presentation never grants or removes water.

The water surface is a simple contained visual, without slosh simulation or a
pouring stream. The gameplay's existing one-cubic-metre unit is unchanged; this
small pail's geometry does not claim a physical one-cubic-metre capacity.
The fixed wrist transforms are authored, while the existing short runtime blend
between clips is ordinary bone interpolation. Appearance awaits user playtest;
close-up skin/sleeve finish inherits the current character's limitations.

Rebuild from `TerraForest`:

```text
blender --background --disable-autoexec addons/characters/Human_R11_Complete_Repost/Human.r11.blend --python-exit-code 1 --python tools/author_water_bucket.py
godot --headless --path . --script res://tools/import_water_bucket.gd
godot --headless --path . --script res://tests/water_bucket_visuals.gd
godot --path . --windowed --position -32000,-32000 --script res://tests/bake_bucket_icon.gd
godot --headless --path . --script res://tools/ensure_item_icons.gd
godot --path . --windowed --position -32000,-32000 --disable-render-loop --script res://tools/preview_water_bucket.gd -- --video
blender --background --factory-startup --python-exit-code 1 --python tools/encode_water_bucket_preview.py
godot --path . --windowed --position -32000,-32000 --max-fps 60 --script res://tests/water_bucket_visuals_world.gd -- --temporary --world-slot=bucket_visuals_review --derived-cache=user://bucket_visuals_review --water-gameplay --water-bucket-review --gameplay-construction --no-zombies
```

The graphical test uses a disposable world, real mouse admission and native water
transfers. Studio capture timing is sampled at 30 FPS and is not a performance test.
See `docs/evidence/water_bucket_visuals/` for checked renders and reports.
