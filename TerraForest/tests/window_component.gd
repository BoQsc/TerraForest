# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func ray() -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,2),Vector3(0,1,-2),2))
func settle() -> void:
	for i in 12:await physics_frame;await process_frame
func run() -> void:
	check(load("res://demo/world.tscn")!=null,"production world scene and window catalog parse")
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(world.prepare(),"structure world prepared")
	var entry: Dictionary=preload("res://addons/structures/window_catalog.gd").register(world)
	check(not entry.is_empty(),"window registered through production catalog")
	if entry.is_empty():world.free();quit(1);return
	var batch: Node3D=entry.collection
	check(entry.mesh.get_surface_count()==2,"window shares separate frame and transparent glass surfaces")
	check(batch.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])),"window placed with stable identity")
	batch.set_collision_focus(Vector3.ZERO);await settle()
	check(not ray().is_empty(),"glass blocks passage through window opening")
	var saved: PackedByteArray=batch.capture_snapshot()
	check(batch.remove_instances(PackedInt64Array([1])),"window removal accepted")
	await settle();check(ray().is_empty(),"removed window leaves no invisible collision")
	check(batch.restore_snapshot(saved),"window snapshot restored")
	await settle();check(not ray().is_empty() and batch.capture_snapshot()==saved,"restored window retains exact placement and collision")
	world.free();print("WINDOW_COMPONENT failures=",failures);quit(1 if failures else 0)
