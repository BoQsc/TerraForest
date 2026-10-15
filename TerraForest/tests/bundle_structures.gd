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
func exercise_static(entry: Dictionary, origin: Vector3, across: Vector3) -> void:
	var batch: Node3D=entry.collection
	var pose:=PackedFloat32Array([1,0,0,origin.x,0,1,0,origin.y,0,0,1,origin.z])
	var query:=PhysicsRayQueryParameters3D.create(origin+Vector3(0,1,0)-across,origin+Vector3(0,1,0)+across,2)
	check(batch.upsert_instances(PackedInt64Array([41]),pose),entry.title+" placed")
	batch.set_collision_focus(origin);await settle()
	check(not root.world_3d.direct_space_state.intersect_ray(query).is_empty(),entry.title+" blocks passage")
	var saved: PackedByteArray=batch.capture_snapshot()
	check(batch.remove_instances(PackedInt64Array([41])),entry.title+" removed")
	await settle()
	check(root.world_3d.direct_space_state.intersect_ray(query).is_empty(),entry.title+" leaves no stale collider")
	check(batch.restore_snapshot(saved),entry.title+" snapshot restored")
	await settle()
	check(batch.capture_snapshot()==saved and not root.world_3d.direct_space_state.intersect_ray(query).is_empty(),entry.title+" exact state and collision restored")
func exercise_blocks(world: Node3D) -> void:
	var blocks: Node3D=world.blocks
	var empty: PackedByteArray=blocks.capture_snapshot()
	var records:=PackedInt32Array()
	for shape in range(1,8):
		for rotation in 4:
			records.append_array(PackedInt32Array([shape*3,0,rotation*3,shape+rotation*8+rotation*32]))
			var preview: Mesh=blocks.preview_mesh(shape,rotation)
			check(preview!=null and preview.get_surface_count()==1,"bundled shape %d rotation %d preview"%[shape,rotation])
	check(blocks.set_cells(records),"bundled shapes accept all rotations and materials")
	blocks.flush_bakes();await settle()
	for shape in range(1,8):
		for rotation in 4:
			var from:=Vector3(shape*3+.5,3,rotation*3+.5)
			var to:=from-Vector3.UP*4
			var authored: Dictionary=blocks.raycast_cells(from,to)
			var physical: Dictionary=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,2))
			check(not authored.is_empty() and not physical.is_empty() and authored.position.distance_to(physical.position)<.001,"bundled shape %d rotation %d targeting matches collision"%[shape,rotation])
	var saved: PackedByteArray=blocks.capture_snapshot()
	var prefab: Resource=blocks.capture_prefab(Vector3i(3,0,0),Vector3i(19,1,10))
	check(prefab!=null and blocks.place_prefab(prefab,Vector3i(3,0,30),1),"bundled shapes capture and place as rotated prefab")
	check(blocks.restore_snapshot(saved) and blocks.capture_snapshot()==saved,"bundled shapes restore exact records")
	check(blocks.restore_snapshot(empty),"clear shape fixture before model collision checks")
	blocks.flush_bakes();await settle()
func exercise_stair_rail(world: Node3D) -> void:
	var rails: Node3D=world.model(preload("res://addons/structures/guardrail_catalog.gd").STAIR_KEY)
	check(rails!=null,"bundled stair rail registers")
	if rails==null:return
	var pose:=PackedFloat32Array([1,0,0,40,0,1,1,3,0,0,1,0])
	check(rails.upsert_instances(PackedInt64Array([51]),pose),"bundled sheared stair rail places")
	rails.set_collision_focus(Vector3(40,3,0));await settle()
	var top:=PhysicsRayQueryParameters3D.create(Vector3(39.7,4.55,.5),Vector3(40.3,4.55,.5),2)
	var below:=PhysicsRayQueryParameters3D.create(Vector3(39.7,4,.5),Vector3(40.3,4,.5),2)
	check(not root.world_3d.direct_space_state.intersect_ray(top).is_empty(),"bundled sloping top rail blocks passage")
	check(root.world_3d.direct_space_state.intersect_ray(below).is_empty(),"bundled stair rail leaves space below top bar")
	var saved: PackedByteArray=rails.capture_snapshot()
	check(rails.remove_instances(PackedInt64Array([51])),"bundled stair rail removes")
	await settle()
	check(root.world_3d.direct_space_state.intersect_ray(top).is_empty(),"bundled removed stair rail releases collider")
	check(rails.restore_snapshot(saved),"bundled stair rail restores")
	await settle()
	check(rails.capture_snapshot()==saved and not root.world_3d.direct_space_state.intersect_ray(top).is_empty(),"bundled restored stair rail retains shear and collision")
func run() -> void:
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(world.prepare(),"bundled native structure world prepares")
	await exercise_blocks(world)
	var door: Dictionary=preload("res://addons/structures/door_catalog.gd").register(world)
	var window: Dictionary=preload("res://addons/structures/window_catalog.gd").register(world)
	var rail: Dictionary=preload("res://addons/structures/guardrail_catalog.gd").register(world)
	var fence: Dictionary=preload("res://addons/structures/fence_catalog.gd").register(world)
	check(not door.is_empty() and not window.is_empty() and not rail.is_empty() and not fence.is_empty(),"bundled building catalogs register")
	if not door.is_empty() and not window.is_empty() and not rail.is_empty() and not fence.is_empty():
		for entry in [door,window,rail,fence]:check(preload("res://addons/player_runtime/item_icons.gd").texture(entry.title)!=null,"bundled catalog icon resolves: "+entry.title)
		await exercise_stair_rail(world)
		await exercise_static(window,Vector3(10,0,0),Vector3(0,0,2))
		await exercise_static(rail,Vector3(20,0,0),Vector3(2,0,0))
		await exercise_static(fence,Vector3(30,0,0),Vector3(2,0,0))
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
