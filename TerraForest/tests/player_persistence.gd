# SPDX-License-Identifier: 0BSD
extends SceneTree
const Terrain=preload("res://addons/volumetric_terrain/terrain_world.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
const HUD=preload("res://addons/player_runtime/player_hud.gd")
var terrain: Node
var hud: Node
var persistence: RefCounted
var failures:=0
var slot:="player_test_%d"%OS.get_process_id()
var messages: Array[String]=[]
var pose_codec: RefCounted
var pose_data:=PackedByteArray()
func capture_pose() -> PackedByteArray: return pose_data
func restore_pose(data: PackedByteArray) -> bool:
	if not pose_codec.validate_snapshot(data): return false
	pose_data=data
	return true
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func until(predicate: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()
func start() -> void:
	terrain=Terrain.new();terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.world_generator=2;terrain.backend.world_seed=2468
	root.add_child(terrain)
	hud=HUD.new();check(hud.prepare(),"native player provider ready")
	persistence=Persistence.new()
	pose_codec=ClassDB.instantiate("NativePlayerPose")
	pose_data=PackedByteArray()
	check(persistence.register_component("player_pose",capture_pose,restore_pose,pose_codec,PackedByteArray()),"native pose validator registered with archive")
	check(persistence.register_component("player_loadout",hud.capture_snapshot,hud.restore_snapshot,hud.inventory,hud.default_loadout) and persistence.attach(terrain)==OK,"player provider attaches to terrain worker archive")
	terrain.message_changed.connect(func(value: String): messages.append(value))
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"persistent terrain starts")
func close() -> void:
	terrain.shutdown();terrain.free();hud.free();persistence=null
func run() -> void:
	Engine.max_fps=60
	start()
	check(await until(func(): return terrain.world_ready),"fresh world ready")
	check(terrain.backend.world_generator==2 and terrain.backend.world_seed==2468,"new world uses requested generator profile and seed")
	check(hud.inventory.transfer(0,5,1,hud.inventory.snapshot().revision).ok,"starter tool moved")
	var saved: PackedByteArray=hud.capture_snapshot()
	pose_data=pose_codec.encode(Vector3(800,50,1200),0.4,-0.2,false,3)
	var saved_pose:=pose_data.duplicate()
	messages.clear();terrain.save_world()
	check(await until(func(): return messages.any(func(m): return m.begins_with("World saved and verified"))),"worker publishes verified compound save")
	close();start()
	check(await until(func(): return terrain.world_ready),"saved world reopens")
	check(terrain.backend.world_generator==2 and terrain.backend.world_seed==2468,"saved world retains generator profile and seed")
	check(hud.capture_snapshot()==saved,"new player instance restores exact loadout from world file")
	check(pose_data==saved_pose,"new player instance restores pose bytes from world file")
	close()
	var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	var archive: RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var decoded: Dictionary=archive.decode(archive.read(path))
	decoded.sections.erase("player_loadout")
	check(archive.acquire(path) and archive.publish(path,archive.encode(decoded.sections))==OK,"legacy fixture has no player section")
	archive.release();start()
	check(await until(func(): return terrain.world_ready),"world without player section opens")
	check(hud.capture_snapshot()==hud.default_loadout,"missing player section receives starter loadout")
	close()
	decoded=archive.decode(archive.read(path));decoded.sections.player_loadout=PackedByteArray([1,2,3])
	check(archive.acquire(path) and archive.publish(path,archive.encode(decoded.sections))==OK,"malformed player fixture published with valid outer checksum")
	archive.release();start()
	check(await until(func(): return not terrain.latest_error.is_empty()) and not terrain.world_ready,"worker rejects malformed player section before world ready")
	close()
	for suffix in ["",".bak",".lock"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	quit(1 if failures else 0)
