# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var planner: RefCounted=ClassDB.instantiate("NativeTerrainPlanner")
	var active: Dictionary={Vector2i(0,0):true}
	check(planner.collision_region_ready(AABB(Vector3(4,50,4),Vector3(3,2,5)),active),"body wholly inside ready cell")
	var seam:=AABB(Vector3(14,50,4),Vector3(3,2,5))
	check(not planner.collision_region_ready(seam,active),"center-cell readiness cannot hide unloaded neighbor")
	active[Vector2i(1,0)]=true
	check(planner.collision_region_ready(seam,active),"seam ready once both cells published")
	check(not planner.collision_region_ready(AABB(Vector3(4,50,4),Vector3(28,2,5)),active),"far boundary cell required for swept bounds")
	active[Vector2i(2,0)]=true
	check(planner.collision_region_ready(AABB(Vector3(4,50,4),Vector3(28,2,5)),active),"complete swept corridor accepted")
	active[Vector2i(1,0)]=false
	check(not planner.collision_region_ready(seam,active),"false publication flag rejected")
	check(not planner.collision_region_ready(AABB(Vector3(-1,0,0),Vector3.ONE),active),"outside world rejected")
	check(not planner.collision_region_ready(AABB(Vector3(1999,0,0),Vector3.ONE),active),"far world edge rejected")
	check(not planner.collision_region_ready(AABB(Vector3.ZERO,Vector3(-1,1,1)),active),"negative extent rejected")
	check(not planner.collision_region_ready(AABB(Vector3(NAN,0,0),Vector3.ONE),active),"nonfinite bounds rejected")
	quit(0 if failures==0 else 1)
