# Water layer continuity and compositing

The sole regional water runtime now connects surface corners across adjacent height layers using actual wet connectivity through a full underlying cell. A solid ledge separates pools. A bounded four-column component refuses to merge multiple surfaces in one column. The mesh-local corner cache avoids repeated traversal. Region invalidation includes the four-cell vertical dependency halo. Authoritative water amounts and snapshot format are unchanged.

Twelve native release checks pass: horizontal and vertical region seams, separate diagonal/ledge pools, exact state preservation and edit invalidation. All 34 real-world mining/bucket/save/cache checks pass. Six 1920x1080 graphical assertions pass for nearest-surface compositing, draw-order invariance, visible absorption, underwater floor colour, shallower absorption and untinted foreground geometry.

The shader reads opaque scene colour plus opaque depth and writes water depth without alpha blending. This removes repeated tinting from overlapping water faces: the nearest surface resolves transmitted scene colour once. This requests Godot's screen-colour copy, unlike the earlier cheaper alpha shader. No second camera or reflection pass was added. Godot's screen copy excludes transparent objects, so transparent underwater particles/glass require further integration; multi-interface optics and underwater views are not qualified by these checks.

The final close view removes the dark grid over the main surface but still has stepped shore sections and some small discontinuities. Visual acceptance remains incomplete. Native region mesh max before save: 0.946 ms, excluding upload. Gameplay frame p50/p95/max: 16.665/16.926/54.386 ms, excluding separately recorded screenshot encoding. Sustained 60 FPS is not proven.

Same-view hidden/visible/visible/hidden GPU medians: 3.633/5.043/4.628/3.290 ms. Difference of averaged medians: 1.374 ms. Short samples drift with device clocks and should not be compared as stable benchmark scores to earlier runs. This cost is material on the laptop and remains an optimization target after correctness. No old-laptop thermal claim.

Reference: https://docs.godotengine.org/en/4.5/tutorials/shaders/screen-reading_shaders.html and https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html . Evidence hashes and commands are retained in run.json.
