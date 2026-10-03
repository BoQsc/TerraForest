# SPDX-License-Identifier: 0BSD
extends SceneTree
class Structures extends Node:
	func is_collision_region_ready(_bounds: AABB) -> bool: return true
class World extends Node3D:
	var terrain: Node3D
	var structures:=Structures.new()
var world: World
var session: Node
var persistence: RefCounted
var messages: Array[String]=[]
var slot: String="vehicle_persistence_%d" % OS.get_process_id()
func _initialize() -> void: call_deferred("run")
func create_world() -> bool:
	world=World.new();root.add_child(world);world.add_child(world.structures)
	world.terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	world.terrain.save_slot=slot;world.terrain.diagnostics_pause_streaming=true;world.terrain.backend.disk_cache.enabled=false
	world.add_child(world.terrain)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	session=load("res://addons/vehicle_runtime/world_vehicle.gd").new();world.add_child(session)
	if not session.prepare(world,persistence) or persistence.attach(world.terrain)!=OK:return false
	world.terrain.message_changed.connect(func(message: String):messages.append(message))
	return world.terrain.start(StandardMaterial3D.new(),false)==OK
func ready_world() -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not world.terrain.world_ready and world.terrain.latest_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	return world.terrain.world_ready
func close_world() -> void:
	world.terrain.shutdown();world.free();persistence=null
func run() -> void:
	Engine.max_fps=60
	if not create_world() or not await ready_world():
		print("FAIL initial persistent world startup");close_world();quit(1);return
	var pose:=Transform3D(Basis.from_euler(Vector3(.1,.5,-.1)),Vector3(800,60,1310))
	var expected: PackedByteArray=session.storage.encode(pose)
	var passed: bool=session.restore_snapshot(expected)
	messages.clear();world.terrain.save_world()
	var deadline:=Time.get_ticks_msec()+15000
	while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline: await process_frame
	passed=passed and messages.any(func(m):return m.begins_with("World saved and verified"))
	print("PASS compound vehicle save published" if passed else "FAIL compound vehicle save publication")
	close_world()
	if not create_world() or not await ready_world():
		print("FAIL reopen persistent world");close_world();quit(1);return
	passed=passed and is_instance_valid(session.car) and session.car.transform.is_equal_approx(pose) and session.car.freeze and session.car.linear_velocity==Vector3.ZERO
	print("PASS vehicle restored parked from new world instance" if passed else "FAIL vehicle disk restore")
	close_world()
	var path: String=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	for suffix in ["",".bak",".lock"]: DirAccess.remove_absolute(path+suffix)
	quit(0 if passed else 1)
