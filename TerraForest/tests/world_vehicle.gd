# SPDX-License-Identifier: 0BSD
extends SceneTree
class ReadyProvider extends Node:
	var available:=true
	var focus:=Vector3.ZERO
	var travel_velocity:=Vector3.ZERO
	func is_collision_region_ready(_bounds: AABB) -> bool: return available
class Fixture extends Node3D:
	var terrain:=ReadyProvider.new()
	var structures:=ReadyProvider.new()
	var player:=CharacterBody3D.new()
	var camera:=Camera3D.new()
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(load("res://demo/world.gd")!=null,"main-world script parses with vehicle integration")
	var world:=Fixture.new();root.add_child(world)
	world.add_child(world.terrain);world.add_child(world.structures);world.add_child(world.player);world.player.add_child(world.camera)
	world.camera.position=Vector3(0,1.6,0);world.camera.look_at(Vector3(0,0,-6))
	var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(40,.2,40)
	collision.shape=box;floor.position.y=-.1;floor.add_child(collision);world.add_child(floor)
	var session=load("res://addons/vehicle_runtime/world_vehicle.gd").new();world.add_child(session)
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(session.prepare(world,persistence),"vehicle component registers with world persistence")
	await physics_frame;await physics_frame
	world.terrain.available=false
	check(session.spawn(world)=="Vehicle area is still loading" and session.car==null,"spawn rejects unavailable ground")
	world.terrain.available=true
	var result: String=session.spawn(world)
	check(is_instance_valid(session.car) and result.begins_with("Vehicle placed"),"spawn on clear loaded ground")
	if not is_instance_valid(session.car): world.free();quit(1);return
	check(not session.enter(world),"entry rejected outside interaction range")
	world.player.position=session.car.position+Vector3.RIGHT*2.8
	var original_camera: Transform3D=world.camera.transform
	var old_ticks:=Engine.physics_ticks_per_second
	check(session.enter(world) and session.driving and world.player.collision_mask==0,"entry transfers control and disables occupant collision")
	session.car.set_physics_process(false)
	session.car.linear_velocity=Vector3(0,0,10)
	check(session.exit_vehicle(world)=="Stop the vehicle before exiting" and session.driving,"moving exit rejected")
	session.car.linear_velocity=Vector3.ZERO;world.structures.available=false
	check(session.exit_vehicle(world)=="No clear, loaded exit beside the vehicle" and session.driving,"exit rejects unloaded building collision")
	world.structures.available=true
	check(session.exit_vehicle(world).begins_with("On foot") and not session.driving,"clear loaded exit restores walking")
	check(world.camera.transform==original_camera and Engine.physics_ticks_per_second==old_ticks and world.player.collision_mask==1,"camera physics rate and collision restored")
	session.car.position=Vector3(400,50,400);session.car.rotation=Vector3(.1,.3,.2)
	var saved: PackedByteArray=session.capture_snapshot()
	var pose: Transform3D=session.car.transform
	check(persistence._capture().sections.vehicles==saved,"world capture includes vehicle")
	check(session.restore_snapshot(saved) and session.car.transform.is_equal_approx(pose) and session.car.freeze and not session.car.is_physics_processing(),"restore recreates parked vehicle pose")
	var id: int=session.car.get_instance_id()
	check(not session.restore_snapshot(PackedByteArray([0])) and session.car.get_instance_id()==id,"invalid restore leaves live vehicle untouched")
	session.car.position.x=-1
	check(not session.storage.validate_snapshot(session.capture_snapshot()),"invalid live pose rejects save instead of removing vehicle")
	check(session.restore_snapshot(PackedByteArray()) and session.car==null,"absent section removes old vehicle")
	world.free();quit(0 if failures==0 else 1)
