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
	var resource_deadline:=Time.get_ticks_msec()+15000
	var loading_preserved:=true
	while not session.scene_ready() and Time.get_ticks_msec()<resource_deadline:
		# A request is preview-free until its resource is ready. Do not assume
		# two physics frames are enough to load the imported vehicle asset.
		loading_preserved=loading_preserved and session.car==null and session.capture_snapshot().is_empty()
		await process_frame
	check(session.scene_ready() and loading_preserved,"vehicle resource becomes ready without creating a live vehicle")
	if not session.scene_ready(): world.free();quit(1);return
	await physics_frame;await physics_frame
	world.terrain.available=false
	check(session.spawn(world)=="Vehicle area is still loading" and session.car==null,"spawn rejects unavailable ground")
	world.terrain.available=true
	session.interaction_available=func(): return false
	check(session.spawn(world)=="Vehicle interaction unavailable" and session.car==null,"live admission rejects vehicle creation")
	session.interaction_available=func(): return true
	var result: String=session.spawn(world)
	check(is_instance_valid(session.car) and result.begins_with("Vehicle placed"),"spawn on clear loaded ground")
	if not is_instance_valid(session.car): world.free();quit(1);return
	check(not session.enter(world),"entry rejected outside interaction range")
	world.player.position=session.car.position+Vector3.RIGHT*2.8
	var original_camera: Transform3D=world.camera.transform
	var old_ticks:=Engine.physics_ticks_per_second
	session.interaction_available=func(): return false
	check(not session.enter(world) and not session.driving and world.player.collision_mask==1 and Engine.physics_ticks_per_second==old_ticks,"blocked entry preserves player collision and physics rate")
	session.interaction_available=func(): return true
	check(session.enter(world) and session.driving and world.player.collision_mask==0,"entry transfers control and disables occupant collision")
	session.interaction_available=func(): return false
	check(session.exit_vehicle(world)=="Vehicle interaction unavailable" and session.driving and world.player.collision_mask==0,"blocked exit preserves vehicle occupancy")
	session.interaction_available=func(): return true
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
	var original_id: int=session.car.get_instance_id()
	session.car.linear_velocity=Vector3(25,2,3);session.car.streaming.discard_motion(session.car)
	session.car.damage_dent_count=3;session.car._pending_damage=true
	session.car.open_driver_door()
	var restore_start:=Time.get_ticks_usec()
	check(session.restore_snapshot(saved) and session.car.transform.is_equal_approx(pose) and session.car.freeze and not session.car.is_physics_processing(),"restore resets parked vehicle pose")
	print("VEHICLE_REUSE_RESTORE_US ",Time.get_ticks_usec()-restore_start)
	check(session.car.get_instance_id()==original_id,"reload reuses detailed vehicle model")
	check(not session.car.streaming.waiting and session.car.linear_velocity==Vector3.ZERO and session.car.angular_velocity==Vector3.ZERO,"reuse clears held momentum")
	check(session.car.damage_dent_count==0 and not session.car._pending_damage and not session.car.driver_door_open and session.car.driver_door_hinge.rotation.y==0,"reuse resets damage and door state")
	var id: int=session.car.get_instance_id()
	check(not session.restore_snapshot(PackedByteArray([0])) and session.car.get_instance_id()==id,"invalid restore leaves live vehicle untouched")
	session.car.position.x=-1
	check(not session.storage.validate_snapshot(session.capture_snapshot()),"invalid live pose rejects save instead of removing vehicle")
	check(session.restore_snapshot(PackedByteArray()) and session.car==null,"absent section removes old vehicle")
	world.free();quit(0 if failures==0 else 1)
