extends SceneTree
const Stream=preload("res://addons/volumetric_terrain/terrain_stream.gd")
var world: Node3D
var checks: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks.append({"passed":value,"name":label});print("PASS " if value else "FAIL ",label)
func pump(predicate: Callable,prepare: bool=true) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		for row: Dictionary in world.backend.poll(): world._receive(row)
		if prepare: world._drain_staging();world._update_cut()
		await process_frame
	return predicate.call()
func run() -> void:
	world=Stream.new();root.add_child(world)
	check(world.start(StandardMaterial3D.new(),true)==OK,"stream and worker start")
	world.set_process(false)
	check(await pump(func(): return world.world_ready),"startup completes")
	var root_key:=Vector3i(1280,1280,256)
	check(world.backend.submit({"kind":"mesh","key":root_key,"epoch":world.epoch,"stamp":0,"base":false}),"original root admitted")
	check(await pump(func(): return world.visible_cut.has(root_key)),"original root is visible")
	for size: int in [256,128,64]:
		var key:=Vector3i(1280,1280,size)
		var parent: Dictionary=world.tiles[key]
		check(world.request_partition(key),"partition admitted "+str(size))
		check(not world.request_partition(key),"duplicate partition rejected "+str(size))
		check(await pump(func(): return world.staging.size()==4,false),"four child packets reach staging "+str(size))
		var held: Array[Dictionary]=world.staging.duplicate()
		world.staging.clear();world.staging.append(held.pop_front())
		check(await pump(func(): return world.partition_request.get("entries",{}).size()==1),"first child prepared "+str(size))
		check(parent.node.visible and world.visible_cut.has(key) and world.partition_request.entries.size()==1,"parent retained before complete child batch "+str(size))
		for entry: Dictionary in world.partition_request.entries.values(): check(not entry.node.visible,"prepared child remains hidden "+str(size))
		world.staging.append_array(held)
		check(await pump(func(): return world.partition_request.is_empty()),"child batch commits "+str(size))
		check(not parent.node.visible and not world.visible_cut.has(key),"parent retired only after complete batch "+str(size))
		var half:=size/2;var all_visible:=true
		for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
			var child:=Vector3i(1280+offset.x*half,1280+offset.y*half,half)
			all_visible=all_visible and world.visible_cut.has(child) and world.tiles[child].node.visible and world.tiles[child].step==8
		check(all_visible,"all children preserve source resolution "+str(size))
	check(not world.player_region_ready(Vector3(1290,110,1290)),"retained 32m coarse child cannot claim player readiness")
	var plan: Dictionary=world.planner.requests(Vector3(1290,110,1290),true,world.tiles,world.split_state,world.visible_cut)
	check(plan.ok and Vector3i(1280,1280,32) in plan.requests,"planner still requests proper fine replacement")
	var fine_key:=Vector3i(1280,1280,32)
	check(world.backend.submit({"kind":"mesh","key":fine_key,"epoch":world.epoch,"stamp":0,"base":false}),"fine parent build admitted")
	check(await pump(func(): return is_instance_valid(world.tiles[fine_key].body)),"fine parent has live collision")
	await physics_frame;await process_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(1290,300,1290),Vector3(1290,0,1290),1)
	var before: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	var fine_parent: Dictionary=world.tiles[fine_key]
	check(not before.is_empty() and before.collider==fine_parent.body,"physics ray hits fine parent")
	check(world.request_partition(fine_key),"fine collision partition admitted")
	check(await pump(func(): return world.staging.size()==4,false),"fine collision children received")
	check(fine_parent.body.collision_layer==1,"parent collision retained during child staging")
	check(await pump(func(): return world.partition_request.is_empty()),"fine collision children publish")
	await physics_frame;await process_frame
	var after: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not after.is_empty() and not before.is_empty() and after.position.distance_to(before.position)<0.001 and after.collider!=fine_parent.body,"replacement collision preserves sampled surface")
	check(fine_parent.body.collision_layer==0 and world.player_region_ready(Vector3(1290,110,1290)),"old collision disabled and fine children ready")
	var stale_key:=Vector3i(1408,1280,128)
	check(world.request_partition(stale_key),"stale transaction admitted")
	check(await pump(func(): return world.staging.size()==4,false),"stale children available")
	var stale_held: Array[Dictionary]=world.staging.duplicate()
	world.staging.clear();world.staging.append(stale_held.pop_front())
	check(await pump(func(): return world.partition_request.get("entries",{}).size()==1),"stale child prepared before invalidation")
	var abandoned: Dictionary=world.partition_request.entries.values()[0]
	world.staging.append_array(stale_held)
	world.stamps[stale_key]=1
	world._drain_staging()
	check(world.partition_request.is_empty() and world.staging.is_empty() and world.tiles[stale_key].node.visible,"changed parent stamp discards children and preserves parent")
	check(not abandoned.node.visible and world.in_flight.is_empty(),"stale child hidden and reservations released")
	var limited_key:=Vector3i(1280,1408,128)
	world.cache_entry_limit=world.tiles.size()
	check(world.request_partition(limited_key),"partition admitted before output residency check")
	check(await pump(func(): return world.partition_request.is_empty()),"residency limit rejects completed partition")
	check(world.tiles[limited_key].node.visible and world.in_flight.is_empty(),"residency rejection preserves parent coverage")
	world.shutdown();check(not world.backend.thread.is_started(),"worker shutdown completes")
	world.free();await process_frame
	var failures:=0
	for row in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	quit(0 if failures==0 else 1)
