extends SceneTree
const Terrain = preload("res://addons/volumetric_terrain/terrain_world.gd")
const Structures = preload("res://addons/structures/structures_world.gd")
const Lakes = preload("res://addons/volumetric_water/lake_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
var terrain: Node3D
var structures: Node3D
var lakes: Node3D
var persistence: RefCounted
var checks: Array[Dictionary] = []
var failures := 0
var messages: Array[String] = []
var slot := "structure_save_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
var asset_ids := PackedStringArray(["architecture/fence/v1","props/crate/v1"])
var region_storage := OS.get_cmdline_user_args().has("--region-storage")

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, description: String) -> void:
	checks.append({"name":description,"pass":value})
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ")+description)

func until(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec()+20000
	while not predicate.call() and Time.get_ticks_msec()<end:
		await process_frame
	return predicate.call()

func create_world() -> void:
	terrain = Terrain.new()
	terrain.save_slot = slot
	terrain.diagnostics_pause_streaming = true
	root.add_child(terrain)
	structures = Structures.new()
	root.add_child(structures)
	structures.prepare()
	for id in asset_ids:
		structures.register_model(id,BoxMesh.new())
	lakes = Lakes.new()
	lakes.terrain = terrain
	lakes.prepare()
	root.add_child(lakes)
	persistence = Persistence.new()
	check(persistence.register_component("structures",structures.capture_storage_snapshot if region_storage else structures.capture_snapshot,structures.restore_snapshot,structures.snapshot_validator(),structures.empty_snapshot()),"structures bundle registers as one world component")
	if region_storage:
		check(persistence.enable_region_structures(),"native region archive enabled before terrain starts")
	check(persistence.register_component("volumetric_water",lakes.capture_snapshot,lakes.restore_snapshot,lakes.snapshot_validator(),lakes.empty_snapshot()) and persistence.attach(terrain)==OK,"water and structures share the terrain persistence coordinator")
	terrain.message_changed.connect(func(text: String):
		messages.append(text)
		if region_storage: print("REGION_PERSISTENCE: ",text))
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"persistent structure world starts")

func close_world() -> void:
	terrain.shutdown()
	structures.free()
	lakes.free()
	terrain.free()
	persistence = null

func save() -> bool:
	messages.clear()
	terrain.save_world()
	return await until(func(): return messages.any(func(m): return m.begins_with("World saved and verified")))

