# Ground-cover mesh LOD, 2026-10-11

These remain provisional procedural visuals. Persistent identities, removal,
placement, inventory and batching are intended runtime systems; the meshes are
replaceable assets. This result does not qualify final vegetation art, biome
variety, wind, representative density, GPU cost or laptop thermal sustainability.

The shared startup meshes now supply a second index buffer to Godot's native
ArrayMesh LOD renderer. Near triangles remain 54/28/15 for stone/plant/grass;
distant triangles are 12/14/5. All seven plant leaves and five grass blades remain,
with simplified folds/bends. Stones retain a closed silhouette. No identities,
transforms, density, picker bounds, save formats, scripts per instance or runtime
LOD loops were added. Existing native draw pages determine the LOD unit, so one
near portion can keep a whole page detailed. Transitions are discrete, without
fading. LOD vertices share the asset allocation and modestly increase its memory.

The 28-check graphical fixture uses the actual native static batch with 256
identities per species, at fullscreen1920x1080/cap60. Near images with LOD on/off
are byte-identical. Near/far counters match both mesh tiers; placement snapshots
and IDs remain identical. All vertices/normals stay inside the interaction
envelope. `gallery.png` magnifies high detail (back) and forced distant detail
(front) for inspection; this is not the normal transition distance.

The initial three failures are retained. Godot ed1daf0bf's Forward+ primitive
counter does not multiply by instance count in its LOD branch, but does when LOD
is disabled. The corrected fixture compares near/far through the same LOD branch
and validates exact per-page counts; it does not claim the misleading raw
13824-to-24 count as a reduction in all submitted triangles. See the matching
[engine source, lines 995-1017](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L995-L1017)
and [ArrayMesh LOD API](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html#class-arraymesh-method-add-surface-from-arrays).
No engine source was copied into the implementation.

Actual-world interaction/exclusion regression passes 66 checks with the new
assets and an isolated cache. The first run passed interaction checks but failed
the cap assertion after OS focus changed: normal background policy reduces the
cap to15. Its evidence is retained. The automated fixture now sets both its
foreground and background caps to60 before startup, so the full check sustains
the requested cap irrespective of focus. Normal gameplay policy is unchanged.
Both runs were temporary and skipped canonical saving.

This closes the missing mesh-LOD path for the current assets only. The earlier
ground-mesh GPU gate failure remains open; fewer distant triangles do not prove
GPU-time savings or mixed-world headroom. Final assets need their own LOD quality
and representative mixed-density qualification.

Commands (from TerraForest):

```powershell
python tools/run_godot_check.py ground_mesh_lod --timeout 30 --require "GROUND_MESH_LOD"
python tools/run_godot_check.py ground_cover_interaction_world --timeout 90 --require "GROUND_COVER_INTERACTION_WORLD failures=0" -- --ground-cover --gameplay-construction --reject-ground --disturb-ground
```
