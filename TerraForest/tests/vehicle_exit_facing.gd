# SPDX-License-Identifier: 0BSD
extends SceneTree
class ReadyProvider extends Node:
	var available:=true
	var focus:=Vector3.ZERO
	var travel_velocity:=Vector3.ZERO
	func is_collision_region_ready(_bounds:AABB)->bool:return available
class Fixture extends Node3D:
	var terrain:=ReadyProvider.new()
	var structures:=ReadyProvider.new()
	var player:=CharacterBody3D.new()
	var camera:=Camera3D.new()
	var yaw:=0.0
	var pitch:=-.25
var failures:=0
var checks:=0
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func run()->void:
	var world:=Fixture.new();root.add_child(world)
	world.add_child(world.terrain);world.add_child(world.structures);world.add_child(world.player);world.player.add_child(world.camera)
	world.player.collision_layer=2;world.player.collision_mask=7
	var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.34
	var player_shape:=CollisionShape3D.new();player_shape.shape=capsule;player_shape.position.y=.9;world.player.add_child(player_shape)
	var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(60,1,60)
	collision.shape=box;floor.position=Vector3(400,179.5,400);floor.add_child(collision);world.add_child(floor)
	var session=load("res://addons/vehicle_runtime/world_vehicle.gd").new();world.add_child(session)
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(session.prepare(world,persistence),"facing fixture registers")
	if not session._install_vehicle(world,Transform3D(Basis(Vector3.UP,PI),Vector3(400,181,400))):check(false,"vehicle installs");world.free();quit(1);return
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var codec:RefCounted=ClassDB.instantiate("NativePlayerPose")
	for angles:Vector3 in [Vector3(0,180,0),Vector3(0,90,0),Vector3(0,0,0),Vector3(0,-90,0),Vector3(15,179,20),Vector3(-15,-179,-20),Vector3(90,45,0),Vector3(0,75,180)]:
		session.car.freeze=true;session.car.set_physics_process(false);session.car.rotation=Vector3(0,PI+.37,0)
		world.yaw=.37;world.pitch=-.25;world.player.rotation=Vector3(0,world.yaw,0)
		world.player.position=session.car.position+Vector3.RIGHT*2.8
		world.camera.position=Vector3(0,1.68,0);world.camera.rotation=Vector3(world.pitch,.1,.04)
		var expected_pitch:float=world.camera.rotation.x
		await physics_frame;await physics_frame
		if not session.enter(world):check(false,"fixture enters");break
		session.car.freeze=true;session.car.set_physics_process(false)
		session.car.rotation=angles*PI/180
		await physics_frame;await physics_frame
		for tick in 120:session.adapter(session.car).camera_update(session.car,world.camera,1.0/60)
		var old_camera:Transform3D=world.camera.transform;var old_player:Transform3D=world.player.transform;var old_yaw:float=world.yaw
		session.interaction_available=func():return false
		check(session.exit_vehicle(world)=="Vehicle interaction unavailable" and world.camera.transform==old_camera and world.player.transform==old_player and world.yaw==old_yaw,"denied exit preserves facing")
		session.interaction_available=func():return true
		world.structures.available=false
		check(session.exit_vehicle(world)=="No clear, loaded exit beside the vehicle" and world.player.transform==old_player and world.yaw==old_yaw,"unloaded exit preserves facing")
		world.structures.available=true
		var expected:Vector3=session.car.global_basis.z;expected.y=0
		if expected.length_squared()<.0001:expected=session.car.global_basis.x.cross(Vector3.UP)
		expected=expected.normalized()
		check(session.exit_vehicle(world).begins_with("On foot"),"supported exit succeeds")
		var facing:Vector3=-world.player.global_basis.z;var view:Vector3=-world.camera.global_basis.z;view.y=0;view=view.normalized()
		check(facing.dot(expected)>.99999 and view.dot(expected)>.99999,"body and view face vehicle front at "+str(angles))
		check(world.player.global_basis.y.dot(Vector3.UP)>.99999 and absf(world.camera.rotation.z)<.00001,"exit does not inherit vehicle roll or pitch")
		check(absf(world.pitch-expected_pitch)<.00001 and absf(world.camera.rotation.x-world.pitch)<.00001,"look pitch is retained and synchronized")
		check(absf(wrapf(world.player.rotation.y-world.yaw,-PI,PI))<.00001,"mouse input yaw agrees with body")
		var saved:Dictionary=codec.decode(codec.encode(world.player.position,world.yaw,world.pitch,false,0))
		check(saved.get("ok",false) and absf(wrapf(saved.yaw-world.player.rotation.y,-PI,PI))<.00001,"on-foot pose codec retains exit heading")
		samples.append({"car_degrees":angles,"expected_forward":expected,"player_forward":facing,"view_forward":view,"yaw":world.yaw,"pitch":world.pitch})
	var file:=FileAccess.open("res://reports/vehicle_exit_facing.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"  "));file.close()
	world.free();await process_frame;print("VEHICLE_EXIT_FACING checks=",checks," failures=",failures);quit(1 if failures else 0)
