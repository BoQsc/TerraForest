# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node
var pickups: Node
var inventory: RefCounted
var persistence: RefCounted
var checks := 0
var failures := 0
var saves := 0
var slot := "pickup_autosave_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func _initialize() -> void: call_deferred("run")
func wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while not terrain.world_ready and Time.get_ticks_msec() < deadline: await process_frame
	return terrain.world_ready
func wait_save(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while saves < target and Time.get_ticks_msec() < deadline: await process_frame
	return saves >= target
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	inventory=ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(102,999)
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3
	root.add_child(terrain)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	pickups=load("res://addons/world_runtime/material_pickups.gd").new()
	root.add_child(pickups)
	check(pickups.prepare(persistence) and persistence.register_component("player_loadout",inventory.capture_storage_snapshot,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()) and persistence.attach(terrain)==OK,"pickup and inventory providers attach to real disk persistence")
	pickups.changed.connect(func(): terrain.changed_since_save=true)
	terrain.message_changed.connect(func(message: String):
		print("AUTOSAVE_FIXTURE ",message)
		if message.begins_with("World saved and verified"): saves+=1)
	check(terrain.start(StandardMaterial3D.new(),false)==OK and await wait_ready(),"persistent fixture starts")
	if terrain.world_ready:
		var id: int=pickups.spawn(102,Vector3.ZERO)
		# First create a canonical uncollected supply. Only accelerate this setup
		# save; the collection below waits through the actual 15-second interval.
		terrain.autosave_timer=15.0
		check(id>0 and await wait_save(1),"authored supply reaches canonical archive through autosave")
		terrain.autosave_timer=0.0
		var begin:=Time.get_ticks_msec()
		var collected: Dictionary=pickups.collect_near(Vector3.ZERO,inventory,func(_point: Vector3): return true)
		check(collected.ok and terrain.changed_since_save,"collection marks the real autosave path dirty")
		check(await wait_save(2),"collection autosaves without manual save or shutdown")
		check(Time.get_ticks_msec()-begin>=14000,"collection test waits through the production autosave interval")
		# Prevent shutdown or another save from hiding an incorrect disk result.
		terrain.backend.disable_snapshot_writes()
		check(inventory.consume_items(PackedInt64Array([102,1]),inventory.snapshot().revision).ok,"clear live inventory before disk reload")
		pickups.spawn(102,Vector3.ZERO)
		terrain.reload_world()
		check(await wait_ready(),"autosaved compound archive reloads")
		check(inventory.can_afford(PackedInt64Array([102,1]),inventory.snapshot().revision).ok,"disk reload restores collected wood")
		var nearby: Dictionary=pickups.stores[102].query_sphere(Vector3.ZERO,2.5,64,256)
		check(nearby.ok and nearby.complete and nearby.ids.is_empty(),"disk reload preserves pickup removal and discards unsaved replacement")
	terrain.backend.disable_snapshot_writes()
	terrain.shutdown();terrain.free();pickups.free()
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
	print("PICKUP_AUTOSAVE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
