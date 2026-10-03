# SPDX-License-Identifier: 0BSD
extends SceneTree
const Terrain=preload("res://addons/volumetric_terrain/terrain_world.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
const Pickups=preload("res://addons/world_runtime/material_pickups.gd")
const HUD=preload("res://addons/player_runtime/player_hud.gd")
var terrain: Node
var pickups: Node3D
var hud: Node
var persistence: RefCounted
var failures:=0
var slot:="pickup_disk_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
var saved:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func until(predicate: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()
func start() -> void:
	terrain=Terrain.new();terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.world_generator=2;terrain.backend.world_seed=2468;root.add_child(terrain)
	pickups=Pickups.new();root.add_child(pickups)
	hud=HUD.new();hud.prepare()
	persistence=Persistence.new()
	check(pickups.prepare(persistence) and persistence.register_component("player_loadout",hud.capture_snapshot,hud.restore_snapshot,hud.inventory,hud.default_loadout) and persistence.attach(terrain)==OK,"pickup and inventory providers attach to disk archive")
	terrain.message_changed.connect(func(value: String):
		if value.begins_with("World saved and verified"): saved=true)
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"persistent world starts")
func close() -> void:
	terrain.shutdown();terrain.free();pickups.free();hud.free();persistence=null
func save() -> bool:
	saved=false;terrain.save_world()
	return await until(func(): return saved)
func run() -> void:
	Engine.max_fps=60
	start()
	check(await until(func(): return terrain.world_ready),"fresh world ready")
	var brick: int=pickups.spawn(101,Vector3(800,60,1300))
	var wood: int=pickups.spawn(102,Vector3(805,60,1300))
	check(brick>0 and wood>0,"two persistent supplies authored")
	check(await save(),"worker verifies first pickup save")
	close();start()
	check(await until(func(): return terrain.world_ready),"fresh instances reopen authored world")
	check(pickups.stores[101].get_position(pickups.stores[101].resolve_identity(brick))==Vector3(800,60,1300) and pickups.stores[102].resolve_identity(wood)>0,"supply identities and positions survive file reload")
	var result: Dictionary=pickups.collect_near(Vector3(800,60,1300),hud.inventory,func(_p: Vector3): return true)
	check(result.ok,"loaded supply transfers into inventory")
	var inventory_bytes: PackedByteArray=hud.capture_snapshot()
	check(await save(),"worker verifies collected state save")
	close();start()
	check(await until(func(): return terrain.world_ready),"collected world reopens")
	check(pickups.stores[101].resolve_identity(brick)==0 and pickups.stores[102].resolve_identity(wood)>0 and hud.capture_snapshot()==inventory_bytes,"file reload retains inventory and cannot respawn collected supply")
	close()
	var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	var archive: RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var decoded: Dictionary=archive.decode(archive.read(path))
	check(decoded.ok and decoded.sections.has("pickups_104"),"disk archive includes all four supply sections")
	decoded.sections.pickups_102=PackedByteArray([1,2,3])
	check(archive.acquire(path) and archive.publish(path,archive.encode(decoded.sections))==OK,"isolated corrupt-section fixture has valid outer checksum")
	archive.release();start()
	check(await until(func(): return not terrain.latest_error.is_empty()) and not terrain.world_ready,"worker rejects malformed supply section before world readiness")
	close()
	for suffix: String in ["",".bak",".lock"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/material_pickup_persistence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"scope":"real terrain worker compound disk save and fresh-instance reload, paused mesh streaming"}));file.close()
	quit(1 if failures else 0)
