# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var world: Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(world);world.set_process(false)
	var records:=PackedInt32Array()
	for i in 512:records.append_array(PackedInt32Array([(i%32)*16,0,(i/32)*16,1]))
	check(world.set_cells(records),"512 spatially separated authored chunks")
	var before: int=world.collision_stats().readiness_chunk_probes
	var clear:=true
	for i in 1000:clear=world.is_collision_region_ready(AABB(Vector3(0,2,0),Vector3.ONE)) and clear
	var small: int=world.collision_stats().readiness_chunk_probes-before
	check(clear and small==1000,"1000 local empty-space queries probe one chunk each despite distant construction")
	before=world.collision_stats().readiness_chunk_probes
	check(not world.is_collision_region_ready(AABB(Vector3(496,0,240),Vector3.ONE)),"far unbaked occupied cell remains unavailable")
	check(world.collision_stats().readiness_chunk_probes-before==1,"far occupied query probes only its chunk")
	before=world.collision_stats().readiness_chunk_probes
	check(world.is_collision_region_ready(AABB(Vector3(-1e8,2,-1e8),Vector3(2e8,1,2e8))),"wide sparse empty layer remains ready")
	var wide: int=world.collision_stats().readiness_chunk_probes-before
	check(wide==512,"wide sparse query scans authored records rather than billions of empty coordinates")
	before=world.collision_stats().readiness_chunk_probes
	check(world.is_collision_region_ready(AABB(Vector3(2e7,0,0),Vector3.ONE)),"finite query beyond authored domain is empty")
	check(world.collision_stats().readiness_chunk_probes==before,"outside-domain query touches no chunk records")
	check(not world.is_collision_region_ready(AABB(Vector3(-1e8,-1e8,-1e8),Vector3(2e8,2e8,2e8))),"huge finite volume still detects unfinished construction")
	print("READINESS_PROBES ",JSON.stringify({"chunks":512,"local_queries":1000,"local_probes":small,"wide_probes":wide}))
	world.free();print("BUILDING_READINESS_SCALING failures=",failures);quit(1 if failures else 0)
