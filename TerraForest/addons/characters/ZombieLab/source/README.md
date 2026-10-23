# Editable zombie sources

- `Zombie.blend`: exact preserved F1 Original / Main source.
- `Zombie.r2.blend`: exact preserved F2 original alternate source.
- `Zombie.r4.blend`: current R4 model, corrected rig/weights, all 15 animation clips and synchronized mouth, knee-bend, two-hand drape and left-collar morphs.
- `author_behaviors.py`: reproducible native Blender authoring for the R4 expansion. Its input is the previous R4 source in `../archive/r4.previous/`.
- Additional authoring/export support is included beside the script.

R3 is deprecated and kept in `../archive/r3/`. The previous R4 remains in `../archive/r4.previous/`. Neither is used as the current model by the lab.

The source was authored and validated in Blender 4.5.3. Textures are packed into the Blender files and embedded in the GLBs. Rig actions use their `Zombie_*` names. The `morph_actions` table in the behavior contract maps each mesh to its shape keys and action prefix. Shape-key actions use identically named `Zombie_*` NLA tracks so the GLB exporter combines them with the skeleton in the same animation clip. All added morph weights remain zero in the four preserved base clips.

See the root README, `../assets/Zombie.r4.behavior.json`, and the authoring script's command-line arguments for timing, root-motion and export details. F1/F2 originals are not inputs to R4 authoring and must remain unchanged.
