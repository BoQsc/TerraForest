extends SceneTree
const Structures = preload("res://addons/structures/structures_world.gd")
const Terrain = preload("res://addons/volumetric_terrain/terrain_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func bytes_at(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)

func write_bytes(path: String,bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func codec() -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	result.configure_assets(PackedStringArray())
	return result

func storage_bytes(c: RefCounted,w: Node3D,base: PackedByteArray) -> PackedByteArray:
	var state: Dictionary = w.capture_storage_state()
	return c.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,{},base)

func run() -> void:
	Engine.max_fps=240
	var directory := ProjectSettings.globalize_path("res://reports/metadata_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	check_restore()
	check_recovery(directory.path_join("recovery.trw"))
	check_large(directory.path_join("large.trw"))
	await check_worker()
	var report := {"checks":checks,"failures":failures,"scope":"Opt-in metadata-first block loading, atomic scene restore and checkpoint-based partial saves. Automatic paging is not enabled."}
	write_bytes("res://reports/region_metadata.json",JSON.stringify(report,"  ").to_utf8_buffer())
	quit(1 if failures else 0)

func check_restore() -> void:
	var w: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var source: Node3D = ClassDB.instantiate("NativeBlockWorld")
	source.set_cells(PackedInt32Array([-1,0,0,1,64,0,0,2]))
	var packet: PackedByteArray = source.capture_region(Vector3i(-1,0,0))
	source.unload_region(packet)
	var state: Dictionary = source.capture_storage_state()
	w.set_cells(PackedInt32Array([200,0,0,5]))
	check(w.restore_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums),"atomic native restore replaces resident and unavailable maps together")
	check(w.get_cell(Vector3i(200,0,0))==0 and w.get_cell(Vector3i(64,0,0))==2 and not w.is_region_loaded(Vector3i(-1,0,0)),"new storage state replaces previous cells and preserves exact unavailability")
	check(w.capture_snapshot().is_empty() and not w.set_cells(PackedInt32Array([-1,0,0,6])),"metadata-only region cannot be mistaken for editable empty space")
	var before: Dictionary = w.capture_storage_state()
	check(not w.restore_storage_state(state.resident,PackedInt32Array([-1,0]),state.unavailable_checksums),"partial xyz rejects before restore")
	check(not w.restore_storage_state(state.resident,state.unavailable_keys,PackedByteArray()),"partial digest rejects before restore")
	check(not w.restore_storage_state(state.resident,PackedInt32Array([-1,0,0,-1,0,0]),state.unavailable_checksums+state.unavailable_checksums),"duplicate availability keys reject before restore")
	check(not w.restore_storage_state(state.resident,PackedInt32Array([1,0,0]),state.unavailable_checksums),"resident and unavailable overlap rejects before restore")
	check(not w.restore_storage_state(state.resident,PackedInt32Array([16384,0,0]),state.unavailable_checksums),"out-of-range availability key rejects before restore")
	check(not w.restore_storage_state(PackedByteArray([1]),state.unavailable_keys,state.unavailable_checksums),"invalid resident snapshot rejects before restore")
	check(w.capture_storage_state()==before,"failed storage restores preserve both maps exactly")
	check(w.restore_region(packet,PackedByteArray()) and not w.capture_snapshot().is_empty(),"matching region admission resolves metadata unavailability")
	var c := codec()
	var fake := PackedByteArray()
	fake.resize(32)
	var based: PackedByteArray = c.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,{},fake)
	check(c.decode_storage(based).checkpoint==fake and c.validate_storage_snapshot(based),"checkpoint storage envelope round-trips its explicit base identity")
	check(not c.validate_snapshot(based) and not c.decode_reference(based).ok and not c.decode(based).ok,"checkpoint storage envelope is neither a complete scene nor a published reference")
	check(c.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,{},PackedByteArray([1])).is_empty(),"checkpoint storage encoder rejects truncated identity")
	var corrupt := based.duplicate()
	corrupt[18]^=1
	check(not c.decode_storage(corrupt).ok,"checkpoint identity is protected by envelope checksum")
	var scene := Structures.new()
	scene.prepare()
	check(scene.restore_storage_snapshot(based) and scene.capture_storage_snapshot()==based,"scene provider restores and caches validated partial state")
	check(scene.capture_snapshot().is_empty() and not scene.restore_snapshot(based),"legacy scene interface stays guarded after metadata restore")
	scene.blocks.set_cells(PackedInt32Array([128,0,0,3]))
	check(scene.snapshot_validator().decode_storage(scene.capture_storage_snapshot()).checkpoint==fake,"resident edit retains the fallback checkpoint identity")
	check(scene.restore_snapshot(scene.empty_snapshot()) and scene.capture_snapshot()==scene.empty_snapshot(),"ordinary scene restore clears partial cache and unavailable map")
	var empty_blocks: PackedByteArray = scene.blocks.capture_snapshot()
	check(scene.restore_storage_snapshot(c.encode_metadata(fake,PackedInt32Array(),PackedByteArray(),{})) and scene.capture_storage_snapshot()==scene.empty_snapshot(),"empty metadata checkpoint captures as an ordinary complete scene")
	check(scene.blocks.capture_snapshot()==empty_blocks,"empty metadata checkpoint allocates no authored cells")
	scene.free()
	w.free()
	source.free()

