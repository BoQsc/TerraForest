extends "res://tests/terrain_worker_publication_probe.gd"

func exact_coverage() -> bool:
	var cells: Dictionary = {}
	for key in world.visible_cut:
		if key.x<1280 or key.y<1280 or key.x+key.z>1536 or key.y+key.z>1536: return false
		for z in range(key.y, key.y+key.z,16):
			for x in range(key.x,key.x+key.z,16):
				var cell := Vector2i(x,z)
				if cells.has(cell): return false
				cells[cell] = true
	return cells.size()==256

func request_mesh(key: Vector3i) -> bool:
	if not world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":int(world.stamps.get(key,0)),"base":false}): return false
	return await pump_until(func(): return world.tiles.has(key) and int(world.tiles[key].stamp)==int(world.stamps.get(key,0)))

func run() -> void:
	world = Stream.new()
	root.add_child(world)
	world.set_process(false)
	world.material = StandardMaterial3D.new()
	world.backend.disk_cache.enabled = false
	check(world.backend.start(true)==OK,"transition native worker starts")
	world.planner = ClassDB.instantiate("NativeTerrainPlanner")
	check(await pump_until(func(): return world.world_ready),"transition worker ready")
	var parent := Vector3i(1280,1280,256)
	check(await request_mesh(parent),"coarse parent prepared through real worker")
	world._update_cut()
	check(world.visible_cut==[parent] and world.tiles[parent].node.visible and exact_coverage(),"native planner activates complete parent coverage")
	var original_parent: Dictionary = world.tiles[parent]
	var requests: Array[Vector3i] = []
	for size in [128,64,32]:
		world.split_state[Vector3i(1280,1280,size*2)] = true
		for offset in [Vector2i(size,0),Vector2i(0,size),Vector2i(size,size)]:
			requests.append(Vector3i(1280+offset.x,1280+offset.y,size))
	world.split_state[Vector3i(1280,1280,32)] = true
	for z in [1280,1296]:
		for x in [1280,1296]: requests.append(Vector3i(x,z,16))
	var transition_begin := Time.get_ticks_usec()
	for i in range(requests.size()):
		check(await request_mesh(requests[i]),"replacement owner prepared %s" % requests[i])
		world._update_cut()
		check(exact_coverage(),"no absent or overlapping ownership after child %d" % i)
		if i<requests.size()-1:
			check(world.visible_cut==[parent] and original_parent.node.visible,"incomplete descendants cannot retire parent %d" % i)
	check(world.visible_cut.size()==13 and not original_parent.node.visible,"complete mixed cut replaces parent")
	var fine_center := Vector3(1296,105,1296)
	check(world.player_region_ready(fine_center),"fine collision readiness becomes available after refinement")
	var refinement_ms := (Time.get_ticks_usec()-transition_begin)/1000.0
	var heights: Array[float] = []
	world.height_received.connect(func(_point: Vector3,height: float,_token: int): heights.append(height))
	world.request_height(fine_center,1)
	check(await pump_until(func(): return not heights.is_empty()),"transition edit height obtained")
	if heights.is_empty():
		world.shutdown()
		world.free()
		quit(1)
		return
	fine_center.y = heights[0]
	check(world.edit(Codec.brush(fine_center,fine_center,2.5,0,false,1),fine_center-Vector3.ONE*8,fine_center+Vector3.ONE*8),"edit accepted with mixed cut active")
	check(world.last_density_tiles==4,"mixed-cut edit rebuilds four fine owners")
	check(await pump_until(func(): return not world.pending_edit),"mixed-cut edit publishes through worker")
	check(exact_coverage() and world.visible_cut.size()==13 and world.tiles[parent].dirty,"edit preserves mixed coverage and invalidates cached parent")
	# Simulate a later distant/coarsening request, where fine collision is no longer needed.
	world.require_collision = false
	world.split_state.clear()
	world._update_cut()
	check(exact_coverage() and world.visible_cut.size()==13 and not original_parent.node.visible,"coarsening cannot resurrect obsolete hidden parent")
	check(await request_mesh(parent),"fresh coarse parent rebuilt after edit")
	world._update_cut()
	check(world.visible_cut==[parent] and exact_coverage() and not world.tiles[parent].dirty,"coarsening switches only to refreshed parent")
	var hidden_disabled := true
	for key in requests:
		var entry: Dictionary = world.tiles[key]
		hidden_disabled = hidden_disabled and not entry.node.visible and (entry.body==null or entry.body.collision_layer==0)
	check(hidden_disabled,"coarsening disables all hidden child visuals and colliders")
	world.shutdown()
	check(not world.backend.thread.is_started(),"transition worker joins cleanly")
	world.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_transition_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"checks":checks,"events":worker_events,"refinement_ms":refinement_ms,"scope":"Real worker, staging and native coverage planner on one aligned mountain root. Controlled child arrival and split flags. Exact XZ ownership coverage at planner updates, not geometric seam/shading proof. Headless; no GPU/FPS, cave qualification, automatic distance scheduling or endurance."},"  "))
	file.close()
	quit(0 if failures==0 else 1)
