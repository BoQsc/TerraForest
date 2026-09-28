extends SceneTree
var checks := 0
var failures := 0
var gpu := DisplayServer.get_name() != "headless"
var collision_evidence := {}

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ")+description)

func transform_at(x: float, y := 0.0, z := 0.0) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,x,0,1,0,y,0,0,1,z])

func signed_snapshot(payload: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	payload.append_array(hash.finish())
	return payload

func _initialize() -> void:
	if not ClassDB.class_exists("NativeStaticBatch"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func settle_collision(world: Node3D) -> void:
	for i in range(30):
		await physics_frame
		await process_frame
		var status: Dictionary = world.collision_stats()
		if not status.selection_pending and status.pending_bodies==0:
			break
	await physics_frame
	await process_frame

func collision_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,2)
	return root.get_world_3d().direct_space_state.intersect_ray(query)

func check_collision() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	world.configure_asset("tests/collision_box",BoxMesh.new())
	var box := AABB(Vector3(-0.5,-0.5,-0.5),Vector3.ONE)
	check(not world.collision_stats().enabled,"static collision defaults to opt-in")
	world.upsert_instances(PackedInt64Array([17,9000000001,33]),transform_at(0)+transform_at(8)+transform_at(80))
	var saved: PackedByteArray = world.capture_snapshot()
	check(world.configure_collision(box,16,2,1),"configure bounded native static collision")
	var bounded := true
	var previous: int = world.collision_stats().body_builds
	var previous_tick := Engine.get_physics_frames()
	for i in range(5):
		await physics_frame
		await process_frame
		var now: int = world.collision_stats().body_builds
		bounded=bounded and now-previous<=Engine.get_physics_frames()-previous_tick
		previous=now
		previous_tick=Engine.get_physics_frames()
	check(bounded and world.collision_stats().resident_bodies==2,"nearby proxies publish within one-body-per-tick budget")
	check(world.get_child_count()==world.stats().spatial_batches,"native collision adds no per-placement scene nodes")
	var hit := collision_ray(Vector3(8,3,0),Vector3(8,-3,0))
	check(not hit.is_empty() and hit.collider==world and world.placement_for_body(hit.rid)==9000000001,"physics ray resolves exact stable 64-bit placement ID")
	check(collision_ray(Vector3(80,3,0),Vector3(80,-3,0)).is_empty(),"distant static placements have no physics body")
	check(world.capture_snapshot()==saved,"collision residency does not change placement snapshots")
	var corrupt := saved.duplicate()
	corrupt[40]^=1
	var invalid := transform_at(3)
	invalid[0]=NAN
	var builds_before: int = world.collision_stats().body_builds
	check(not world.restore_snapshot(corrupt) and not world.upsert_instances(PackedInt64Array([17]),invalid),"invalid load and edit reject before changing physics")
	await settle_collision(world)
	check(world.collision_stats().body_builds==builds_before and world.collision_stats().resident_bodies==2,"rejected commands preserve existing physics handles")
	var queries: int = world.collision_stats().selection_queries
	world.set_collision_focus(Vector3(0.1,0,0))
	await settle_collision(world)
	check(world.collision_stats().selection_queries==queries,"small focus changes avoid repeated placement scans")
	check(not world.configure_collision(box,NAN,2,1) and not world.configure_collision(box,16,0,1) and not world.configure_collision(box,16,2,0),"invalid budgets preserve collision configuration")
	check(not world.configure_collision(AABB(Vector3.ZERO,Vector3(-1,1,1)),16,2,1),"invalid proxy geometry rejected")
	check(world.collision_stats().resident_bodies==2 and world.collision_stats().radius==16,"invalid configuration preserves existing collision")
	world.set_collision_focus(Vector3(80,0,0))
	await settle_collision(world)
	check(world.collision_stats().resident_bodies==1 and collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).is_empty(),"travel evicts old bodies and admits the nearby placement")
	hit=collision_ray(Vector3(80,3,0),Vector3(80,-3,0))
	check(not hit.is_empty() and world.placement_for_body(hit.rid)==33,"travelled-to object has its own collision identity")
	world.set_collision_focus(Vector3.ZERO)
	await settle_collision(world)
	var stale_rid: RID = collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).rid
	world.upsert_instances(PackedInt64Array([9000000001]),transform_at(12))
	check(world.placement_for_body(stale_rid)==0,"moving a placement immediately invalidates its old physics identity")
	await settle_collision(world)
	check(collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).is_empty() and not collision_ray(Vector3(12,3,0),Vector3(12,-3,0)).is_empty(),"local render edit also moves static collision")
	world.remove_instances(PackedInt64Array([9000000001]))
	await settle_collision(world)
	check(collision_ray(Vector3(12,3,0),Vector3(12,-3,0)).is_empty(),"removal releases collision")
	check(world.restore_snapshot(saved),"restore collidable placements")
	await settle_collision(world)
	check(not collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).is_empty(),"snapshot restore rebuilds application-configured proxies")
	# A large scaled proxy crosses several origin groups; selection uses its bounds.
	world.upsert_instances(PackedInt64Array([44]),PackedFloat32Array([100,0,0,65,0,1,0,0,0,0,1,0]))
	world.set_collision_focus(Vector3(20,0,0))
	await settle_collision(world)
	hit=collision_ray(Vector3(20,3,0),Vector3(20,-3,0))
	check(not hit.is_empty() and world.placement_for_body(hit.rid)==44,"large proxy crossing origin groups remains selectable by its bounds")
	check(world.configure_collision(box,128,1,1),"collision count cap can shrink")
	await settle_collision(world)
	check(world.collision_stats().resident_bodies==1 and world.collision_stats().budget_deferred==3,"nearest admission reports capacity-deferred collision")
	world.restore_snapshot(saved)
	world.configure_collision(box,16,2,2)
	world.set_collision_focus(Vector3.ZERO)
	# Nonuniform scale and shear are baked into convex vertices, not body scale.
	world.upsert_instances(PackedInt64Array([17]),PackedFloat32Array([2,0.5,0,0,0,2,0,0,0,0,3,0]))
	await settle_collision(world)
	hit=collision_ray(Vector3(0,3,0),Vector3(0,-3,0))
	check(not hit.is_empty() and absf(hit.position.y-1.0)<0.02,"affine placement basis produces matching convex proxy surface")
	world.position=Vector3(0,10,0)
	world.scale=Vector3(1,2,1)
	await settle_collision(world)
	hit=collision_ray(Vector3(0,15,0),Vector3(0,5,0))
	check(not hit.is_empty() and absf(hit.position.y-12.0)<0.02,"collection transform updates physics without scaled-body mismatch")
	root.remove_child(world)
	check(world.collision_stats().resident_bodies==0,"leaving the scene releases all native physics handles")
	root.add_child(world)
	await settle_collision(world)
	check(world.collision_stats().resident_bodies==2,"reentering the scene rebuilds collision")
	var viewport := SubViewport.new()
	viewport.own_world_3d=true
	root.add_child(viewport)
	world.reparent(viewport)
	await settle_collision(world)
	check(collision_ray(Vector3(0,15,0),Vector3(0,5,0)).is_empty(),"moving to a private physics world removes collision from the old world")
	# Retain the departing World3D through Godot's viewport scenario reassignment.
	var private_world: World3D = world.get_world_3d()
	var private_hit := private_world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,15,0),Vector3(0,5,0),2))
	check(not private_hit.is_empty() and world.placement_for_body(private_hit.rid)==17,"private physics world receives the placement proxies")
	viewport.own_world_3d=false
	await settle_collision(world)
	check(not collision_ray(Vector3(0,15,0),Vector3(0,5,0)).is_empty(),"in-tree world reassignment rebinds native bodies to the new space")
	world.reparent(root)
	viewport.free()
	check(world.configure_collision(box,0,2,2) and world.collision_stats().resident_bodies==0,"disabling collision releases bodies immediately")
	# Repeated travel checks bounded retained handles, not a long-duration benchmark.
	world.transform=Transform3D.IDENTITY
	world.restore_snapshot(saved)
	world.configure_collision(box,16,2,2)
	var travel_ok := true
	for i in range(20):
		world.set_collision_focus(Vector3.ZERO if i%2==0 else Vector3(80,0,0))
		await settle_collision(world)
		travel_ok=travel_ok and world.collision_stats().resident_bodies==(2 if i%2==0 else 1)
	check(travel_ok and world.capture_snapshot()==saved,"twenty visits retain only nearby physics and preserve authored records")
	var dense := PackedFloat32Array()
	dense.resize(100000*12)
	for i in range(100000):
		var p := transform_at((i%1000)*2,0,(i/1000)*2)
		for j in range(12):
			dense[i*12+j]=p[j]
	world.configure_collision(box,16,16,4)
	world.set_collision_focus(Vector3.ZERO)
	check(world.set_instances(BoxMesh.new(),dense),"100000 placements coexist with bounded collision configuration")
	await settle_collision(world)
	collision_evidence=world.collision_stats()
	check(collision_evidence.resident_bodies==16 and collision_evidence.budget_deferred>0 and collision_evidence.pending_bodies==0,"100000-placement collection admits only sixteen nearest physics bodies")
	check(world.get_child_count()==world.stats().spatial_batches,"large collidable collection retains only spatial render nodes")
	# A real character controller must stand on a scaled static model floor.
	world.set_instances(BoxMesh.new(),PackedFloat32Array([8,0,0,0,0,1,0,0,0,0,8,0]))
	world.set_collision_focus(Vector3.ZERO)
	await settle_collision(world)
	var player := CharacterBody3D.new()
	player.collision_mask=2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.25
	capsule.height=1
	shape.shape=capsule
	player.add_child(shape)
	root.add_child(player)
	player.position=Vector3(0,3,0)
	for i in range(90):
		await physics_frame
		player.velocity.y-=9.8/60.0
		player.move_and_slide()
	check(player.is_on_floor() and absf(player.position.y-1.0)<0.06,"CharacterBody3D lands on the placed model floor")
	player.free()
	world.free()
	await physics_frame
	await process_frame
	check(collision_ray(Vector3(0,3,0),Vector3(0,-3,0)).is_empty(),"destroying collection leaves no ghost physics")

