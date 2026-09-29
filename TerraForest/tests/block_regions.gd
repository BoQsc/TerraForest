extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockWorld"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func checksum(bytes: PackedByteArray) -> PackedByteArray:
	var payload := bytes.slice(0,bytes.size()-32)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	payload.append_array(hash.finish())
	return payload

func run() -> void:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.configure_history(1024*1024,128)
	check(world.set_cells(PackedInt32Array([-65,0,0,1,-64,0,0,2,-1,0,0,3,0,0,0,4,63,0,0,5,64,0,0,6])),"author signed region-boundary fixtures")
	var key := Vector3i(-1,0,0)
	var packet: PackedByteArray = world.capture_region(key)
	check(world.validate_region_snapshot(packet) and packet.decode_u32(32)==2,"64-cell region captures only its two occupied signed chunks")
	check(world.capture_region(Vector3i(16384,0,0)).is_empty() and not world.is_region_loaded(Vector3i(-16385,0,0)),"region coordinates are bounded before multiplication")
	check(packet==world.capture_region(key),"region encoding is deterministic")
	var damaged := packet.duplicate()
	damaged[26]^=1
	check(not world.validate_region_snapshot(damaged) and not world.unload_region(damaged),"corrupt region cannot validate or evict authored data")
	check(not world.validate_region_snapshot(packet.slice(0,packet.size()-1)),"truncated region rejected")
	var moved := packet.duplicate()
	moved.encode_s32(8,0)
	moved=checksum(moved)
	check(not world.validate_region_snapshot(moved),"valid checksum cannot bind foreign chunks to a different region")
	var malformed := packet.duplicate()
	malformed.encode_u32(20,1)
	malformed=checksum(malformed)
	check(not world.validate_region_snapshot(malformed),"declared region payload length must match")
	world.set_cells(PackedInt32Array([-1,0,0,6]))
	var changed: PackedByteArray = world.capture_snapshot()
	check(not world.unload_region(packet) and world.capture_snapshot()==changed,"edit after capture rejects stale unload without mutation")
	packet=world.capture_region(key)
	world.set_cells(PackedInt32Array([64,0,0,1]))
	var complete: PackedByteArray = world.capture_snapshot()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/block_region_roundtrip.tfrg",FileAccess.WRITE)
	file.store_buffer(packet)
	file.flush()
	file.close()
	var disk := FileAccess.get_file_as_bytes("res://reports/block_region_roundtrip.tfrg")
	check(disk==packet,"region packet survives a real file round trip")
	check(world.unload_region(packet),"unrelated region edit does not invalidate local unload acknowledgement")
	check(world.get_cell(Vector3i(-64,0,0))==0 and world.get_cell(Vector3i(-65,0,0))==1 and world.get_cell(Vector3i(64,0,0))==1,"unload reclaims only the addressed authored chunks")
	check(world.region_stats().resident_chunks==4 and world.region_stats().unloaded_regions==1 and world.region_stats().unloaded_digest_bytes==32,"unloaded region retains a digest rather than its cell payload")
	check(not world.can_undo() and not world.can_redo(),"region transfer creates a history barrier")
	check(world.capture_snapshot().is_empty() and world.capture_region(key).is_empty(),"whole-world and region captures cannot silently omit unavailable data")
	var codec: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray())
	check(codec.encode(world.capture_snapshot(),{}).is_empty(),"compound structure save also rejects omitted unloaded regions")
	check(not world.is_region_loaded(key) and world.is_region_loaded(Vector3i.ZERO),"region availability distinguishes missing from authored-empty data")
	check(not world.is_collision_region_ready(AABB(Vector3(-32,4,4),Vector3.ONE)),"walking blocks even in apparently empty space of an unloaded region")
	world.position=Vector3(100,0,0)
	check(not world.is_collision_region_ready(AABB(Vector3(68,4,4),Vector3.ONE)),"unavailable-region readiness respects the block-world transform")
	world.position=Vector3.ZERO
	check(world.is_collision_region_ready(AABB(Vector3(1000,0,0),Vector3.ONE)),"unrelated empty region remains ready")
	check(not world.set_cells(PackedInt32Array([1,0,0,1,-2,0,0,1])) and world.get_cell(Vector3i(1,0,0))==0,"mixed edit touching missing data fails atomically")
	var prefab: Resource = ClassDB.instantiate("NativeBlockPrefab")
	prefab.configure(PackedInt32Array([0,0,0,1]))
	check(not world.can_place_prefab(prefab,Vector3i(-3,0,0),0,true),"prefab replacement cannot overwrite an unloaded region")
	check(world.capture_prefab(Vector3i(-32,0,0),Vector3i.ONE)==null,"prefab capture cannot mistake unavailable data for air")
	var mask: PackedByteArray = world.overlap_mask([Transform3D(Basis(),Vector3(-32,0,0))],AABB(Vector3.ZERO,Vector3.ONE))
	check(mask.size()==1 and mask[0]==1,"vegetation exclusion conservatively reserves unavailable regions")
	var other: Node3D = ClassDB.instantiate("NativeBlockWorld")
	other.set_cells(PackedInt32Array([-1,0,0,1]))
	check(not world.restore_region(other.capture_region(key),PackedByteArray()),"wrong version of unloaded region cannot replace its acknowledged packet")
	check(not world.restore_region(disk,disk),"unloaded restore requires an explicit empty current-state token")
	check(world.restore_region(disk,PackedByteArray()) and world.capture_snapshot()==complete,"disk-backed reload restores exact world bytes and leaves other regions unchanged")
	check(world.is_region_loaded(key) and world.region_stats().unloaded_regions==0,"reload clears missing-region metadata")
	var before: PackedByteArray = world.capture_snapshot()
	check(not world.restore_region(other.capture_region(key),PackedByteArray()) and world.capture_snapshot()==before,"resident replacement requires a matching captured current packet")
	check(world.restore_region(other.capture_region(key),world.capture_region(key)) and world.get_cell(Vector3i(-64,0,0))==0,"conditional replacement atomically removes obsolete chunks in only one region")
	var cycle_packet: PackedByteArray = world.capture_region(key)
	var cycle_snapshot: PackedByteArray = world.capture_snapshot()
	var cycles_ok := true
	for i in range(40): cycles_ok=world.unload_region(cycle_packet) and world.restore_region(cycle_packet,PackedByteArray()) and cycles_ok
	check(cycles_ok and world.capture_snapshot()==cycle_snapshot,"forty eviction/reload cycles preserve authored bytes")
	world.unload_region(cycle_packet)
	check(not world.restore_snapshot(damaged) and not world.is_region_loaded(key),"failed full-world restore preserves region availability")
	check(world.restore_snapshot(complete) and world.is_region_loaded(key),"explicit valid full-world replacement resets region transfer state")
	var empty: PackedByteArray = other.capture_region(Vector3i(100,0,0))
	check(empty.size()==100 and other.validate_region_snapshot(empty),"authored-empty region has a valid bounded canonical packet")
	check(other.unload_region(empty) and not other.is_region_loaded(Vector3i(100,0,0)) and other.restore_region(empty,PackedByteArray()),"empty-region availability round trips independently of cell occupancy")
	other.free()
	world.free()
	check_capacity(disk)
	await check_halos()
	var report := {"checks":checks,"failures":failures}
	file=FileAccess.open("res://reports/block_regions.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(1 if failures else 0)

func check_capacity(packet: PackedByteArray) -> void:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var records := PackedInt32Array()
	for i in range(2048): records.append_array(PackedInt32Array([(i%64)*16,(i/64)*16,128,1]))
	check(world.set_cells(records),"fill resident chunk capacity outside the incoming region")
	var before: PackedByteArray = world.capture_snapshot()
	check(not world.restore_region(packet,world.capture_region(Vector3i(-1,0,0))) and world.capture_snapshot()==before,"capacity overflow rejects the whole region without evicting unrelated data")
	world.free()

func check_halos() -> void:
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(world)
	world.set_focus(Vector3(64,0,0))
	world.set_cells(PackedInt32Array([63,0,0,1,64,0,0,1]))
	world.flush_bakes()
	check(world.stats().triangles==20,"adjacent cubes share a face across the region boundary")
	var packet: PackedByteArray = world.capture_region(Vector3i.ZERO)
	world.unload_region(packet)
	world.flush_bakes()
	check(world.stats().triangles==12 and world.stats().chunks==1,"unload retires old visuals and rebuilds the retained neighbor halo")
	world.restore_region(packet,PackedByteArray())
	world.flush_bakes()
	check(world.stats().triangles==20,"reload rebuilds both sides of a region seam")
	world.set_cells(PackedInt32Array([62,0,0,6]))
	for i in range(8):
		await process_frame
		if world.stats().worker_jobs==1: break
	check(world.stats().worker_jobs==1,"region fixture observes an outstanding native bake before unloading")
	packet=world.capture_region(Vector3i.ZERO)
	check(world.unload_region(packet),"region unload accepts a matching capture while baking is outstanding")
	world.flush_bakes()
	check(world.get_cell(Vector3i(62,0,0))==0 and world.stats().triangles==12,"stale worker result cannot republish an unloaded region")
	world.free()
	await process_frame
