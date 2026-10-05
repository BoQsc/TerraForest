# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node
var pickups: Node
var inventory: RefCounted
var persistence: RefCounted
var checks:=0
var failures:=0
var saved:=false
var item:=102
var slot:="drop_disk_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func open_world() -> bool:
	saved=false
	inventory=ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(item,999)
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3
	root.add_child(terrain)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	pickups=load("res://addons/world_runtime/material_pickups.gd").new()
	root.add_child(pickups)
	if not pickups.prepare(persistence) or not persistence.register_component("player_loadout",inventory.capture_storage_snapshot,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()) or persistence.attach(terrain)!=OK: return false
	pickups.changed.connect(func(): terrain.changed_since_save=true)
	terrain.message_changed.connect(func(message: String):
		if message.begins_with("World saved and verified"): saved=true)
	if terrain.start(StandardMaterial3D.new(),false)!=OK: return false
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	return terrain.world_ready
func autosave() -> bool:
	saved=false
	# Accelerate the timer, not the production capture/worker/archive path.
	terrain.autosave_timer=15.0
	var deadline:=Time.get_ticks_msec()+10000
	while not saved and Time.get_ticks_msec()<deadline: await process_frame
	return saved
func close_world() -> void:
	# Ensure teardown cannot create or repair the disk state under test.
	terrain.backend.disable_snapshot_writes()
	terrain.shutdown();terrain.free();pickups.free()
	inventory=null;persistence=null
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--drop-item="): item=int(argument.get_slice("=",1))
	Engine.max_fps=60
	for addon in ["player_runtime","world_runtime"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	var opened: bool=await open_world()
	check(opened,"fresh disk world starts")
	var expected_inventory:=PackedByteArray()
	var expected_pickup:=PackedByteArray()
	var identity:=0
	var point:=Vector3(800,100,1300)
	if opened:
		inventory.grant(item,5,inventory.snapshot().revision)
		var dropped: Dictionary=pickups.drop_one(inventory,0,inventory.snapshot().revision,point)
		identity=dropped.get("id",0)
		check(dropped.ok and terrain.changed_since_save,"drop marks compound world dirty")
		expected_inventory=inventory.capture_storage_snapshot()
		expected_pickup=pickups.stores[item].capture_storage_snapshot()
		check(await autosave(),"drop reaches verified disk archive before shutdown")
	close_world()
	opened=await open_world()
	check(opened,"fresh worker and providers reopen dropped state")
	if opened:
		check(inventory.capture_storage_snapshot()==expected_inventory and inventory.snapshot().slots[0].count==4,"reopened inventory contains exactly four remaining resources")
		var store: RefCounted=pickups.stores[item]
		check(store.capture_storage_snapshot()==expected_pickup and store.statistics().active==1,"reopened world contains exactly the dropped supply")
		var handle: int=store.resolve_identity(identity)
		check(handle>0 and store.get_position(handle)==point,"disk round trip preserves pickup identity and location")
		var collected: Dictionary=pickups.collect_near(point,inventory,func(_point: Vector3): return true)
		check(collected.ok and inventory.snapshot().slots[0].count==5 and store.statistics().active==0,"recollection after fresh load conserves all five units")
		check(not pickups.collect_near(point,inventory,func(_point: Vector3): return true).ok and inventory.snapshot().slots[0].count==5,"repeated collection cannot duplicate supply")
		expected_inventory=inventory.capture_storage_snapshot()
		check(await autosave(),"recollection reaches verified disk archive before shutdown")
	close_world()
	opened=await open_world()
	check(opened,"second fresh reopen loads recollected state")
	if opened:
		check(inventory.capture_storage_snapshot()==expected_inventory and inventory.snapshot().slots[0].count==5,"second reopen preserves exact recovered inventory")
		check(pickups.stores[item].statistics().active==0 and pickups.stores[item].resolve_identity(identity)==0,"second reopen cannot resurrect collected supply")
	close_world()
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
	print("INVENTORY_DROP_PERSISTENCE item=",item," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
