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

func make_world() -> Node3D:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(world)
	world.set_process(false)
	world.set_collision_radius(0)
	return world

func dense() -> PackedInt32Array:
	var records := PackedInt32Array()
	for z in range(16):
		for y in range(16):
			for x in range(16):
				records.append_array(PackedInt32Array([x,y,z,3+((x+y+z)%4)*32]))
	return records

func launch_one(world: Node3D) -> bool:
	world.set_process(true)
	for i in range(120):
		await process_frame
		if world.stats().worker_jobs==1:
			world.set_process(false)
			return true
	world.set_process(false)
	return false

func digest(world: Node3D) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for child in world.get_children():
		if child is MeshInstance3D: hash.update(var_to_bytes(child.mesh.surface_get_arrays(0)))
	return hash.finish().hex_encode()

func run() -> void:
	var world := make_world()
	check(world.stats().worker_threads_started==0,"unused block world allocates no worker thread")
	var bounded := true
	for i in range(200):
		world.set_cells(PackedInt32Array([1,1,1,1+(i%4)*32]))
		world.flush_bakes()
		var state: Dictionary = world.stats()
		bounded=bounded and state.worker_threads_started==1 and state.worker_jobs==0 and state.worker_jobs_submitted==state.worker_results_consumed
	check(bounded and world.stats().worker_jobs_submitted==200,"200 real edits reuse one thread and consume exactly one result per submission")
	var idle_state: Dictionary = world.stats()
	world.set_process(true)
	for i in range(100): await process_frame
	world.set_process(false)
	check(world.stats()==idle_state,"idle processing submits no jobs and changes no worker counters")
	measurements["repeated_edits"]=idle_state
	world.free()

	world=make_world()
	world.configure_streaming(true,32,1,1048576,1048576)
	world.set_cells(PackedInt32Array([1,1,1,1]))
	world.flush_bakes()
	var submissions: int = world.stats().worker_jobs_submitted
	for i in range(50):
		world.set_focus(Vector3(1000,1000,1000));world.flush_bakes()
		world.set_focus(Vector3.ZERO);world.flush_bakes()
	check(world.stats().worker_jobs_submitted==submissions and world.stats().worker_threads_started==1 and world.streaming_stats().cache_hits==50,"50 cached return trips neither submit work nor create threads")
	world.free()

	var a := make_world()
	var b := make_world()
	var records := dense()
	a.set_cells(records);b.set_cells(records)
	var a_started: bool = await launch_one(a)
	var b_started: bool = await launch_one(b)
	check(a_started and b_started and a.stats().worker_jobs==1 and b.stats().worker_jobs==1,"independent block worlds each own one bounded outstanding job")
	a.set_cells(PackedInt32Array([1,1,1,0]))
	a.flush_bakes();b.flush_bakes()
	check(a.stats().stale_bakes_rejected==1 and a.get_cell(Vector3i.ONE)==0 and b.get_cell(Vector3i.ONE)!=0,"edit during a pending bake rejects stale geometry without cross-world mutation")
	var reference := make_world()
	reference.restore_snapshot(a.capture_snapshot());reference.flush_bakes()
	check(digest(a)==digest(reference),"replacement result matches a fresh bake of the final authored state")
	check(a.stats().worker_threads_started==1 and a.stats().worker_jobs_submitted==2,"stale replacement also reuses the same worker")
	measurements["stale_replacement"]=a.stats()
	reference.free();a.free();b.free()

	var start := Time.get_ticks_usec()
	var shutdown_jobs := 0
	for i in range(40):
		world=make_world()
		world.set_cells(records)
		if await launch_one(world): shutdown_jobs+=1
		world.free()
	check(shutdown_jobs==40,"40 worlds destroyed with outstanding work join safely without publishing after destruction")
	measurements["shutdown_cycles"]=40
	measurements["shutdown_cycles_ms"]=float(Time.get_ticks_usec()-start)/1000.0
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/block_worker.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"  "))
	file.close()
	print("BLOCK_WORKER_RESULT ",JSON.stringify(measurements))
	quit(1 if failures else 0)