func transform_at(x: float) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,x,0,1,0,64,0,0,1,1310])

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func run() -> void:
	Engine.max_fps=240
	create_world()
	var ready := await until(func(): return terrain.world_ready or not terrain.latest_error.is_empty())
	check(ready and terrain.world_ready,"new terrain/water/structure world becomes ready")
	if not terrain.world_ready:
		print("STARTUP_DIAGNOSTICS ",JSON.stringify({"messages":messages,"error":terrain.latest_error,"worker":terrain.backend.status(),"queued":terrain.backend.queued(),"slot":slot}))
		close_world()
		finish_report()
		return
	check(structures.blocks.stats().cells==0,"absent structures section restores an empty block world")
	check(structures.register_model("late/asset",BoxMesh.new())==null,"registered persistence schema rejects late asset mutation")
	check(not structures.model(asset_ids[0]).configure_asset("wrong/key",BoxMesh.new()),"empty registered collection keeps its asset identity locked")
	check(not structures.snapshot_validator().configure_assets(asset_ids),"worker validator schema is immutable after registration")
	check(structures.blocks.set_cells(PackedInt32Array([800,64,1310,1,801,64,1310,43])),"native building edits accepted independently of terrain")
	check(structures.model(asset_ids[0]).upsert_instances(PackedInt64Array([7000000001]),transform_at(804)),"fence placement retains a 64-bit ID")
	check(structures.model(asset_ids[1]).upsert_instances(PackedInt64Array([12]),transform_at(810)),"second mesh collection accepts placement")
	check(terrain.sculpt_sphere(Vector3(800,50,1310),3),"terrain edit accepted alongside buildings")
	check(await until(func(): return not terrain.pending_edit),"terrain edit completes")
	var saved: PackedByteArray = structures.capture_snapshot()
	check(structures.capture_snapshot()==saved,"unchanged bundle capture reuses the same logical snapshot")
	# Exercise the worker-owned capture ordering state without starting a worker.
	var coordinator: RefCounted = load("res://addons/volumetric_terrain/terrain_backend.gd").new()
	coordinator.snapshot_validators={"structures":structures.snapshot_validator()}
	coordinator.components={"structures":saved}
	coordinator._apply_components({"epoch":0,"generation":2,"sections":{"structures":PackedByteArray()}})
	coordinator._apply_components({"epoch":0,"generation":1,"sections":{"structures":structures.empty_snapshot()}})
	check(not coordinator._component_capture_valid and coordinator.components.structures==saved,"older capture cannot overtake a newer rejected capture")
	coordinator._apply_components({"epoch":0,"generation":3,"sections":{"structures":structures.empty_snapshot()}})
	check(coordinator._component_capture_valid and coordinator.components.structures==structures.empty_snapshot(),"newer valid capture recovers worker-owned component state")
	coordinator=null
	var exposed: PackedByteArray = structures.capture_snapshot()
	exposed[0]^=1
	check(structures.snapshot_validator().validate_snapshot(structures.capture_snapshot()),"caller mutation of returned bytes cannot corrupt the component cache")
	check(await save(),"compound save publishes terrain water blocks and static models")
	var path := ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	var archive: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var decoded: Dictionary = terrain.backend.snapshot_codec.decode(archive.read(path))
	check(decoded.ok and decoded.sections.size()==3 and decoded.sections.structures==saved,"one canonical file contains all providers, with models inside the structures section")
	if region_storage:
		var disk_root: Dictionary = archive.decode(archive.read(path))
		check(structures.snapshot_validator().decode_reference(disk_root.sections.structures).ok and DirAccess.dir_exists_absolute(path+".regions"),"integrated terrain save publishes checkpoint reference and region sidecar")
	if region_storage:
		var packet: PackedByteArray = structures.blocks.capture_region(Vector3i(12,1,20))
		check(structures.blocks.unload_region(packet),"saved building region unloads while the terrain worker stays live")
		check(structures.blocks.set_cells(PackedInt32Array([864,64,1310,6])),"resident region edits coexist with unloaded buildings")
		var partial: PackedByteArray = structures.capture_storage_snapshot()
		check(not partial.is_empty() and terrain.backend.snapshot_codec.validate_snapshot(partial),"region provider validates native partial storage envelope")
		check(structures.capture_snapshot().is_empty() and not structures.snapshot_validator().validate_snapshot(partial),"legacy whole-world capture and validator never accept partial data")
		var exposed_partial := partial.duplicate()
		exposed_partial[0]^=1
		check(structures.capture_storage_snapshot()==partial and not structures.restore_snapshot(partial),"partial cache is isolated and cannot be restored as a complete scene")
		structures.model(asset_ids[1]).upsert_instances(PackedInt64Array([12]),transform_at(812))
		check(structures.capture_storage_snapshot()!=partial,"model edits invalidate the partial storage cache")
		check(await save(),"terrain worker commits resident edits alongside unloaded region references")
		decoded=terrain.backend.snapshot_codec.decode(archive.read(path))
		saved=decoded.sections.structures
		check(structures.blocks.restore_region(packet,PackedByteArray()) and structures.capture_snapshot()==saved,"reconstructed world exactly matches edited resident and preserved unloaded cells")
		check(structures.capture_storage_snapshot()==saved,"admitting the region invalidates partial cache and returns ordinary bundle")
	var disk_before: PackedByteArray = archive.read(path)
	var real_capture: Callable = terrain.backend.snapshot_capture
	terrain.backend.snapshot_capture = func():
		var state: Dictionary = real_capture.call()
		state.sections.structures=PackedByteArray()
		return state
	messages.clear()
	terrain.save_world()
	check(await until(func(): return messages.any(func(m): return m.begins_with("ERROR: invalid addon capture"))),"invalid live component capture refuses publication")
	check(archive.read(path)==disk_before,"invalid live capture leaves the canonical file unchanged")
	terrain.backend.snapshot_capture=real_capture
	check(await save(),"a subsequent valid capture recovers saving without reopening the world")
	var bundle: Dictionary = structures.snapshot_validator().decode(saved)
	check(bundle.ok and bundle.models.size()==2,"native bundle stores both registered mesh assets")
	structures.blocks.set_cells(PackedInt32Array([800,64,1310,0]))
	structures.model(asset_ids[0]).remove_instances(PackedInt64Array([7000000001]))
	check(structures.capture_snapshot()!=saved,"native changes invalidate cached component bytes")
	var invalid := saved.duplicate()
	invalid[30]^=1
	var unchanged: PackedByteArray = structures.capture_snapshot()
	check(not structures.restore_snapshot(invalid) and structures.capture_snapshot()==unchanged,"invalid bundle restore cannot partially change block/model state")
	terrain.reload_world()
	close_world()
	create_world()
	check(await until(func(): return terrain.world_ready),"restart after shutdown during reload becomes ready")
	check(structures.capture_snapshot()==saved,"queued reload wins over stale shutdown capture for every structure collection")
	check(structures.model(asset_ids[0]).get_instance(7000000001)==transform_at(804),"static placement ID and transform survive world restart")
	check(not terrain.natural_column_available(Vector3(800,50,1310)),"terrain edit metadata survives with the structure snapshot")
	structures.blocks.set_cells(PackedInt32Array([-1,3,-1,100]))
	structures.model(asset_ids[1]).upsert_instances(PackedInt64Array([12]),transform_at(830))
	var latest: PackedByteArray = structures.capture_snapshot()
	if region_storage:
		check(structures.blocks.unload_region(structures.blocks.capture_region(Vector3i(12,1,20))),"shutdown fixture retains an unloaded persisted region")
	close_world()
	create_world()
	check(await until(func(): return terrain.world_ready),"structure-only edit shutdown reloads")
	check(structures.capture_snapshot()==latest,"shutdown persists building/model changes without a terrain edit or explicit save")
	close_world()
	# Added catalog entries default empty, while old asset records retain identity.
	asset_ids.append("props/lamp/v1")
	create_world()
	check(await until(func(): return terrain.world_ready),"extended asset registry loads an older structures bundle")
	check(structures.model("props/lamp/v1").stats().instances==0 and structures.model("props/crate/v1").get_instance(12)==transform_at(830),"new asset starts empty without changing existing placement IDs")
	check(structures.model("props/lamp/v1").upsert_instances(PackedInt64Array([2]),transform_at(840)),"new asset placement accepted")
	check(await save(),"extended catalog publishes all asset records")
	close_world()
	var canonical: PackedByteArray = archive.read(path)
	# The validator must reject unknown saved assets before native terrain restore.
	asset_ids = PackedStringArray(["architecture/fence/v1"])
	create_world()
	check(await until(func(): return not terrain.latest_error.is_empty()) and not terrain.world_ready,"unresolved saved model asset blocks startup")
	check(structures.blocks.stats().cells==0,"unresolved asset cannot partially restore block data")
	close_world()
	check(archive.read(path)==canonical,"failed asset resolution cannot overwrite canonical save during shutdown")
	asset_ids = PackedStringArray(["architecture/fence/v1","props/crate/v1","props/lamp/v1"])
	create_world()
	check(await until(func(): return terrain.world_ready),"restoring the complete asset registry reopens the world")
	var before_reload: PackedByteArray = structures.capture_snapshot()
	decoded=archive.decode(canonical)
	decoded.sections.structures=PackedByteArray([1,2,3])
	var malformed: PackedByteArray = archive.encode(decoded.sections)
	write_bytes(path,malformed)
	terrain.reload_world()
	check(await until(func(): return not terrain.latest_error.is_empty()),"valid outer archive cannot bypass malformed structures validation")
	check(structures.capture_snapshot()==before_reload,"failed hot reload preserves existing block and object state")
	close_world()
	check(archive.read(path)==malformed,"failed hot reload protects invalid canonical bytes from automatic overwrite")
	# Check a payload larger than the previous 16 MiB component ceiling and the new bound.
	var large := PackedByteArray()
	large.resize(17*1024*1024)
	var packed: PackedByteArray = archive.encode({"terrain":PackedByteArray([1]),"structures":large})
	check(not packed.is_empty() and archive.decode(packed).ok,"bounded archive accepts structure sections above the old 16 MiB ceiling")
	packed=PackedByteArray()
	large.resize(64*1024*1024+1)
	check(archive.encode({"terrain":PackedByteArray([1]),"structures":large}).is_empty(),"non-terrain sections remain bounded at 64 MiB")
	large=PackedByteArray()
	for suffix in ["",".bak",".lock"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	DirAccess.make_dir_recursive_absolute("res://reports")
	finish_report()

func finish_report() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/structure_region_persistence.json" if region_storage else "res://reports/structure_persistence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	print("STRUCTURE_PERSISTENCE_RESULT ",checks.size()," checks; ",failures," failures")
	quit(1 if failures else 0)
