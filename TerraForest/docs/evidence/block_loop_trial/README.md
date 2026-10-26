# Existing-block loop experiment — 2026-10-26

Requested visual feasibility trial, rendered in Godot 4.7.2 with the current
native structures addon. No new block shapes, stretched blocks, arbitrary block
rotations, custom track meshes, or changes to the playable world are involved.
Every track and support piece has its own integer one-metre cell and existing
shape/orientation/material word. The native world has an identity transform.

| Assembly | Cells | Shape result |
| --- | ---: | --- |
| Octagonal loop | 1,148 | 20 m opening, eight-metre track; flat panels and 45-degree thin slopes/seams |
| Rounded rectangle | 1,100 | Straight panels and four one-metre-radius quarter-arch corners, repeated across the eight-metre track |

`octagonal_loop.png` and `octagonal_loop_front.png` show the first variant;
`rounded_rectangle_loop.png` shows the alternative. All three final images were
inspected. Each `.tfbl` stores that variant's complete independent block cells.
`manifest.json` records per-shape counts, native statistics and the engine version.

The native batch accepted both assemblies. Their snapshots validated and restored
with byte-identical cell storage; final execution reports two variants and zero
failures. This checks static assembly and storage only. The straight deck is a
staging platform: entry/exit connections, the sharp changes of direction, physics
at the joins, vehicle inversion and actual driving have not been qualified.
In particular, the rounded rectangle is a silhouette experiment, not a smooth
circular track. No world-quality acceptance or runtime performance claim follows.

The ground plane is scenery; the existing vehicle is frozen as a scale reference.
Track materials are the game's existing brick, concrete and metal materials.
No generated artwork substitutes for the native geometry.

Reproduce from the TerraForest project directory with the installed engine:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/Godot Engine.exe' --path . --rendering-method forward_plus --windowed --resolution 1920x1080 --max-fps 60 --script res://tools/preview_block_loop.gd -- --temporary
```

The script writes only this evidence folder and creates a temporary scene; it
does not load or save a player world. Parent `evidence/.gdignore` excludes these
images/snapshots from game imports and exports.

Earlier fixture attempts reported 38 and four cell conflicts respectively between
the support layout and the thin deck/columns. The final recipe moves the tower
posts outside the track, uses one cube cell at each column/deck junction, and
omits the conflicting ground crossbeam. Earlier logs remain in `attempts/`;
they are not counted as passes. The initial script also had an invalid optional
environment enum, removed before either rendered attempt. These were preview
fixture corrections; the native shape catalogue and libraries were unchanged.
