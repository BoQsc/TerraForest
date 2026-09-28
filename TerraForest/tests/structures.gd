extends SceneTree
var failures := 0
var checks := 0
var evidence := {}

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL ", description)
	else:
		print("PASS ", description)

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func make_world() -> Node3D:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(world)
	return world

func area_and_winding(world: Node3D) -> Vector2:
	var area := 0.0
	var wrong := 0.0
	for child in world.get_children():
		if child is MeshInstance3D:
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var cross := (points[indices[i+1]]-points[indices[i]]).cross(points[indices[i+2]]-points[indices[i]])
				area += cross.length()*0.5
				if cross.dot(normals[indices[i]]) >= 0:
					wrong += 1
	return Vector2(area, wrong)

func check_exclusion() -> void:
	var blocks := make_world()
	var empty: PackedByteArray = blocks.capture_snapshot()
	blocks.set_cells(PackedInt32Array([-1,0,0,1,16,3,0,4]))
	var bounds := AABB(Vector3.ZERO,Vector3.ONE)
	var samples: Array[Transform3D] = [Transform3D(Basis.IDENTITY,Vector3(-1,0,0)),Transform3D.IDENTITY,Transform3D(Basis.IDENTITY,Vector3(16,3,0)),Transform3D(Basis.IDENTITY,Vector3(-1,2,0))]
	check(blocks.overlap_mask(samples,bounds)==PackedByteArray([1,0,1,0]),"occupancy handles negative seams, touching faces, slope cells and vertical clearance")
	var saved: PackedByteArray = blocks.capture_snapshot()
	blocks.set_cells(PackedInt32Array([-1,0,0,0]))
	check(blocks.overlap_mask(samples,bounds)==PackedByteArray([0,0,1,0]),"occupancy updates after removal")
	blocks.restore_snapshot(saved)
	check(blocks.overlap_mask(samples,bounds)==PackedByteArray([1,0,1,0]),"occupancy index rebuilt from persisted cells")
	blocks.position=Vector3(100,0,0)
	var moved: Array[Transform3D] = [Transform3D(Basis.IDENTITY,Vector3(99,0,0))]
	check(blocks.overlap_mask(moved,bounds)==PackedByteArray([1]),"occupancy transforms world placements into block coordinates")
	blocks.position=Vector3.ZERO
	check(blocks.overlap_mask(samples,AABB(Vector3.ZERO,Vector3(-1,1,1))).is_empty(),"negative query bounds rejected")
	var bad: Array[Transform3D] = [Transform3D(Basis.IDENTITY,Vector3(INF,0,0))]
	check(blocks.overlap_mask(bad,bounds).is_empty(),"nonfinite transforms rejected atomically")
	var large: Array[Transform3D] = [Transform3D.IDENTITY]
	check(blocks.overlap_mask(large,AABB(Vector3.ONE*-1e10,Vector3.ONE*2e10))==PackedByteArray([1]),"huge query bounded by resident chunks")
	check(blocks.overlap_mask(large,AABB(Vector3.ONE*1e10,Vector3.ONE))==PackedByteArray([0]),"remote huge coordinates safely rejected before integer conversion")
	blocks.restore_snapshot(empty)
	check(blocks.overlap_mask(samples,bounds)==PackedByteArray([0,0,0,0]),"empty restored world clears occupancy")
	blocks.free()

