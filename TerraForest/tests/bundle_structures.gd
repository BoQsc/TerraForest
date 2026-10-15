# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for i in 12:await physics_frame;await process_frame
func blocked() -> bool:
	return not root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.5,1,2),Vector3(0.5,1,-2),2)).is_empty()
func run() -> void:
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(world.prepare(),"bundled native structure world prepares")
	var door: Dictionary=preload("res://addons/structures/door_catalog.gd").register(world)
	var window: Dictionary=preload("res://addons/structures/window_catalog.gd").register(world)
	var rail: Dictionary=preload("res://addons/structures/guardrail_catalog.gd").register(world)
	check(not door.is_empty() and not window.is_empty() and not rail.is_empty(),"bundled building catalogs register")
	if not door.is_empty() and not window.is_empty() and not rail.is_empty():
		for entry in [door,window,rail]:check(preload("res://addons/player_runtime/item_icons.gd").texture(entry.title)!=null,"bundled catalog icon resolves")
		var batch: Node3D=door.collection
		var pose:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])
		check(batch.upsert_instances(PackedInt64Array([7]),pose),"bundled door placed")
		batch.set_collision_focus(Vector3.ZERO);await settle()
		check(blocked(),"bundled closed door blocks ray")
		var hinges: RefCounted=ClassDB.instantiate("NativeHingedDoors")
		check(hinges.toggle(batch,7,AABB()).ok,"bundled hinge opens")
		await settle();check(not blocked(),"bundled open door clears passage")
		var saved: PackedByteArray=hinges.capture_storage_snapshot()
		var models: PackedByteArray=batch.capture_snapshot()
		hinges.forget(7)
		check(hinges.restore_storage_snapshot(saved) and batch.restore_snapshot(models),"bundled hinge and model restore")
		check(hinges.toggle(batch,7,AABB()).ok and batch.get_instance(7)==pose,"restored bundled door closes to exact pose")
		await settle();check(blocked(),"restored bundled collision closes passage")
	world.free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports/bundle_structures")
	FileAccess.open("res://reports/bundle_structures/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("BUNDLE_STRUCTURES failures=",failures);quit(1 if failures else 0)
