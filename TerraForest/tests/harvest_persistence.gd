# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node
var vegetation: Node
var ecosystem: Node
var inventory: RefCounted
var persistence: RefCounted
var checks:=0
var failures:=0
var saved:=false
var slot:="harvest_disk_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func open_world() -> bool:
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(102,999)
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3
	root.add_child(terrain)
	vegetation=load("res://addons/vegetation/vegetation_world.gd").new()
	root.add_child(vegetation);vegetation.ready_to_render=true
	if not vegetation.enable_trunk_collision(): return false
	ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	ecosystem.vegetation=vegetation
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	if not ecosystem.prepare_persistence(persistence) or not persistence.register_component("player_loadout",inventory.capture_storage_snapshot,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()) or persistence.attach(terrain)!=OK: return false
	ecosystem.harvested.connect(func(): terrain.changed_since_save=true)
	terrain.message_changed.connect(func(message: String):
		if message.begins_with("World saved and verified"): saved=true)
	if terrain.start(StandardMaterial3D.new(),false)!=OK: return false
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	return terrain.world_ready
func publish_trees() -> void:
	var poses: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(0,100,0)),Transform3D(Basis.IDENTITY,Vector3(10,100,0))]
	ecosystem._replace_samples(Vector2i.ZERO,PackedInt64Array([1,2]),poses)
	vegetation.trunk_collision.set_collision_focus(Vector3(0,100,0))
func close_world() -> void:
	# Teardown must never create the save that the test claims to verify.
	terrain.backend.disable_snapshot_writes()
	terrain.shutdown();terrain.free();ecosystem.free();vegetation.free()
	inventory=null;persistence=null
func run() -> void:
	Engine.max_fps=60
	for addon in ["player_runtime","world_runtime","structures","vegetation_runtime"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	var opened: bool=await open_world()
	check(opened,"new disk world starts with registered harvest and inventory providers")
	var expected_inventory:=PackedByteArray()
	var expected_harvest:=PackedByteArray()
	if opened:
		publish_trees()
		check(ecosystem.harvest_root(1,inventory).ok,"live harvest removes tree and grants wood")
		expected_inventory=inventory.capture_storage_snapshot()
		expected_harvest=ecosystem.harvest_state.capture_storage_snapshot()
		# Accelerate only the clock; use the production autosave admission/worker.
		terrain.autosave_timer=15.0
		var deadline:=Time.get_ticks_msec()+10000
		while not saved and Time.get_ticks_msec()<deadline: await process_frame
		check(saved,"harvest autosave publishes a verified archive before shutdown")
	close_world()
	opened=await open_world()
	check(opened,"fresh worker and fresh providers reopen the saved world")
	if opened:
		check(inventory.capture_storage_snapshot()==expected_inventory and inventory.can_afford(PackedInt64Array([102,4]),inventory.snapshot().revision).ok,"fresh inventory restores exactly the harvested wood")
		check(ecosystem.harvest_state.capture_storage_snapshot()==expected_harvest and ecosystem.harvest_state.contains(1),"fresh harvest store restores exact disk exclusions")
		publish_trees()
		for tick in range(4): await physics_frame
		check(not vegetation.renderer.roots.has(1) and vegetation.renderer.roots.has(2),"regenerated owner keeps harvested tree absent and neighbour present")
		check(vegetation.trunk_collision.get_ids()==PackedInt64Array([2]),"regeneration does not recreate harvested trunk collision")
		var hit:=root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,101,-2),Vector3(0,101,2),2))
		check(hit.is_empty(),"physics ray passes through the harvested trunk location")
		check(not ecosystem.harvest_root(1,inventory).ok and inventory.capture_storage_snapshot()==expected_inventory,"reload cannot award the same tree twice")
		ecosystem.reset();publish_trees()
		check(not vegetation.renderer.roots.has(1) and vegetation.renderer.roots.has(2),"second region unload and regeneration preserves disk harvest")
	close_world()
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
	print("HARVEST_PERSISTENCE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