func check_recovery(path: String) -> void:
	var c := codec()
	var raw: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var adapter: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	check(adapter.configure(raw,c,true) and adapter.acquire(path),"metadata archive mode is selected before acquiring the world")
	var w: Node3D = ClassDB.instantiate("NativeBlockWorld")
	w.set_cells(PackedInt32Array([-1,0,0,1,64,0,0,2]))
	var original: PackedByteArray = w.capture_snapshot()
	var packet: PackedByteArray = w.capture_region(Vector3i(-1,0,0))
	var sections := {"terrain":PackedByteArray([1]),"structures":c.encode(original,{})}
	check(adapter.publish(path,adapter.encode(sections))==OK,"metadata fixture commits an ordinary initial world")
	var root_a: PackedByteArray = adapter.read(path)
	var base: PackedByteArray = c.decode_reference(raw.decode(root_a).sections.structures).checkpoint
	var guard := FileAccess.open(path,FileAccess.READ)
	w.set_cells(PackedInt32Array([-1,0,0,6,64,0,0,4]))
	sections.structures=c.encode(w.capture_snapshot(),{})
	check(adapter.publish(path,adapter.encode(sections))!=OK and adapter.read(path)==root_a,"failed root replacement leaves canonical checkpoint older than active catalog")
	guard.close()
	var decoded: Dictionary = adapter.decode(root_a)
	var state: Dictionary = c.decode_storage(decoded.sections.structures)
	check(decoded.ok and state.ok and state.checkpoint==base,"metadata load reads the published checkpoint instead of newer active catalog")
	check(w.restore_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums) and w.stats().chunks==0 and w.region_stats().unloaded_regions==2,"checkpoint restore allocates no resident block chunks")
	var digest: PackedByteArray = packet.slice(packet.size()-32)
	check(not adapter.read_storage_region(Vector3i(-1,0,0),digest).ok,"unqualified version read cannot silently return newer active data")
	check(adapter.read_storage_region(Vector3i(-1,0,0),digest,base).bytes==packet,"explicit pinned checkpoint resolves the old exact region version")
	w.set_cells(PackedInt32Array([128,0,0,3]))
	sections.structures=storage_bytes(c,w,PackedByteArray())
	check(adapter.publish(path,adapter.encode(sections))!=OK and adapter.read(path)==root_a,"partial save without fallback identity cannot replace mismatching active versions")
	sections.structures=storage_bytes(c,w,base)
	check(adapter.publish(path,adapter.encode(sections))==OK,"checkpoint-based partial save recovers after active catalog advanced during failed save")
	check(adapter.read_storage_region(Vector3i(-1,0,0),digest,base).bytes==packet,"recovered save retains the exact unloaded region bytes")
	var repeated := true
	for shape in [4,5,6]:
		w.set_cells(PackedInt32Array([128,0,0,shape]))
		sections.structures=storage_bytes(c,w,base)
		repeated=adapter.publish(path,adapter.encode(sections))==OK and repeated
	check(repeated and not FileAccess.file_exists(path+".regions/checkpoints/"+base.hex_encode()+".tfrc"),"subsequent saves remain valid after original fallback pin is retired")
	check(adapter.read_storage_region(Vector3i(-1,0,0),digest,base).bytes==packet,"exact active version remains readable with a retired fallback identity")
	var wrong := digest.duplicate()
	wrong[0]^=1
	check(not adapter.read_storage_region(Vector3i(-1,0,0),wrong,base).ok,"unknown exact version fails rather than returning another region revision")
	check(not adapter.read_storage_region(Vector3i(-1,0,0),PackedByteArray(),base).ok,"version read requires full expected checksum")
	adapter.release()
	var complete: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	complete.configure(ClassDB.instantiate("NativeWorldArchive"),c)
	complete.acquire(path)
	decoded=complete.decode(complete.read(path))
	w.restore_snapshot(c.decode(decoded.sections.structures).blocks)
	check(w.get_cell(Vector3i(-1,0,0))==1 and w.get_cell(Vector3i(64,0,0))==2 and w.get_cell(Vector3i(128,0,0))==6,"complete reopen preserves canonical historical regions together with later resident edits")
	complete.release()
	# Metadata validates the index; lazy region reads must detect damaged blobs.
	var blob := path+".regions/blobs/"+digest.hex_encode()+".tfrg"
	write_bytes(blob,PackedByteArray([1,2,3]))
	check(adapter.acquire(path) and adapter.decode(adapter.read(path)).ok,"metadata loading does not read or allocate distant region payloads")
	check(not adapter.read_storage_region(Vector3i(-1,0,0),digest,base).ok,"lazy exact-version read detects damaged region instead of admitting empty space")
	adapter.release()
	w.free()

