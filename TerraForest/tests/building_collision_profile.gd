extends SceneTree
var checks := 0
var failures := 0
var measurements := {}

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func run() -> void:
	for shape in [1,3,6]:
		var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
		root.add_child(world)
		world.set_collision_radius(0)
		var records := PackedInt32Array()
		for z in range(16):
			for y in range(16):
				for x in range(16):
					records.append_array(PackedInt32Array([x,y,z,shape]))
		check(world.set_cells(records),"dense shape %d authored" % shape)
		world.flush_bakes()
		world.set_process(false)
		var saved: PackedByteArray = world.capture_snapshot()
		var original: Dictionary = world.stats()
		var admissions: Array[float] = []
		var releases: Array[float] = []
		var exact := true
		for sample in range(8):
			world.set_collision_radius(48)
			var start := Time.get_ticks_usec()
			world.flush_bakes()
			admissions.append(float(Time.get_ticks_usec()-start)/1000.0)
			await physics_frame
			await physics_frame
			var query := PhysicsRayQueryParameters3D.create(Vector3(8.5,18,8.875),Vector3(8.5,14,8.875),2)
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			var authored: Dictionary = world.raycast_cells(query.from,query.to)
			exact=exact and not hit.is_empty() and not authored.is_empty()
			if not hit.is_empty() and not authored.is_empty():
				exact=exact and hit.position.distance_to(authored.position)<0.001
			world.set_collision_radius(0)
			start=Time.get_ticks_usec()
			world.flush_bakes()
			releases.append(float(Time.get_ticks_usec()-start)/1000.0)
			await physics_frame
		check(exact,"dense shape %d actual collision matches authored surface on every admission" % shape)
		check(world.capture_snapshot()==saved and world.stats().published_bakes==original.published_bakes and world.stats().collision_chunks==0,"shape %d residency cycles preserve authoring and avoid geometry rebakes" % shape)
		admissions.sort();releases.sort()
		measurements[str(shape)]={"cells":original.cells,"triangles":original.triangles,"samples":8,"admission_median_ms":admissions[4],"admission_max_ms":admissions.back(),"release_median_ms":releases[4],"release_max_ms":releases.back()}
		world.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/building_collision_profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Headless CPU collision creation/attachment and release, pre-baked single dense chunk. Excludes frame presentation; does not establish full simulation cost.","measurements":measurements},"  "))
	file.close()
	print("BUILDING_COLLISION_PROFILE ",JSON.stringify(measurements))
	quit(1 if failures else 0)
