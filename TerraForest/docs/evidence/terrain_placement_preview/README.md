# Terrain placement preview — 2026-10-24

Topsoil (211), stone (201), iron ore (202) and copper ore (203) already placed paid
native terrain units, but had no dedicated placement visualization. They now
show a snapped **octahedron**, a thin straight outline and lightly tinted faces.
The initial sphere/rings design was rejected by the user as horrible; it is not
the delivered design. No sphere option remains. Revised user visual acceptance
is still open.

The marker is always available for these held materials independently of the
optional debug overlay. Green means spatial clearance, red explains obstruction
or player/vehicle protection, and amber indicates unavailable collision. A short
caption names the material and right-click action or rejection reason. The debug
box is suppressed while this marker is active. Menus, missing reach, focus loss,
other equipment, developer tools, vehicles and in-progress edits hide the marker.

`terrain_placement.target()` is shared by preview and click; click re-queries live
state. The existing 3.5 m reach, snapped centre, .74 m obstruction sphere and
player/vehicle clearance remain; native world limits and carried-stack availability
are also reported before submission. Eight triangles are created once for the
marker; native ray/overlap queries are bounded to 20 Hz while held. There is no
preview terrain mutation, mesh rebuild, resource payment or CPU voxel scan.
The octahedron's axis tips extend .75 m from the centre, matching the native paid
stamp radius. It illustrates a placement unit; final surface blending depends on
neighbouring density. Native no-op placement/refund remains authoritative.

## Verification

`verified/`: run `20261024T164401151790Z` passes 20 integrated checks in a temporary
forest world with an isolated cache. Tests cover all four held resources, preview
with the debug setting off, zero preview-side mutation/payment, an actual right
click paying for exactly the displayed lattice cell, native topsoil readback,
blocked placement without payment, edit/menu/focus/reach/tool hiding and shutdown.
Ready, placed and blocked octahedron images were inspected. The rebuilt PCK is
280,893,484 bytes; export and its native-library startup check passed. The full
interaction check ran against source resources; it was not repeated against the
PCK. Existing player saves and display preferences were not used or changed.

`retained_failures/` contains the first two runs' logs/manifests. Both successfully
placed the previewed unit but had two fixture assertions fail: the material ray
was exactly on a lattice X/Z boundary, and the obstruction prop placed after the
edit caused a target too close to the player. The existing optional material
prefetch uses a floor-based sample and can report a neighbour at such boundaries;
this cosmetic-query approximation is unchanged. The corrected readback samples
the interior of the placed unit, and the prop fixture explicitly provides player
clearance. The original rounded preview image is retained in `rejected_sphere/`.

Separate pickaxe work was present in this shared checkout and is listed in the
manifests. Its files and status entries are excluded from this feature commit.

```powershell
python tools/run_godot_check.py terrain_placement_preview --timeout 100 --require 'failures=0' -- --gameplay-construction --ground-cover --no-zombies --preview-evidence=res://reports/terrain_placement_octahedron_verified
python tools/export_pack.py --godot $env:GODOT_EXE
```
