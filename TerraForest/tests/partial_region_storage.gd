extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func publish(store: RefCounted,state: Dictionary) -> Dictionary:
	return store.publish_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums)
func run() -> void:
	var path := ProjectSettings.globalize_path("res://reports/partial_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	store.open_store(path)
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.set_cells(PackedInt32Array([-1,0,0,1,64,0,0,2]))
	var original: PackedByteArray = world.capture_snapshot()
	var missing: PackedByteArray = world.capture_region(Vector3i(-1,0,0))
	check(store.publish_block_snapshot(original).ok,"initial complete world persists both regions")
	var old: PackedByteArray = store.pin_checkpoint().checkpoint
	check(world.unload_region(missing),"persisted region unloads before partial capture")
	world.set_cells(PackedInt32Array([64,0,0,4,128,0,0,6]))
	var state: Dictionary = world.capture_storage_state()
	check(state.unavailable_keys==PackedInt32Array([-1,0,0]) and state.unavailable_checksums==missing.slice(missing.size()-32),"partial capture carries exact unavailable-region reference")
	check(world.capture_snapshot().is_empty(),"legacy complete capture remains guarded during partial residency")
	check(publish(store,state).ok and store.list_regions()==PackedInt32Array([-1,0,0,1,0,0,2,0,0]),"partial publication combines edited resident regions with saved missing region")
	check(store.read_region(Vector3i(-1,0,0)).bytes==missing,"partial publication preserves exact unavailable packet")
	var pin: PackedByteArray = store.pin_checkpoint().checkpoint
	var reconstructed: Node3D = ClassDB.instantiate("NativeBlockWorld")
	check(reconstructed.restore_snapshot(store.read_block_checkpoint(pin).blocks) and reconstructed.get_cell(Vector3i(-1,0,0))==1 and reconstructed.get_cell(Vector3i(64,0,0))==4 and reconstructed.get_cell(Vector3i(128,0,0))==6,"new checkpoint reconstructs unloaded data together with resident edits")
	check(store.read_block_checkpoint(old).blocks==original,"previous checkpoint remains unchanged")
	check(publish(store,state).unchanged,"identical partial state avoids unnecessary catalog revision")
	var edited := state.duplicate(true)
	edited.resident[0]^=1
	check(not publish(store,edited).ok and world.capture_storage_state().resident==state.resident,"invalid resident data rejects without mutating captured world values")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))
	check(not store.publish_storage_state(state.resident,PackedInt32Array([-1,0]),state.unavailable_checksums).ok,"incomplete unavailable xyz rejected")
	check(not store.publish_storage_state(state.resident,state.unavailable_keys,PackedByteArray()).ok,"incomplete unavailable digest rejected")
	check(not store.publish_storage_state(state.resident,PackedInt32Array([-1,0,0,-1,0,0]),state.unavailable_checksums+state.unavailable_checksums).ok,"duplicate unavailable keys rejected")
	check(not store.publish_storage_state(state.resident,PackedInt32Array([16384,0,0]),state.unavailable_checksums).ok,"out-of-range unavailable region rejected")
	check(not store.publish_storage_state(state.resident,PackedInt32Array([1,0,0]),store.checksum(Vector3i(1,0,0))).ok,"resident and unavailable region overlap rejected")
	check(not store.publish_storage_state(state.resident,PackedInt32Array([-2,0,0]),state.unavailable_checksums).ok,"uncataloged unavailable region cannot be invented")
	var wrong: PackedByteArray = state.unavailable_checksums.duplicate()
	wrong[0]^=1
	check(not store.publish_storage_state(state.resident,state.unavailable_keys,wrong).ok,"stale unavailable digest cannot preserve a different catalog version")
	check(FileAccess.get_file_as_bytes(path.path_join("catalog.tfrc"))==before,"rejected partial states leave committed catalog byte-identical")
	# Erasing all resident cells must remove their old regions while retaining
	# the unloaded one. Otherwise demolition would reappear on the next load.
	world.set_cells(PackedInt32Array([64,0,0,0,128,0,0,0]))
	check(publish(store,world.capture_storage_state()).ok and store.list_regions()==PackedInt32Array([-1,0,0]),"resident demolition removes absent resident regions but preserves missing data")
	var absent: PackedByteArray = world.capture_region(Vector3i(2,0,0))
	world.unload_region(absent)
	check(not publish(store,world.capture_storage_state()).ok,"unpersisted empty-region unload cannot be saved as a valid catalog reference")
	world.restore_region(absent,PackedByteArray())
	store.close()
	check(store.open_store(path).ok and store.read_region(Vector3i(-1,0,0)).bytes==missing,"partial save preserves unloaded region across disk reopen")
	check(world.restore_region(store.read_region(Vector3i(-1,0,0)).bytes,PackedByteArray()) and not world.capture_snapshot().is_empty(),"unavailable region can still be admitted after partial save")
	check(publish(store,world.capture_storage_state()).ok,"fully resident storage-state capture remains compatible")
	store.close()
	check(not publish(store,state).ok,"closed store rejects partial publication")
	world.free()
	reconstructed.free()
	var file := FileAccess.open("res://reports/partial_region_storage.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Native partial-state capture and catalog publication; world-root encoding and automatic paging integration remain pending."},"  "))
	file.close()
	quit(1 if failures else 0)
