# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node
var structures: Node
var inventory: RefCounted
var persistence: RefCounted
var history: RefCounted
var collection: Node3D
var saved:=false
var checks:=0
var failures:=0
var slot:="paid_model_disk_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func open_world() -> bool:
	saved=false
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3
	root.add_child(terrain)
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(104,999)
	structures=load("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	if not structures.prepare(): return false
	collection=structures.register_model("tests/paid_beam",BoxMesh.new())
	if collection==null: return false
	history=ClassDB.instantiate("NativeStaticHistory")
	if not history.configure([collection],1048576,256): return false
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	if not persistence.register_component("player_loadout",inventory.capture_storage_snapshot,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()): return false
	if not persistence.register_component("structures",structures.capture_storage_snapshot,structures.restore_storage_snapshot,structures.snapshot_validator(),structures.empty_snapshot()) or not persistence.enable_region_structures(true) or persistence.attach(terrain)!=OK: return false
	structures.changed.connect(func(): terrain.changed_since_save=true)
	terrain.message_changed.connect(func(message: String):
		if message.begins_with("World saved and verified"): saved=true)
	if terrain.start(StandardMaterial3D.new(),false)!=OK: return false
	var deadline:=Time.get_ticks_msec()+60000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	if not terrain.world_ready: print("STARTUP_CONTEXT ",{"worker":terrain.backend.status(),"queued":terrain.backend.queued(),"error":terrain.latest_error})
	return terrain.world_ready
func autosave() -> bool:
	saved=false;terrain.autosave_timer=15.0
	var deadline:=Time.get_ticks_msec()+10000
	while not saved and Time.get_ticks_msec()<deadline: await process_frame
	return saved
func close_world() -> void:
	terrain.backend.disable_snapshot_writes("test teardown must not create the archive under verification")
	terrain.shutdown();terrain.free();structures.free()
	history=null;inventory=null;persistence=null;collection=null
func run() -> void:
	Engine.max_fps=60
	for addon in ["player_runtime","structures","world_runtime"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	var opened: bool=await open_world()
	check(opened,"persistent model and inventory providers initialize")
	if not opened:
		close_world();cleanup();quit(1);return
	var coordinator=load("res://addons/player_runtime/construction_inventory.gd").new();coordinator.gameplay=true
	var pose:=PackedFloat32Array([4,0,0,20,0,0.2,0,100,0,0,0.2,20])
	var identity:=0
	var inventory_bytes:=PackedByteArray()
	var model_bytes:=PackedByteArray()
	if opened:
		inventory.grant(104,8,inventory.snapshot().revision)
		terrain.changed_since_save=false
		identity=coordinator.place_model(history,collection,inventory,pose,AABB(),PackedInt64Array([104,4]))
		check(identity>0 and inventory.snapshot().slots[0].count==4 and terrain.changed_since_save,"paid native placement charges materials and requests autosave")
		inventory_bytes=inventory.capture_storage_snapshot();model_bytes=collection.capture_snapshot()
		check(await autosave(),"paid placement autosaves before teardown")
	close_world()
	opened=await open_world();check(opened,"fresh worker and providers reopen paid placement")
	if not opened:
		close_world();cleanup();quit(1);return
	if opened:
		check(inventory.capture_storage_snapshot()==inventory_bytes,"reloaded inventory preserves exact debit")
		check(collection.capture_snapshot()==model_bytes and collection.get_instance(identity)==pose,"reloaded model preserves exact identity and transform")
		check(history.erase(collection,identity) and inventory.capture_storage_snapshot()==inventory_bytes,"removal gives no inventory refund")
		check(await autosave(),"model removal autosaves before teardown")
	close_world()
	opened=await open_world();check(opened,"second fresh reopen succeeds")
	if opened:
		check(collection.get_instance(identity).is_empty() and inventory.capture_storage_snapshot()==inventory_bytes,"removal remains saved without resurrecting object or materials")
	close_world()
	cleanup()
	print("MODEL_INVENTORY_PERSISTENCE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func cleanup() -> void:
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
