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

func run() -> void:
	check(ClassDB.class_exists("NativeBlockWorld"), "native block extension registered")
	check_exclusion()
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