func check_prefabs() -> void:
	var prefab: Resource = ClassDB.instantiate("NativeBlockPrefab")
	var records := PackedInt32Array([0,1,2,44,-1,0,0,65])
	check(prefab.configure(records) and prefab.get_cell_count()==2,"native prefab accepts sparse shape/material records")
	var canonical := PackedInt32Array([-1,0,0,65,0,1,2,44])
	check(prefab.get_records()==canonical,"prefab canonicalizes record ordering")
	var exposed: PackedInt32Array = prefab.get_records()
	exposed[3]=0
	check(prefab.get_records()==canonical,"returned prefab records cannot mutate the asset")
	for bad in [PackedInt32Array([0,0,0,0]),PackedInt32Array([0,0,0,7]),PackedInt32Array([0,0,0,1,0,0,0,2]),PackedInt32Array([4096,0,0,1]),PackedInt32Array([0,0,0])]:
		check(not prefab.configure(bad) and prefab.get_records()==canonical,"invalid prefab authoring is atomic")
	var world := make_world()
	var empty: PackedByteArray = world.capture_snapshot()
	var origin := Vector3i(-16,5,-16)
	var positions := [[Vector3i(-1,0,0),Vector3i(0,1,2)],[Vector3i(0,0,-1),Vector3i(-2,1,0)],[Vector3i(1,0,0),Vector3i(0,1,-2)],[Vector3i(0,0,1),Vector3i(2,1,0)]]
	var lows := [Vector3(-1,0,0),Vector3(-2,0,-1),Vector3(0,0,-2),Vector3(0,0,0)]
	for rotation in range(4):
		world.restore_snapshot(empty)
		check(world.can_place_prefab(prefab,origin,rotation) and world.place_prefab(prefab,origin,rotation),"native prefab quarter-turn placement %d" % rotation)
		check(world.get_cell(origin+positions[rotation][0])==(65|(rotation<<3)) and world.get_cell(origin+positions[rotation][1])==(36|(((rotation+1)%4)<<3)),"quarter-turn rotates coordinates and oriented shape %d" % rotation)
		var bounds: AABB = prefab.placement_bounds(origin,rotation)
		check(bounds.position==Vector3(origin)+lows[rotation] and bounds.size==Vector3(2 if rotation%2==0 else 3,2,3 if rotation%2==0 else 2),"preview bounds match rotated cell extents %d" % rotation)
	var before: PackedByteArray = world.capture_snapshot()
	check(not world.place_prefab(prefab,origin,3) and world.capture_snapshot()==before,"occupied destination rejects entire prefab")
	check(world.place_prefab(prefab,origin,3,true) and world.capture_snapshot()==before,"explicit replace mode is deterministic")
	check(not world.place_prefab(prefab,Vector3i(2147483647,0,0),0) and world.capture_snapshot()==before,"coordinate overflow rejects placement before mutation")
	check(not world.place_prefab(prefab,origin,4) and not world.place_prefab(null,origin,0),"invalid rotation and null asset rejected")
	world.restore_snapshot(empty)
	world.set_cells(PackedInt32Array([0,0,1,1]))
	check(world.place_prefab(prefab,Vector3i.ZERO,0) and world.get_cell(Vector3i(0,0,1))==1,"sparse prefab leaves unlisted destination cells untouched")
	var captured: Resource = world.capture_prefab(Vector3i(-1,0,0),Vector3i(2,2,3))
	check(captured!=null and captured.get_cell_count()==3,"capture creates reusable asset from actual world cells")
	check(world.capture_prefab(Vector3i.ZERO,Vector3i(257,1,1))==null and world.capture_prefab(Vector3i.ZERO,Vector3i(256,256,256))==null,"capture dimensions and volume are bounded")
	check(world.place_prefab(captured,Vector3i(100,0,100),0) and world.get_cell(Vector3i(101,1,102))==44,"captured asset can be placed independently")
	DirAccess.make_dir_recursive_absolute("res://reports")
	check(ResourceSaver.save(captured,"res://reports/prefab_roundtrip.tres")==OK,"native prefab saves as a Godot resource")
	var loaded: Resource = ResourceLoader.load("res://reports/prefab_roundtrip.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded!=null and loaded.get_records()==captured.get_records(),"native prefab resource round trip preserves all records")
	world.restore_snapshot(empty)
	var capacity := PackedInt32Array()
	for i in range(2048):
		capacity.append_array(PackedInt32Array([i*16,0,0,1]))
	world.set_cells(capacity)
	before=world.capture_snapshot()
	check(not world.can_place_prefab(prefab,Vector3i(40000,0,0),0) and not world.place_prefab(prefab,Vector3i(40000,0,0),0) and world.capture_snapshot()==before,"prefab capacity preflight and commit both reject atomically")
	world.free()

func check_history() -> void:
	var world := make_world()
	var empty: PackedByteArray = world.capture_snapshot()
	world.set_cells(PackedInt32Array([0,0,0,1]))
	check(not world.can_undo() and world.history_stats().cell_capacity_bytes==0,"history is opt-in for runtime worlds")
	world.restore_snapshot(empty)
	check(world.configure_history(16*1024*1024,128),"bounded native editor history enabled")
	var notices: Array = []
	var observe := func(): notices.append(world.history_stats())
	world.changed.connect(observe)
	world.set_cells(PackedInt32Array([0,0,0,1,16,-1,-16,44,0,0,0,33]))
	var authored: PackedByteArray = world.capture_snapshot()
	check(world.history_stats().undo_steps==1 and world.history_stats().cell_capacity_bytes==32,"one command stores only two unique changed cells")
	check(notices[-1].undo_steps==1 and notices[-1].redo_steps==0,"forward change listeners observe committed history")
	check(world.undo() and world.capture_snapshot()==empty,"undo restores original values across signed chunk seams")
	check(notices[-1].undo_steps==0 and notices[-1].redo_steps==1,"undo cursor is committed before change notification")
	var history: Dictionary = world.history_stats()
	world.set_cells(PackedInt32Array([0,0,0,1,0,0,0,0]))
	check(world.history_stats()==history and world.can_redo(),"net-zero duplicate edits preserve redo")
	check(not world.set_cells(PackedInt32Array([0,0,0,1,1,0,0,7])) and world.history_stats()==history,"invalid batch preserves history atomically")
	check(world.redo() and world.capture_snapshot()==authored,"redo reproduces exact shapes and materials")
	check(notices[-1].undo_steps==1 and notices[-1].redo_steps==0,"redo cursor is committed before change notification")
	world.undo()
	world.set_cells(PackedInt32Array([2,0,0,65]))
	check(not world.can_redo() and world.history_stats().undo_steps==1,"new edit discards abandoned future commands")
	var corrupt := authored.duplicate()
	corrupt[10]^=1
	history=world.history_stats()
	check(not world.restore_snapshot(corrupt) and world.history_stats()==history,"failed load preserves construction history")
	check(world.restore_snapshot(authored) and not world.can_undo() and not world.can_redo(),"successful load starts a new history timeline")
	world.changed.disconnect(observe)
	history=world.history_stats()
	check(not world.configure_history(-1,2) and not world.configure_history(67108865,2) and not world.configure_history(1024,1025) and world.history_stats()==history,"invalid history limits preserve configuration")
	world.restore_snapshot(empty)
	world.configure_history(32,2)
	for x in range(3):
		world.set_cells(PackedInt32Array([x,0,0,1]))
	check(world.history_stats().undo_steps==2 and world.history_stats().cell_capacity_bytes==32,"byte and command budgets evict the oldest undo steps")
	check(world.undo() and world.undo() and not world.undo() and world.get_cell(Vector3i.ZERO)==1,"eviction retains a valid nearest undo chain")
	world.restore_snapshot(empty)
	world.configure_history(1024,3)
	for x in range(3):
		world.set_cells(PackedInt32Array([x,0,0,1]))
	world.undo()
	world.undo()
	world.undo()
	world.configure_history(32,2)
	check(world.redo() and world.redo() and not world.redo() and world.get_cell(Vector3i(2,0,0))==0,"shrinking undone history retains nearest redo steps")
	world.configure_history(16,2)
	world.set_cells(PackedInt32Array([4,0,0,1,5,0,0,1]))
	check(not world.can_undo() and not world.can_redo() and world.history_stats().cell_capacity_bytes==0 and world.history_stats().unrecorded_edits==1,"oversized accepted edit forms a barrier instead of unsafe partial undo")
	world.restore_snapshot(empty)
	world.configure_history(1024,16)
	var prefab: Resource = ClassDB.instantiate("NativeBlockPrefab")
	prefab.configure(PackedInt32Array([0,0,0,1,1,0,0,1,16,0,0,3]))
	world.place_prefab(prefab,Vector3i.ZERO,0)
	authored=world.capture_snapshot()
	prefab.configure(PackedInt32Array([100,0,0,65]))
	check(world.undo() and world.capture_snapshot()==empty and world.redo() and world.capture_snapshot()==authored,"whole prefab history is independent of later asset changes")
	world.flush_bakes()
	var triangles: int = world.stats().triangles
	world.undo()
	world.flush_bakes()
	check(world.stats().triangles==0 and world.stats().collision_chunks==0,"undo removes chunk geometry and collision")
	world.redo()
	world.flush_bakes()
	var instances: Array[Transform3D] = [Transform3D.IDENTITY]
	check(world.stats().triangles==triangles and world.overlap_mask(instances,AABB(Vector3.ZERO,Vector3.ONE))==PackedByteArray([1]),"redo rebuilds geometry and vegetation occupancy")
	world.restore_snapshot(empty)
	world.set_cells(PackedInt32Array([0,0,0,1]))
	world.set_cells(PackedInt32Array([0,0,0,0]))
	history=world.history_stats()
	check(not world.undo(AABB(Vector3.ZERO,Vector3.ONE)) and world.history_stats()==history and world.get_cell(Vector3i.ZERO)==0,"protected player volume blocks solid restoration atomically")
	world.position=Vector3(100,0,0)
	check(not world.undo(AABB(Vector3(100,0,0),Vector3.ONE)),"protected volume is transformed into block coordinates")
	check(not world.undo(AABB(Vector3(INF,0,0),Vector3.ONE)),"nonfinite history protection is rejected")
	check(world.undo(AABB(Vector3.ZERO,Vector3.ONE)) and world.get_cell(Vector3i.ZERO)==1,"nonintersecting protection permits restoration")
	world.position=Vector3.ZERO
	world.undo()
	check(not world.redo(AABB(Vector3.ZERO,Vector3.ONE)) and world.can_redo(),"redo also respects player clearance")
	world.redo()
	var clear_on_change := func(): world.clear_history()
	world.changed.connect(clear_on_change)
	check(world.undo() and not world.can_undo() and not world.can_redo(),"reentrant signal listener may clear history safely")
	world.changed.disconnect(clear_on_change)
	world.configure_history(0,128)
	world.set_cells(PackedInt32Array([0,0,0,1]))
	check(world.history_stats().cell_capacity_bytes==0 and not world.can_undo(),"disabling history releases retained cell data")
	world.free()

func check_history_model() -> void:
	var world := make_world()
	world.configure_history(1152,8)
	var states: Array[Dictionary] = [{}]
	var cursor := 0
	var rng := RandomNumberGenerator.new()
	rng.seed=1703
	var correct := true
	for operation in range(400):
		var action := rng.randi_range(0,9)
		if action<6:
			var next: Dictionary = states[cursor].duplicate()
			var records := PackedInt32Array()
			for j in range(rng.randi_range(1,6)):
				var x := rng.randi_range(0,8)
				var word: int = [0,1,33,65,3][rng.randi_range(0,4)]
				records.append_array(PackedInt32Array([x,0,0,word]))
				if word:
					next[x]=word
				else:
					next.erase(x)
			correct=world.set_cells(records) and correct
			if next!=states[cursor]:
				states.resize(cursor+1)
				states.append(next)
				cursor+=1
				if states.size()>9:
					states.pop_front()
					cursor-=1
		elif action<8:
			correct=(world.undo()==(cursor>0)) and correct
			cursor=maxi(0,cursor-1)
		else:
			correct=(world.redo()==(cursor<states.size()-1)) and correct
			cursor=mini(states.size()-1,cursor+1)
		for x in range(9):
			correct=(world.get_cell(Vector3i(x,0,0))==states[cursor].get(x,0)) and correct
		var history: Dictionary = world.history_stats()
		correct=(history.undo_steps==cursor and history.redo_steps==states.size()-cursor-1 and history.cell_capacity_bytes<=1152) and correct
	check(correct,"400 deterministic edits, undo, redo and history evictions match an independent state model")
	world.free()

func check_history_worker() -> void:
	var world := make_world()
	world.configure_history(1024,16)
	world.set_cells(PackedInt32Array([0,0,0,1]))
	await process_frame
	await process_frame
	check(world.stats().worker_jobs==1,"history test has a live bake awaiting publication")
	var undone: bool = world.undo()
	world.flush_bakes()
	check(undone and world.stats().triangles==0 and world.stats().stale_bakes_rejected>0,"undo rejects in-flight geometry from the abandoned edit")
	var redone: bool = world.redo()
	world.flush_bakes()
	check(redone and world.stats().triangles==12 and world.stats().collision_chunks==1,"redo publishes current geometry and collision after stale rejection")
	world.free()

func check_streaming() -> void:
	var world := make_world()
	var empty: PackedByteArray = world.capture_snapshot()
	check(world.configure_streaming(true,64,2,1048576,1048576),"native mesh residency and bake cache configured")
	world.set_cells(PackedInt32Array([0,0,0,1,512,0,0,1,1024,0,0,1,1536,0,0,1]))
	var authored: PackedByteArray = world.capture_snapshot()
	world.set_focus(Vector3(8,8,8))
	world.flush_bakes()
	check(world.stats().chunks==4 and world.stats().mesh_chunks==1 and world.stats().collision_chunks==1 and world.streaming_stats().deferred_chunks==3,"only nearby building meshes and physics are resident")
	for i in range(1,4):
		world.set_focus(Vector3(i*512+8,8,8))
		world.flush_bakes()
	var warmed: Dictionary = world.streaming_stats()
	check(warmed.bake_jobs==4 and warmed.cached_chunks==4 and world.stats().mesh_chunks==1,"travel releases old meshes while retaining bounded CPU bakes")
	var bounded := true
	for i in range(100):
		world.set_focus(Vector3((i%4)*512+8,8,8))
		world.flush_bakes()
		var stats: Dictionary = world.streaming_stats()
		bounded=bounded and stats.cache_capacity_bytes<=1048576 and stats.mesh_payload_bytes<=1048576 and world.stats().mesh_chunks==1
	check(bounded and world.streaming_stats().bake_jobs==4 and world.streaming_stats().cache_hits>=100,"100 warmed travel cycles reuse bakes within fixed residency/cache budgets")
	evidence.streaming_warm=world.streaming_stats()
	check(world.capture_snapshot()==authored,"render eviction never removes authored cells from persistence")
	var single_cache_budget: int = int(warmed.cache_capacity_bytes/4)
	world.configure_streaming(true,64,2,1048576,single_cache_budget)
	world.flush_bakes()
	var evicted_jobs: int = world.streaming_stats().bake_jobs
	world.set_focus(Vector3(8,8,8))
	world.flush_bakes()
	check(world.streaming_stats().cached_chunks==1 and world.streaming_stats().bake_jobs==evicted_jobs+1 and world.streaming_stats().cache_evictions>0,"bounded LRU eviction regenerates a dropped bake on revisit")
	world.configure_streaming(true,64,2,1048576,1048576)
	world.flush_bakes()
	var before: Dictionary = world.streaming_stats()
	check(not world.configure_streaming(true,NAN,2,1048576,1048576) and not world.configure_streaming(true,64,2147483649,1048576,1048576) and not world.configure_streaming(true,64,2,0,1048576) and world.streaming_stats()==before,"invalid streaming limits preserve current state")
	world.set_focus(Vector3(INF,0,0))
	world.flush_bakes()
	check(world.stats().mesh_chunks==1 and world.streaming_stats().residency_checks==before.residency_checks,"nonfinite focus cannot corrupt residency")
	world.restore_snapshot(empty)
	world.set_focus(Vector3(8,8,8))
	world.set_cells(PackedInt32Array([15,0,0,1,16,0,0,1]))
	world.flush_bakes()
	check(world.stats().triangles==20,"streamed adjacent chunks omit their shared boundary faces")
	world.set_focus(Vector3(1000,8,8))
	world.flush_bakes()
	check(world.stats().mesh_chunks==0 and world.streaming_stats().cached_chunks==2,"distant chunks retain only cached CPU geometry")
	world.configure_history(1024,16)
	world.set_cells(PackedInt32Array([16,0,0,0]))
	check(world.streaming_stats().cached_chunks==0,"far edit invalidates both the changed chunk and its cached neighbour")
	world.set_focus(Vector3(8,8,8))
	world.flush_bakes()
	check(world.stats().triangles==12,"returning after a far edit rebuilds the exposed boundary face")
	world.undo()
	world.flush_bakes()
	check(world.stats().triangles==20,"undo and streamed cache invalidation preserve chunk seams")
	var replacement: PackedByteArray = world.capture_snapshot()
	world.restore_snapshot(replacement)
	check(world.streaming_stats().cached_chunks==0,"world restoration cannot reuse old cached bakes")
	world.flush_bakes()
	world.configure_streaming(true,64,2,1048576,0)
	world.flush_bakes()
	check(world.streaming_stats().cache_capacity_bytes==0 and world.streaming_stats().cached_chunks==0,"zero cache budget immediately releases all retained bakes")
	world.restore_snapshot(empty)
	var fragmented := PackedInt32Array()
	for z in range(16):
		for y in range(16):
			for x in range(16):
				if (x+y+z)%2==0:
					fragmented.append_array(PackedInt32Array([x,y,z,1]))
	world.configure_streaming(true,64,3,65536,16777216)
	world.set_cells(fragmented)
	world.flush_bakes()
	check(world.is_idle() and world.stats().mesh_chunks==0 and world.streaming_stats().budget_blocked_chunks==1 and world.streaming_stats().cached_chunks==1,"over-budget chunk reports a settled admission failure without an endless bake loop")
	var jobs: int = world.streaming_stats().bake_jobs
	world.configure_streaming(true,64,3,4194304,16777216)
	world.flush_bakes()
	check(world.stats().mesh_chunks==1 and world.streaming_stats().bake_jobs==jobs,"raising the mesh budget reuses the cached rejected bake")
	var one_payload: int = world.streaming_stats().mesh_payload_bytes
	for offset in [16,32]:
		var translated := fragmented.duplicate()
		for i in range(0,translated.size(),4):
			translated[i]+=offset
		world.set_cells(translated)
	world.configure_streaming(true,64,3,one_payload+1024,16777216)
	world.flush_bakes()
	check(world.stats().mesh_chunks==1 and world.streaming_stats().budget_blocked_chunks==2 and world.streaming_stats().mesh_payload_bytes<=one_payload+1024,"mesh-byte budget bounds fragmented buildings independently of chunk count")
	evidence.fragmented_budget=world.streaming_stats()
	world.set_focus(Vector3(40,8,8))
	world.flush_bakes()
	var nearest := false
	for child in world.get_children():
		if child is MeshInstance3D:
			nearest=child.position.x==32
	check(nearest and world.stats().mesh_chunks==1,"nearer building mesh displaces farther mesh under byte pressure")
	var scans: int = world.streaming_stats().residency_checks
	for i in range(20):
		world.set_focus(Vector3(40.1,8,8))
		world.flush_bakes()
	check(world.streaming_stats().residency_checks==scans,"sub-threshold focus motion does not rescan all building chunks")
	world.configure_streaming(true,64,1,16777216,1)
	world.flush_bakes()
	check(world.stats().mesh_chunks==1 and world.streaming_stats().wanted_chunks==1 and world.streaming_stats().cache_capacity_bytes<=1,"chunk-count limit and tiny cache budget are enforced independently")
	world.configure_streaming(false,64,1,65536,0)
	world.flush_bakes()
	check(world.stats().mesh_chunks==3 and not world.streaming_stats().enabled,"disabling streaming restores standalone all-chunk authoring")
	world.restore_snapshot(empty)
	world.flush_bakes()
	check(world.streaming_stats().mesh_payload_bytes==0 and world.streaming_stats().cache_capacity_bytes==0 and world.stats().collision_chunks==0,"empty world releases mesh, collision and cache residency")
	world.free()

func check_cached_publication() -> void:
	var world := make_world()
	world.configure_streaming(true,64,4,1048576,1048576)
	world.set_cells(PackedInt32Array([0,0,0,1,16,0,0,1,32,0,0,1]))
	world.set_focus(Vector3(8,8,8))
	world.flush_bakes()
	world.set_focus(Vector3(512,8,8))
	world.flush_bakes()
	var previous: int = world.stats().published_bakes
	world.set_focus(Vector3(8,8,8))
	var bounded := true
	for i in range(8):
		await process_frame
		var current: int = world.stats().published_bakes
		bounded=bounded and current-previous<=1
		previous=current
	check(bounded and world.is_idle() and world.stats().mesh_chunks==3 and world.streaming_stats().cache_hits==3,"cached reentry uploads at most one nonempty mesh per frame")
	var clear: Node3D = make_world()
	world.restore_snapshot(clear.capture_snapshot())
	clear.free()
	world.set_cells(PackedInt32Array([0,0,0,1]))
	for attempt in range(120):
		await process_frame
		if world.stats().worker_jobs==1:
			break
	check(world.stats().worker_jobs==1,"travel test has an actual in-flight building bake")
	world.set_focus(Vector3(512,8,8))
	for i in range(120):
		await process_frame
		if world.is_idle():
			break
	check(world.is_idle() and world.stats().mesh_chunks==0 and world.streaming_stats().cached_chunks==1,"completed out-of-range bake is cached without uploading a distant mesh")
	var jobs: int = world.streaming_stats().bake_jobs
	world.set_focus(Vector3(8,8,8))
	world.flush_bakes()
	check(world.stats().mesh_chunks==1 and world.streaming_stats().bake_jobs==jobs,"return uses the bake completed during travel")
	world.set_cells(PackedInt32Array([0,0,0,33]))
	await process_frame
	await process_frame
	world.set_focus(Vector3(512,8,8))
	world.set_cells(PackedInt32Array([0,0,0,65]))
	await process_frame
	world.set_focus(Vector3(8,8,8))
	world.flush_bakes()
	var latest_material := false
	for child in world.get_children():
		if child is MeshInstance3D:
			var arrays: Array = child.mesh.surface_get_arrays(0)
			latest_material=(arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[0].x==2.0
	check(latest_material and world.is_idle(),"edit during in-flight travel cannot cache or publish obsolete building material")
	world.free()

func run() -> void:
	check(ClassDB.class_exists("NativeBlockWorld"), "native block extension registered")
	check_exclusion()
	check_prefabs()
	check_history()
	check_history_model()
	await check_history_worker()
	check_streaming()
	await check_cached_publication()
	var world := make_world()
	var empty: PackedByteArray = world.capture_snapshot()
	check(world.validate_snapshot(empty), "empty snapshot validates")
	check(world.set_cells(PackedInt32Array([0,0,0,1])), "place cube")
	world.flush_bakes()
	check(world.stats().triangles == 12, "isolated cube is six merged quads")
	check(area_and_winding(world).is_equal_approx(Vector2(6,0)), "cube exact area and clockwise winding")
	check(world.set_cells(PackedInt32Array([1,0,0,1])), "place adjacent cube")
	world.flush_bakes()
	check(world.stats().triangles == 12, "adjacent cubes merge into six quads")
	check(area_and_winding(world).is_equal_approx(Vector2(10,0)), "adjacent cubes have no internal face")
	check(world.set_cells(PackedInt32Array([2,0,0,33])), "second material cube")
	world.flush_bakes()
	check(is_equal_approx(area_and_winding(world).x,14.0), "material boundary does not expose internal face")
	var before: PackedByteArray = world.capture_snapshot()
	check(not world.set_cells(PackedInt32Array([4,0,0,1,5,0,0,7])), "reject invalid shape in batch")
	check(world.capture_snapshot() == before, "invalid batch is atomic")
	check(not world.set_cells(PackedInt32Array([1048576,0,0,1])), "reject out of range coordinates")
	check(not world.set_cells(PackedInt32Array([0,0,0,129])), "reject reserved material bits")
	check(not world.set_cells(PackedInt32Array([0,0,0])), "reject incomplete records")
	check(world.restore_snapshot(empty), "clear using valid snapshot")
	check(world.set_cells(PackedInt32Array([-1,0,0,1,0,0,0,1,15,0,0,1,16,0,0,1])), "edit across positive and negative chunk seams")
	world.flush_bakes()
	check(world.stats().chunks == 3, "negative floor division and positive seam ownership")
	check(area_and_winding(world).is_equal_approx(Vector2(20,0)), "no internal faces at either chunk seam")
	check(world.get_cell(Vector3i(-1,0,0)) == 1, "negative coordinate lookup")
	check(world.set_cells(PackedInt32Array([-1,0,0,0])), "remove sole cell in negative chunk")
	world.flush_bakes()
	check(world.stats().chunks == 2 and is_equal_approx(area_and_winding(world).x,16), "empty chunk reclaimed and neighbour face restored")
	for shape in range(1,6):
		for rotation in range(4):
			world.restore_snapshot(empty)
			check(world.set_cells(PackedInt32Array([0,0,0,shape+(rotation<<3)])), "shape %d rotation %d accepted" % [shape,rotation])
			world.flush_bakes()
			var metrics := area_and_winding(world)
			var expected: float = [0.0,6.0,4.0,5.25,3.0+sqrt(2.0),2.5][shape]
			check(is_equal_approx(metrics.x,expected) and metrics.y==0, "shape %d rotation %d exact boundary and winding" % [shape,rotation])
	# Adjacent rotated stairs/slabs use the same occupancy mesh as cubes.
	world.restore_snapshot(empty)
	world.set_cells(PackedInt32Array([0,0,0,2,1,0,0,2]))
	world.flush_bakes()
	check(world.stats().triangles == 12 and is_equal_approx(area_and_winding(world).x,7), "adjacent slabs merge without hidden faces")
	var snapshot: PackedByteArray = world.capture_snapshot()
	var restored := make_world()
	check(restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot, "deterministic snapshot round trip")
	var corrupt := snapshot.duplicate()
	corrupt[20] ^= 1
	check(not restored.validate_snapshot(corrupt) and not restored.restore_snapshot(corrupt), "corrupt snapshot rejected")
	check(restored.capture_snapshot()==snapshot, "rejected load preserves live building")
	check(not restored.validate_snapshot(snapshot.slice(0, snapshot.size()-1)), "truncated snapshot rejected")
	# Launch a real worker, then edit its dependency before publication.
	world.restore_snapshot(empty)
	world.set_cells(PackedInt32Array([0,0,0,1]))
	await process_frame
	await process_frame
	world.set_cells(PackedInt32Array([1,0,0,1]))
	world.flush_bakes()
	check(world.stats().stale_bakes_rejected > 0, "stale worker output discarded after edit")
	check(area_and_winding(world).is_equal_approx(Vector2(10,0)), "latest edit is eventually published")
	world.restore_snapshot(empty)
	world.flush_bakes()
	for i in range(2000):
		world.set_cells(PackedInt32Array([i*16,0,0,1]))
		world.set_cells(PackedInt32Array([i*16,0,0,0]))
	check(world.stats().chunks==0 and world.stats().dirty_chunks==0, "repeated distant placement/removal retains no empty chunks or dirty tombstones")
	# A dense 16-cubed building block compresses to exactly six outer rectangles.
	var dense := PackedInt32Array()
	for z in range(16):
		for y in range(16):
			for x in range(16):
				dense.append_array(PackedInt32Array([x,y,z,1]))
	var start := Time.get_ticks_usec()
	world.set_cells(dense)
	world.flush_bakes()
	evidence.dense_bake_ms = (Time.get_ticks_usec()-start)/1000.0
	check(world.stats().cells==4096 and world.stats().triangles==12, "4096 solid cubes become 12 triangles")
	check(world.capture_snapshot().size()==60, "dense chunk RLE snapshot is 60 bytes with checksum")
	restored.free()
	# Real physics rays check exact staircase treads and the sloped collision plane.
	world.restore_snapshot(empty)
	world.set_cells(PackedInt32Array([0,0,0,3,3,0,0,4]))
	world.flush_bakes()
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	for step in range(4):
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.5,3,step*0.25+0.125),Vector3(0.5,-1,step*0.25+0.125),2))
		check(not hit.is_empty() and is_equal_approx(hit.position.y,(step+1)*0.25), "stair collision tread %d" % step)
	var slope := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3.5,3,0.625),Vector3(3.5,-1,0.625),2))
	check(not slope.is_empty() and is_equal_approx(slope.position.y,0.625), "true slope collision plane")
	world.set_focus(Vector3(1000,1000,1000))
	await process_frame
	await process_frame
	check(world.stats().collision_chunks==0, "far physics bodies released")
	var models: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(models)
	var transforms := PackedFloat32Array([1,0,0,-1,0,1,0,0,0,0,1,0, 1,0,0,33,0,1,0,0,0,0,1,0])
	var mesh := BoxMesh.new()
	check(models.set_instances(mesh,transforms), "static mesh transform upload")
	check(models.stats().instances==2 and models.stats().spatial_batches==2, "static model instances partition at signed spatial boundaries")
	transforms[0]=NAN
	check(not models.set_instances(mesh,transforms) and models.stats().instances==2, "invalid static transform rejected atomically")
	check(models.set_instances(mesh,PackedFloat32Array()) and models.get_child_count()==0, "static batches reclaimed on clear")
	var many := PackedFloat32Array()
	many.resize(100000*12)
	for i in range(100000):
		many[i*12]=1
		many[i*12+5]=1
		many[i*12+10]=1
		many[i*12+3]=(i%100)*2
		many[i*12+7]=(i/10000)*3
		many[i*12+11]=((i/100)%100)*2
	start = Time.get_ticks_usec()
	check(models.set_instances(mesh,many), "100000 static model instances accepted")
	evidence.static_100k_upload_ms = (Time.get_ticks_usec()-start)/1000.0
	evidence.static_100k = models.stats()
	check(models.stats().spatial_batches==49 and models.stats().transform_bytes==4800000, "100000 placements use 49 batches and 4.8 MB of transform payload")
	many.append(1)
	check(not models.set_instances(mesh,many), "static model capacity/record limit enforced")
	var showcase := make_world()
	start = Time.get_ticks_usec()
	showcase.create_showcase()
	showcase.flush_bakes()
	evidence.showcase_bake_ms = (Time.get_ticks_usec()-start)/1000.0
	evidence.showcase = showcase.stats()
	check(showcase.stats().cells > 8000 and showcase.stats().mesh_chunks < 100, "house/tower showcase uses chunks rather than block nodes")
	evidence.checks=checks
	evidence.failures=failures
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output := FileAccess.open("res://reports/structures.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence,"  "))
	output.close()
	world.free()
	models.free()
	showcase.free()
	print("STRUCTURES_RESULT ", JSON.stringify(evidence))
	quit(1 if failures else 0)
