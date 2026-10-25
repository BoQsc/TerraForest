# Water bucket presentation

The former 16-sided procedural bucket is replaced by a Blender-authored metal
pail with 16,700 triangles: a continuous thick shell and recessed inner floor,
rolled mouth/foot, reinforcing beads, round wire bail, stamped ears/rivets and
a turned wooden sleeve. Steel and wood have embedded 1024px base-color,
roughness and tangent-space normal maps. This artwork is original 0BSD code-generated
geometry/materials; no external texture dependencies are required.

`Human.bucket.blend` contains the editable geometry, packed maps and original
59-bone R11 rig. `Bucket.glb` is the rigid export; `Human.bucket.glb` exports only
the body/rig animation. `tools/import_water_bucket.gd` verifies the unchanged rest
bones, maps bone tracks and clears source pose-specific morphs. The imported
`Human.bucket.res` and `Bucket.held.res`/`Bucket.pickup.res` are self-contained
runtime resources. Pickup geometry has the same surfaces, translated to centre
its bounds for the existing native pickup renderer.

The right hand wraps the wooden sleeve throughout each action. It reuses the
axe's static finger curl and the accepted unarmed pose's closed thumb. The left
hand retains the accepted relaxed pose. The bucket selects the already repaired
unarmed finger-weight mesh with original materials; other tools restore their
original mesh. The existing `Weapon_Axe` bone carries the rigid bucket; no new
rig bones or changes to accepted axe/pickaxe animations are required.

Actions, baked at 60 FPS:

- `FP_Bucket_Idle`: two-second static hold.
- `FP_Bucket_Walk`/`Run`: one-second/0.8-second carry cycles, fixed grip and
  original in-place leg gaits. Velocity selects running above 6.5 m/s.
- `FP_Bucket_Jump`: 1.5-second airborne hold/settle.
- `FP_Bucket_Scoop`/`Pour`: one-second/1.2-second cosmetic use/recovery.

Use clips follow the existing successful water transaction. They do not delay,
authorize or repeat transfer, emit attack events, consume wear, or move the motor.
Both immediate and pending completions already refresh equipment before calling
the presentation gesture. `demo/world.gd` now passes the active slot's `water_ml`
to the view, since current empty/full buckets both use item 401. Legacy IDs
401–411 remain supported. The interior surface shows empty/full/older partial
state and hides on tool switches or placement.

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