func check_compound_collision() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	var mesh: Mesh = load("res://addons/structures/prefabs/doorway_model.tres")
	var boxes: Array[AABB] = mesh.get_meta("collision_boxes")
	world.configure_asset("architecture/doorway/v1",mesh)
	world.upsert_instances(PackedInt64Array([11,22,33]),transform_at(0)+transform_at(8)+transform_at(16))
	check(world.configure_compound_collision(boxes,64,3,8,6,3),"compound doorway uses explicit body and shape budgets")
	var before: int = world.collision_stats().body_builds
	var tick := Engine.get_physics_frames()
	var bounded := true
	for i in range(5):
		await physics_frame
		await process_frame
		var built: int = world.collision_stats().body_builds
		bounded=bounded and (built-before)*3<=(Engine.get_physics_frames()-tick)*3
		before=built
		tick=Engine.get_physics_frames()
	var status: Dictionary = world.collision_stats()
	check(bounded and status.resident_bodies==2 and status.resident_shapes==6 and status.budget_deferred==1,"shape budgets bound residency and tick publication independently of body budgets")
	check(collision_ray(Vector3(0,1,-2),Vector3(0,1,2)).is_empty(),"doorway opening is not filled by the union bounding box")
	for point in [Vector3(-1.5,1,0),Vector3(1.5,1,0),Vector3(0,2.5,0)]:
		var hit := collision_ray(point+Vector3(0,0,-2),point+Vector3(0,0,2))
		check(not hit.is_empty() and world.placement_for_body(hit.rid)==11,"each doorway part resolves to the same placement identity")
	var player := CharacterBody3D.new()
	player.collision_mask=2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.25
	capsule.height=1
	shape.shape=capsule
	player.add_child(shape)
	root.add_child(player)
	player.position=Vector3(0,1,-2)
	check(player.move_and_collide(Vector3(0,0,4))==null and player.position.z>1.9,"character passes through the compound doorway")
	player.position=Vector3(1.5,1,-2)
	check(player.move_and_collide(Vector3(0,0,4))!=null and player.position.z<0,"character is stopped by the door post")
	player.free()
	check(not world.configure_compound_collision(boxes,64,3,8,2,3) and not world.configure_compound_collision(boxes,64,3,8,6,2),"budgets too small for one complete compound body reject atomically")
	var bad: Array[AABB] = boxes.duplicate()
	bad.append(AABB(Vector3.ZERO,Vector3.ZERO))
	check(not world.configure_compound_collision(bad,64,3,8,6,3),"invalid part rejects the entire compound configuration")
	var excess: Array[AABB] = []
	for i in range(33):
		excess.append(boxes[0])
	check(not world.configure_compound_collision(excess,64,3,8,100,64),"compound part count is bounded")
	check(world.collision_stats().resident_shapes==6,"rejected compound configurations preserve live bodies")
	boxes[0]=AABB(Vector3(50,0,0),Vector3.ONE)
	world.set_collision_focus(Vector3(16,0,0))
	await settle_collision(world)
	world.set_collision_focus(Vector3.ZERO)
	await settle_collision(world)
	check(not collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty(),"caller array mutation cannot alter retained compound metadata")
	var saved: PackedByteArray = world.capture_snapshot()
	world.remove_instances(PackedInt64Array([11]))
	await settle_collision(world)
	check(collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty(),"removal releases every part of a compound body")
	world.restore_snapshot(saved)
	await settle_collision(world)
	check(not collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty() and collision_ray(Vector3(0,1,-2),Vector3(0,1,2)).is_empty(),"restore reconstructs compound solids and openings")
	world.free()
	await physics_frame
	await process_frame
	check(collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty(),"compound destruction leaves no ghost shapes")

