extends SceneTree
var checks := 0
var failures := 0
var gpu := DisplayServer.get_name() != "headless"

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
	var result := {"checks":checks,"failures":failures,"gpu_readback":gpu}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/static_placements_gpu.json" if gpu else "res://reports/static_placements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	world.free()
	copy.free()
	print("STATIC_PLACEMENTS_RESULT ",JSON.stringify(result))
	quit(1 if failures else 0)
