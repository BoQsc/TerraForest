extends SceneTree
var checks := 0
var failures := 0
var evidence := {}

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func dense() -> PackedInt32Array:
	var records := PackedInt32Array()
	for z in range(16):
		for y in range(16):
			for x in range(16): records.append_array(PackedInt32Array([x,y,z,6]))
	return records

func drive(world: Node3D, predicate: Callable, limit: int = 2000) -> Dictionary:
	var bounded := true
	var inactive := true
	var samples: Array[float] = []
	var before: Dictionary = world.collision_stats()
	world.set_process(true)
	for frame in range(limit):
		await process_frame
		var state: Dictionary = world.collision_stats()
		var ticks: int = state.ticks-before.ticks
		bounded=bounded and state.pieces_built-before.pieces_built<=ticks and state.pieces_retired-before.pieces_retired<=ticks*4
		if state.pending_chunks>0:
			for child in world.get_children():
				if child is StaticBody3D: inactive=inactive and child.collision_layer==0
		if ticks>0: samples.append(state.last_tick_ms)
		before=state
		if predicate.call(): break
	world.set_process(false)
	samples.sort()
	return {"done":predicate.call(),"bounded":bounded,"partial_inactive":inactive,"samples":samples.size(),"median_ms":samples[samples.size()/2] if samples.size() else 0,"max_ms":samples.back() if samples.size() else 0}

func run() -> void:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(world)
	world.set_collision_radius(0)
	check(world.set_cells(dense()),"dense curved chunk authored")
	world.flush_bakes();world.set_process(false)
	var saved: PackedByteArray = world.capture_snapshot()
	check(world.stats().triangles==491520 and not world.collision_stats().ready,"dense fixture has expected geometry and disabled collision readiness")
	world.set_collision_radius(48)
	check(not world.collision_stats().ready,"enabling collision reports pending before any shape admission")
	var admission: Dictionary = await drive(world,func(): return world.collision_stats().ready)
	check(admission.done and admission.bounded and admission.partial_inactive,"480-piece admission obeys per-tick bounds and keeps partial collision inactive")
	check(world.collision_stats().live_pieces==480 and world.stats().collision_chunks==1,"complete dense chunk activates all 480 exact pieces")
	await physics_frame
	await physics_frame
	var exact := true
	for x in [0.5,8.5,15.5]:
		for z in [0.5,8.5,15.5]:
			var from := Vector3(x,18,z)
			var to := Vector3(x,14,z)
			var query := PhysicsRayQueryParameters3D.create(from,to,2)
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			var authored: Dictionary = world.raycast_cells(from,to)
			exact=exact and not hit.is_empty() and not authored.is_empty()
			if not hit.is_empty() and not authored.is_empty(): exact=exact and hit.position.distance_to(authored.position)<0.001
	check(exact,"completed paged collision agrees with authored spheres across the chunk")
	world.set_collision_radius(0)
	var release: Dictionary = await drive(world,func(): return world.collision_stats().live_pieces==0 and world.collision_stats().retired_bodies==0)
	check(release.done and release.bounded and world.stats().collision_chunks==0,"dense collision retirement drains incrementally")
	check(world.capture_snapshot()==saved,"collision streaming leaves authored data unchanged")
	world.set_collision_radius(48)
	var partial: Dictionary = await drive(world,func(): return world.collision_stats().live_pieces>=10)
	check(partial.done and not world.collision_stats().ready,"second admission can be interrupted with real partial pieces")
	world.set_focus(Vector3(1000,1000,1000))
	var abandoned: Dictionary = await drive(world,func(): return world.collision_stats().live_pieces==0 and world.collision_stats().retired_bodies==0)
	check(abandoned.done and abandoned.bounded,"travel away retires incomplete collision without activation")
	world.set_focus(Vector3.ZERO)
	await drive(world,func(): return world.collision_stats().live_pieces>=10)
	world.set_cells(PackedInt32Array([8,15,8,0]))
	check(not world.collision_stats().ready,"authored edit immediately invalidates readiness")
	world.flush_bakes();world.set_process(false)
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(8.5,18,8.5),Vector3(8.5,14,8.5),2)
	var changed: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	check(world.collision_stats().ready and not changed.is_empty() and absf(changed.position.y-15)<0.001,"edit during partial admission replaces every old piece and publishes the changed surface")
	world.configure_streaming(true,32,1,65536,0)
	world.flush_bakes();world.set_process(false)
	check(not world.collision_stats().ready and world.collision_stats().unresolved_mesh_chunks==1 and world.collision_stats().retired_bodies==0,"mesh-budget rejection is not reported as collision ready and releases all old pieces")
	evidence={"admission":admission,"release":release,"abandoned":abandoned,"final":world.collision_stats(),"scope":"Headless native collision tick time, excludes physics simulation and rendered frames; offline flush after edit is intentionally blocking."}
	world.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/building_collision_stream.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence},"  "))
	file.close()
	print("BUILDING_COLLISION_STREAM ",JSON.stringify(evidence))
	quit(1 if failures else 0)