func run() -> void:
	if gpu:
		DisplayServer.window_set_size(Vector2i(1920,1080))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		await process_frame
		check(DisplayServer.window_get_size()==Vector2i(1920,1080) and DisplayServer.window_get_mode()==4, "GPU test uses 1920x1080 exclusive fullscreen")
		check(root.get_texture().get_size()==Vector2(1920,1080), "GPU test render target is 1920x1080")
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	var mesh := BoxMesh.new()
	check(not world.upsert_instances(PackedInt64Array([1]),transform_at(0)), "reject edits before mesh configuration")
	check(world.capture_snapshot().is_empty(), "unconfigured collection cannot silently save anonymous assets")
	check(not world.configure_asset("",mesh) and not world.configure_asset("bad key",mesh), "reject invalid asset keys")
	check(world.configure_asset("architecture/fence",mesh), "configure stable asset key")
	var empty: PackedByteArray = world.capture_snapshot()
	check(world.validate_snapshot(empty), "empty configured snapshot validates")
	var data := transform_at(-1)+transform_at(1)+transform_at(65)
	check(world.upsert_instances(PackedInt64Array([17,42,9000000001]),data), "insert explicit 64-bit stable IDs")
	check(world.get_ids()==PackedInt64Array([17,42,9000000001]), "IDs remain sorted and preserve 64-bit precision")
	check(world.get_instance(17)==transform_at(-1), "retrieve exact authored transform")
	check(world.get_instance(999).is_empty(), "missing object returns no transform")
	var far_node := world.get_child(2).get_instance_id()
	var uploads: int = world.stats().batch_uploads
	check(world.upsert_instances(PackedInt64Array([42]),transform_at(2)), "move object inside group")
	check(world.stats().batch_uploads==uploads and world.stats().instance_updates==1, "single local edit updates one GPU slot without rebuilding its group")
	var local_batch: MultiMeshInstance3D = world.get_child(1)
	if gpu:
		check(local_batch.multimesh.get_instance_transform(0).origin==Vector3(2,0,0), "GPU slot contains updated local translation")
	check(world.get_child(2).get_instance_id()==far_node, "unrelated group keeps its scene node")
	uploads = world.stats().batch_uploads
	check(world.upsert_instances(PackedInt64Array([42]),transform_at(2)) and world.stats().batch_uploads==uploads, "identical edit performs no GPU upload")
	var rotated := PackedFloat32Array([0,0,2,2,0,3,0,0,-4,0,0,0])
	check(world.upsert_instances(PackedInt64Array([42]),rotated), "direct slot update accepts rotated scaled basis")
	if gpu:
		var rendered := local_batch.multimesh.get_instance_transform(0)
		check(rendered.basis.x==Vector3(0,0,-4) and rendered.basis.y==Vector3(0,3,0) and rendered.basis.z==Vector3(2,0,0), "direct slot update preserves matrix row/column convention")
	check(world.upsert_instances(PackedInt64Array([42]),transform_at(-2)), "move existing ID across signed group boundary")
	check(world.stats().spatial_batches==2 and world.get_instance(42)==transform_at(-2), "move reclaims old empty group and preserves ID")
	var before: PackedByteArray = world.capture_snapshot()
	check(not world.upsert_instances(PackedInt64Array([17,17]),transform_at(1)+transform_at(2)), "duplicate IDs rejected")
	check(not world.upsert_instances(PackedInt64Array([0]),transform_at(1)), "zero ID rejected")
	check(not world.upsert_instances(PackedInt64Array([-1]),transform_at(1)), "negative ID rejected")
	check(not world.upsert_instances(PackedInt64Array([17]),PackedFloat32Array([1])), "incomplete transform rejected")
	var invalid := transform_at(1)
	invalid[0]=0
	check(not world.upsert_instances(PackedInt64Array([17]),invalid), "singular basis rejected")
	invalid[0]=INF
	check(not world.upsert_instances(PackedInt64Array([17]),invalid), "nonfinite basis rejected")
	check(not world.remove_instances(PackedInt64Array([17,99])), "mixed existing/missing removal rejected")
	check(not world.remove_instances(PackedInt64Array([17,17])), "duplicate removal IDs rejected")
	check(not world.configure_asset("different/mesh",mesh), "populated asset identity cannot change silently")
	check(world.capture_snapshot()==before, "all rejected commands preserve snapshot bytes")
	var copy: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(copy)
	copy.configure_asset("wrong/asset",mesh)
	check(copy.validate_snapshot(before) and not copy.restore_snapshot(before), "valid snapshot with unresolved asset identity rejected on restore")
	copy.configure_asset("architecture/fence",mesh)
	check(copy.restore_snapshot(before) and copy.capture_snapshot()==before, "asset-bound snapshot round trip preserves IDs/transforms")
	var corrupt := before.duplicate()
	corrupt[40]^=1
	check(not copy.restore_snapshot(corrupt), "checksum catches accidental corruption")
	check(not copy.restore_snapshot(before.slice(0,before.size()-1)), "truncated snapshot rejected")
	# Re-sign malicious fields to test semantic validation beyond checksum integrity.
	var first_record := 16+"architecture/fence".length()
	var payload := before.slice(0,before.size()-32)
	payload.encode_u64(first_record,0)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed zero placement ID rejected")
	payload=before.slice(0,before.size()-32)
	payload.encode_u64(first_record+56,17)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed duplicate placement ID rejected")
	payload=before.slice(0,before.size()-32)
	payload.encode_float(first_record+8,NAN)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed NaN transform rejected")
	payload=before.slice(0,before.size()-32)
	payload.encode_u32(12,100001)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed excessive count rejected before allocation")
	check(copy.capture_snapshot()==before, "rejected loads preserve published collection")
	check(world.remove_instances(PackedInt64Array([17])) and world.get_ids()==PackedInt64Array([42,9000000001]), "removal preserves all remaining IDs")
	check(world.restore_snapshot(empty) and world.get_child_count()==0, "restoring empty collection releases all render batches")
	var dense_ids := PackedInt64Array()
	var dense_transforms := PackedFloat32Array()
	var dense_moved := PackedFloat32Array()
	for i in range(100):
		dense_ids.append(i+1)
		dense_transforms.append_array(transform_at(i%16))
		dense_moved.append_array(transform_at(i%16+0.125))
	world.upsert_instances(dense_ids,dense_transforms)
	uploads=world.stats().batch_uploads
	var individual: int = world.stats().instance_updates
	check(world.upsert_instances(dense_ids,dense_moved), "large same-group update accepted")
	check(world.stats().batch_uploads==uploads+1 and world.stats().instance_updates==individual, "large edit uses one bulk upload instead of individual renderer calls")
	world.restore_snapshot(empty)
	# Maximum group count is checked against the final transaction, allowing swaps.
	var ids := PackedInt64Array()
	var transforms := PackedFloat32Array()
	for i in range(4096):
		ids.append(i+1)
		transforms.append_array(transform_at(i*32))
	check(world.upsert_instances(ids,transforms), "4096 spatial group boundary accepted")
	before=world.capture_snapshot()
	check(not world.upsert_instances(PackedInt64Array([5000]),transform_at(4096*32)), "4097th spatial group rejected atomically")
	check(world.capture_snapshot()==before, "group overflow leaves collection unchanged")
	check(world.upsert_instances(PackedInt64Array([1]),transform_at(4096*32)), "moving singleton group at capacity allowed")
	check(world.stats().spatial_batches==4096 and world.stats().instances==4096, "capacity move retains exact limits")
	world.restore_snapshot(empty)
	for i in range(1000):
		world.upsert_instances(PackedInt64Array([i+1]),transform_at(i*32))
		world.remove_instances(PackedInt64Array([i+1]))
	check(world.stats().instances==0 and world.stats().spatial_batches==0 and world.stats().slot_entries==0 and world.get_child_count()==0, "repeated placement/removal retains no spatial or slot tombstones")
	await check_collision()
	await check_compound_collision()
	var result := {"checks":checks,"failures":failures,"gpu_readback":gpu,"collision_100k":collision_evidence}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/static_placements_gpu.json" if gpu else "res://reports/static_placements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	world.free()
	copy.free()
	print("STATIC_PLACEMENTS_RESULT ",JSON.stringify(result))
	quit(1 if failures else 0)
