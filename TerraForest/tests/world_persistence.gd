extends SceneTree
const Terrain = preload("res://addons/volumetric_terrain/terrain_world.gd")
const Lakes = preload("res://addons/volumetric_water/lake_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
var terrain: Node3D
var lakes: Node3D
var persistence: RefCounted
var checks: Array[Dictionary] = []
var failures: int = 0
var messages: Array[String] = []
var slot: String = "compound_test_%d" % OS.get_process_id()
var center := Vector3(800,50,1310)

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func until(predicate: Callable) -> bool:
	var end: int = Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<end:
		await process_frame
	return predicate.call()
func create_world() -> void:
	terrain = Terrain.new()
	terrain.save_slot = slot
	terrain.diagnostics_pause_streaming = true
	root.add_child(terrain)
	lakes = Lakes.new()
	lakes.terrain = terrain
	lakes.prepare()
	root.add_child(lakes)
	persistence = Persistence.new()
	check(persistence.register_component("volumetric_water",lakes.capture_snapshot,lakes.restore_snapshot,lakes.snapshot_validator(),lakes.empty_snapshot()) and persistence.attach(terrain)==OK,"compound persistence provider attaches before terrain startup")
	terrain.message_changed.connect(func(text: String): messages.append(text))
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"leased persistent world starts")
func close_world() -> void:
	terrain.shutdown()
	lakes.free()
	terrain.free()
	persistence = null
func add_lake() -> int:
	return lakes.add_lake(center-Vector3(16,16,16),Vector3i(32,20,32),1,center.y-3,center-Vector3(0,6,0))
func save() -> bool:
	messages.clear()
	terrain.save_world()
	return await until(func(): return messages.any(func(m): return m.begins_with("World saved and verified")))
func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
func run() -> void:
	Engine.max_fps = 240
	create_world()
	check(await until(func(): return terrain.world_ready),"new compound world ready")
	var height: Array = []
	terrain.height_received.connect(func(_p: Vector3,h: float,_token: int): height.append(h))
	terrain.request_height(center,999)
	check(await until(func(): return not height.is_empty()),"terrain worker returns basin height")
	if height.is_empty():
		close_world()
		quit(1)
		return
	center.y = floorf(height[0])
	var id: int = add_lake()
	check(id>0 and terrain.sculpt_sphere(center,12),"lake definition and terrain excavation accepted")
	check(await until(func(): return not terrain.pending_edit and lakes.statistics()["ready"]==1),"lake bakes before saving")
	check(await save(),"compound terrain and lake snapshot published")
	var path: String = ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	var archive: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var decoded: Dictionary = archive.decode(archive.read(path))
	check(decoded.get("ok",false) and decoded["sections"].has("volumetric_water"),"single canonical file contains terrain and water sections")
	var captured: PackedByteArray = lakes.capture_snapshot()
	lakes.clear()
	terrain.reload_world()
	close_world()
	create_world()
	check(await until(func(): return terrain.world_ready and lakes.statistics()["ready"]==1),"new process-equivalent world instance restores and rebakes lake")
	check(lakes.capture_snapshot()==captured,"shutdown during queued reload does not overwrite restored addon state with stale UI state")
	check(lakes.capture_snapshot()==captured and lakes.depth_at(center-Vector3(0,6,0))>0,"persistent IDs definitions and water occupancy restored")
	check(not terrain.natural_column_available(center),"terrain edit metadata restored with lake state")
	close_world()
	# Preserve future addon payloads even when there is no active provider for them.
	decoded = archive.decode(archive.read(path))
	decoded["sections"]["future_addon"] = PackedByteArray([9,8,7,6])
	check(archive.acquire(path) and archive.publish(path,archive.encode(decoded["sections"]))==OK,"test snapshot includes unknown addon section")
	archive.release()
	create_world()
	check(await until(func(): return terrain.world_ready),"world with unknown addon section opens")
	check(await save(),"world with unknown addon section saves")
	check(archive.decode(archive.read(path))["sections"]["future_addon"]==PackedByteArray([9,8,7,6]),"disabled or unknown addon bytes survive round trip")
	close_world()
	# Legacy terrain files migrate on save; the exact old file is retained as backup.
	var legacy: PackedByteArray = archive.decode(archive.read(path))["sections"]["terrain"]
	write_bytes(path,legacy)
	create_world()
	check(await until(func(): return terrain.world_ready),"legacy raw terrain snapshot imports")
	check(lakes.statistics()["lakes"]==0,"legacy snapshot starts with an empty water catalog")
	check(await save(),"legacy snapshot migrates to compound format")
	check(archive.read(path+".bak")==legacy,"migration preserves exact legacy backup")
	close_world()
	# Valid outer checksum must not bypass an addon's semantic validation.
	decoded = archive.decode(archive.read(path))
	decoded["sections"]["volumetric_water"] = PackedByteArray([1,2,3,4])
	var corrupt: PackedByteArray = archive.encode(decoded["sections"])
	write_bytes(path,corrupt)
	create_world()
	check(await until(func(): return not terrain.latest_error.is_empty()) and not terrain.world_ready,"malformed addon section blocks world startup")
	close_world()
	check(archive.read(path)==corrupt,"shutdown preserves semantically invalid canonical file")
	# Restore a valid empty-lake snapshot, then close immediately after an edit.
	decoded["sections"]["volumetric_water"] = ClassDB.instantiate("NativeLakeCatalog").encode([])
	write_bytes(path,archive.encode(decoded["sections"]))
	create_world()
	check(await until(func(): return terrain.world_ready),"repaired test snapshot starts")
	check(add_lake()>0 and terrain.sculpt_sphere(center+Vector3(3,0,0),13),"edit accepted immediately before shutdown")
	close_world()
	create_world()
	check(await until(func(): return terrain.world_ready and lakes.statistics()["ready"]==1),"shutdown drains accepted edit and stores its lake definition")
	check(not terrain.natural_column_available(center+Vector3(3,0,0)),"shutdown-drained edit survives restart")
	lakes.clear()
	check(await save(),"lake removal publishes an empty catalog with its ID cursor")
	close_world()
	create_world()
	check(await until(func(): return terrain.world_ready),"empty lake catalog reloads")
	check(add_lake()>id,"deleted persistent lake IDs are not reused after restart")
	close_world()
	for suffix in ["",".bak",".lock"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report := FileAccess.open("res://reports/world_persistence.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	report.close()
	quit(0 if failures==0 else 1)
