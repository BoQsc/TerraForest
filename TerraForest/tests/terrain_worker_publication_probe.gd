extends "res://tests/terrain_publication_probe.gd"

var worker_events: Array[Dictionary] = []

func pump_until(predicate: Callable, prepare: bool = true) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		for result: Dictionary in world.backend.poll():
			worker_events.append({"kind":result.kind,"ticket":result.get("ticket",-1),"remaining_before_receive":world.batch_remaining,"worker_ms":result.get("worker_ms",0.0)})
			world._receive(result)
		if prepare: world._drain_staging()
		if not world.latest_error.is_empty(): return false
		await process_frame
	return predicate.call()

func run() -> void:
	world = FixedCut.new()
	root.add_child(world)
	world.set_process(false)
	world.material = StandardMaterial3D.new()
	world.backend.disk_cache.enabled = false
	check(world.backend.start(true)==OK,"real native terrain worker starts")
	check(await pump_until(func(): return world.world_ready),"real worker startup delivered")
	for z in [1280,1296]:
		for x in [1280,1296]: world.visible_cut.append(Vector3i(x,z,16))
	for key in world.visible_cut:
		check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":0,"base":false}),"initial region admitted %s" % key)
	check(await pump_until(func(): return world.tiles.size()==4),"worker meshes reach live staging and publication")
	# Obtain terrain height through the same worker, avoiding concurrent native access.
	var height_reply: Array[float] = []
	world.height_received.connect(func(_point: Vector3, height: float, _token: int): height_reply.append(height))
	world.request_height(Vector3(1296,0,1296),7)
	check(await pump_until(func(): return not height_reply.is_empty()),"worker height query completes")
	if height_reply.is_empty():
		world.shutdown()
		world.free()
		quit(1)
		return
	var point := Vector3(1296,height_reply[0],1296)
	var rows: Array[Dictionary] = []
	for mode in ["completion_before_preparation","overlapped"]:
		var old: Dictionary = world.tiles.duplicate()
		var before: Array[float] = await physics_hits(old,"worker fixture original physics "+mode)
		var revision_before: int = world.published_revision
		var start := Time.get_ticks_usec()
		check(world.edit(Codec.brush(point,point,4,0,false,1),point-Vector3.ONE*9,point+Vector3.ONE*9),"public stream edit accepted "+mode)
		check(world.last_density_tiles==4,"edit invalidates exactly four visible local regions "+mode)
		if mode=="completion_before_preparation":
			check(await pump_until(func(): return world.edit_worker_done,false),"worker completion received with staging deliberately held")
			check(world.pending_edit and world.batch_remaining==4 and world.staging.size()==4,"completion alone cannot publish unprepared batch")
			var held: Array[float] = await physics_hits(old,"worker completed but original collision retained")
			check(before==held,"completion-before-preparation keeps original physics surface")
		check(await pump_until(func(): return not world.pending_edit),"local worker edit commits "+mode)
		var elapsed := (Time.get_ticks_usec()-start)/1000.0
		check(world.published_revision==revision_before+1 and world.batch_remaining==0 and world.staged_batch.is_empty(),"worker transaction publishes exactly once "+mode)
		var after: Array[float] = await physics_hits(world.tiles,"worker fixture replacement physics "+mode)
		var lowered := 0
		for i in range(4):
			if after[i]<before[i]-0.01: lowered += 1
		check(lowered==4,"worker excavation lowers all four sampled surfaces "+mode)
		rows.append({"mode":mode,"elapsed_ms":elapsed,"worker_build_ms":world.last_total_build_ms,"worker_queue_ms":world.last_queue_ms,"publish_ms":world.last_commit_ms,"before_heights":before,"after_heights":after})
		point.y -= 2.0
	world.shutdown()
	check(not world.backend.thread.is_started(),"real worker joins cleanly")
	world.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_worker_publication_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"checks":checks,"rows":rows,"events":worker_events,"scope":"Real native worker, public stream edit/invalidation, collision staging and physics queries. Fixed four-region cut; no quadtree transitions, draw/GPU, new mesher or endurance. Held mode deliberately includes observer delay; all timings are headless diagnostic only."},"  "))
	file.close()
	quit(0 if failures==0 else 1)