func check_large(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path+".regions")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path+".regions")
	var w: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var empty: PackedByteArray = w.capture_snapshot()
	var ok := true
	for region in range(33):
		w.restore_snapshot(empty)
		var records := PackedInt32Array()
		for x in range(4):
			for y in range(4):
				for z in range(4):
					records.append_array(PackedInt32Array([region*64+x*16,y*16,z*16,1]))
		w.set_cells(records)
		ok=store.publish_region(w.capture_region(Vector3i(region,0,0)),PackedByteArray()).ok and ok
	check(ok,"large-world fixture commits 2112 sparse chunks across 33 regions")
	var id: PackedByteArray = store.pin_checkpoint().checkpoint
	check(not store.read_block_checkpoint(id).ok,"legacy full reconstruction still rejects its 2048-chunk bound")
	store.close()
	var c := codec()
	var raw: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	write_bytes(path,raw.encode({"terrain":PackedByteArray([1]),"structures":c.encode_reference(id,{})}))
	var adapter: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	adapter.configure(raw,c,true)
	check(adapter.acquire(path),"metadata adapter opens checkpoint above resident chunk capacity")
	var decoded: Dictionary = adapter.decode(adapter.read(path))
	var state: Dictionary = c.decode_storage(decoded.sections.structures)
	check(decoded.ok and state.unavailable_keys.size()==99 and state.resident==empty,"large checkpoint loads availability without reconstructing cells")
	check(w.restore_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums) and w.stats().chunks==0,"large metadata restore replaces previous authoring with zero resident chunks")
	var packet: Dictionary = adapter.read_storage_region(Vector3i(0,0,0),state.unavailable_checksums.slice(0,32),id)
	check(packet.ok and w.restore_region(packet.bytes,PackedByteArray()) and w.stats().chunks==64 and w.region_stats().unloaded_regions==32,"one region can be admitted without reconstructing remaining 2048 chunks")
	var sections := {"terrain":PackedByteArray([2]),"structures":storage_bytes(c,w,id)}
	check(adapter.publish(path,adapter.encode(sections))==OK,"partially admitted large checkpoint saves without hitting full-world chunk cap")
	adapter.release()
	w.free()

func until(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec()+20000
	while not predicate.call() and Time.get_ticks_msec()<end:
		await process_frame
	return predicate.call()

func check_worker() -> void:
	var slot := "metadata_worker_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var latest := PackedByteArray()
	var original_packet := PackedByteArray()
	for iteration in range(3):
		var terrain := Terrain.new()
		terrain.save_slot=slot
		terrain.diagnostics_pause_streaming=true
		root.add_child(terrain)
		var scene := Structures.new()
		root.add_child(scene)
		scene.prepare()
		var batch: Node3D = scene.register_model("props/metadata/v1",BoxMesh.new())
		var persistence := Persistence.new()
		check(persistence.register_component("structures",scene.capture_storage_snapshot,scene.restore_storage_snapshot,scene.snapshot_validator(),scene.empty_snapshot()) and persistence.enable_region_structures(true) and persistence.attach(terrain)==OK,"metadata-aware scene provider attaches to real terrain worker %d" % iteration)
		check(terrain.start(StandardMaterial3D.new(),false)==OK,"metadata terrain worker starts %d" % iteration)
		var ready := await until(func(): return terrain.world_ready or not terrain.latest_error.is_empty())
		check(ready and terrain.world_ready,"metadata terrain worker loads validated world %d" % iteration)
		if not terrain.world_ready:
			print("METADATA_STARTUP_ERROR ",terrain.latest_error)
			terrain.shutdown()
			scene.free()
			terrain.free()
			return
		if iteration==0:
			scene.blocks.set_cells(PackedInt32Array([-1,0,0,1]))
			batch.upsert_instances(PackedInt64Array([7000000001]),PackedFloat32Array([1,0,0,3,0,1,0,4,0,0,1,5]))
			original_packet=scene.blocks.capture_region(Vector3i(-1,0,0))
		elif iteration==1:
			check(scene.blocks.stats().chunks==0 and scene.blocks.region_stats().unloaded_regions==1,"terrain worker restore leaves building cells unloaded")
			check(batch.stats().instances==1 and not batch.get_instance(7000000001).is_empty(),"metadata load retains static model ID and transform")
			scene.blocks.set_cells(PackedInt32Array([64,0,0,2]))
			var state: Dictionary = scene.snapshot_validator().decode_storage(scene.capture_storage_snapshot())
			check(state.ok and state.checkpoint.size()==32,"worker-bound capture retains explicit original checkpoint")
			latest=scene.capture_storage_snapshot()
		else:
			check(scene.blocks.stats().chunks==0 and scene.blocks.region_stats().unloaded_regions==2,"shutdown saves resident edits with untouched unloaded cells")
			check(scene.blocks.restore_region(original_packet,PackedByteArray()) and scene.blocks.get_cell(Vector3i(-1,0,0))==1,"exact original region admits after metadata reload")
			check(not latest.is_empty() and batch.stats().instances==1,"repeated metadata shutdown/reload preserves model collection")
		terrain.shutdown()
		scene.free()
		terrain.free()
