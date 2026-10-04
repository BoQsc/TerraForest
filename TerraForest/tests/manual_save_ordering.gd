# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var terrain: Node
var inventory: RefCounted
var persistence: RefCounted
var checks:=0
var failures:=0
var captures:=0
var saved:=false
var granted:=false
var slot:="manual_save_order_%d"%OS.get_process_id()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func capture() -> Dictionary:
	captures+=1
	return persistence._capture()
func wait_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	return terrain.world_ready
func published(_bounds: AABB,_revision: int) -> void:
	if not granted:
		granted=inventory.grant(101,7,inventory.snapshot().revision).ok
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999)
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true;terrain.backend.disk_cache.enabled=false
	terrain.backend.world_generator=3;root.add_child(terrain)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(persistence.register_component("player_loadout",inventory.capture_storage_snapshot,inventory.restore_storage_snapshot,inventory,inventory.capture_storage_snapshot()) and persistence.attach(terrain)==OK,"real compound persistence attaches")
	terrain.backend.snapshot_capture=capture
	terrain.region_changed.connect(published)
	terrain.message_changed.connect(func(message: String):
		if message.begins_with("World saved and verified"): saved=true)
	check(terrain.start(StandardMaterial3D.new(),false)==OK and await wait_ready(),"isolated persistent world starts")
	if terrain.world_ready:
		var center:=Vector3(800,30,1310)
		check(terrain.edit(Codec.brush(center,center,2,0,false,3),center-Vector3.ONE*8,center+Vector3.ONE*8),"native excavation admitted")
		var before:=captures
		terrain.save_world();terrain.save_world()
		check(terrain.pending_edit and captures==before,"manual saves do not capture inventory during pending edit")
		var deadline:=Time.get_ticks_msec()+15000
		while not saved and Time.get_ticks_msec()<deadline: await process_frame
		check(saved and granted and captures==before+1,"repeated requests coalesce and capture after publication callback")
		var revision: int=terrain.density_revision
		check(inventory.consume_items(PackedInt64Array([101,7]),inventory.snapshot().revision).ok,"clear runtime inventory to distinguish actual disk restoration")
		terrain.reload_world()
		check(await wait_ready(),"compound save reload completes")
		check(inventory.snapshot().slots[0].count==7 and terrain.density_revision==revision,"disk save contains published terrain and post-publication inventory together")
	terrain.shutdown();terrain.free()
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
	print("MANUAL_SAVE_ORDERING ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
