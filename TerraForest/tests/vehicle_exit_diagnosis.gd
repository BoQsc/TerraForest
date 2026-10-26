# SPDX-License-Identifier: 0BSD
# Diagnostic A/B probe: exercise the unchanged enter/exit and parking adapter.
extends SceneTree
class ReadyProvider extends Node:
	var focus:=Vector3.ZERO
	var travel_velocity:=Vector3.ZERO
	var require_collision:=true
	func is_collision_region_ready(_bounds:AABB)->bool:return true
class Hud extends RefCounted:
	var inventory_open:=false
class Fixture extends Node3D:
	var terrain:=ReadyProvider.new()
	var structures:=ReadyProvider.new()
	var player:=CharacterBody3D.new()
	var camera:=Camera3D.new()
	var player_hud:=Hud.new()
	var app_focused:=false
	var session:Node
	var move_player:=true
	func _process(delta:float)->void:
		if is_instance_valid(session):session.update(self,delta)
	func _physics_process(delta:float)->void:
		if move_player and is_instance_valid(session) and not session.driving:
			player.velocity.y-=20*delta;player.move_and_slide()
var results:Array=[]
var failures:=0
func _initialize()->void:run.call_deferred()
func sample(car:RigidBody3D,world:Fixture,tick:int)->Dictionary:
	var player_wheels:=0
	for ray:RayCast3D in car.wheel_rays:
		if ray.get_collider()==world.player:player_wheels+=1
	var player_physics:Transform3D=PhysicsServer3D.body_get_state(world.player.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return {"tick":tick,"position":car.position,"linear":car.linear_velocity,"angular":car.angular_velocity,
		"player_scene":world.player.global_position,"player_physics":player_physics.origin,
		"loaded":car.loaded_wheels,"springs":car._spring_lengths.duplicate(),"freeze":car.freeze,
		"normal_mode":car._normal_mode,"player_body_contact":world.player in car.get_colliding_bodies(),"player_wheel_hits":player_wheels}
func run_case(mode:String,slope:float)->void:
	Engine.physics_ticks_per_second=60
	var world:=Fixture.new();root.add_child(world)
	world.add_child(world.terrain);world.add_child(world.structures);world.add_child(world.player);world.player.add_child(world.camera)
	world.player.collision_layer=2;world.player.collision_mask=7
	var player_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	player_shape.shape=capsule;player_shape.position.y=.9;world.player.add_child(player_shape)
	var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(80,1,80)
	collision.shape=box;floor.add_child(collision);floor.position=Vector3(400,179.5,400);floor.rotation.z=slope;world.add_child(floor)
	var session=load("res://addons/vehicle_runtime/world_vehicle.gd").new();world.add_child(session);world.session=session
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	if not session.prepare(world,persistence) or not session._install_vehicle(world,Transform3D(Basis(Vector3.FORWARD,-slope),Vector3(400,180.85,400))):
		failures+=1;world.free();return
	var car:RigidBody3D=session.car
	world.player.position=car.position+Vector3.RIGHT*2.8
	for tick in 3:await physics_frame
	if not session.enter(world):failures+=1;print("FAIL entry ",mode);world.free();return
	for tick in 180:await physics_frame
	var before:=sample(car,world,-1)
	var message:String=session.exit_vehicle(world)
	var immediate:=sample(car,world,-2)
	if not message.begins_with("On foot"):failures+=1;print("FAIL exit ",mode," ",message);world.free();return
	if mode=="no_player_collision":world.player.collision_layer=0;world.player.collision_mask=0;world.move_player=false
	if mode=="keep_120hz":Engine.physics_ticks_per_second=120
	if mode=="no_parking":session.coasting.clear()
	if mode=="flush_player_transform":world.player.force_update_transform()
	# Experimental control only: let the kinematic body reach the checked exit
	# before the car/player pair is allowed to collide again. Ground stays solid.
	if mode=="one_step_pair_exception":car.add_collision_exception_with(world.player)
	var rows:Array=[]
	for tick in Engine.physics_ticks_per_second*2:
		await physics_frame
		rows.append(sample(car,world,tick))
		if mode=="one_step_pair_exception" and tick==1:car.remove_collision_exception_with(world.player)
	var minimum_y:float=before.position.y;var maximum_y:float=minimum_y;var first_frozen:=-1;var contacts:=0;var wheel_hits:=0
	for row:Dictionary in rows:
		minimum_y=minf(minimum_y,row.position.y);maximum_y=maxf(maximum_y,row.position.y)
		if row.freeze and first_frozen<0:first_frozen=row.tick
		if row.player_body_contact:contacts+=1
		wheel_hits+=row.player_wheel_hits
	var result:={"mode":mode,"slope_radians":slope,"before":before,"immediate":immediate,"after":rows[-1],"min_y":minimum_y,"max_y":maximum_y,"first_frozen_tick":first_frozen,"body_contact_ticks":contacts,"player_wheel_hits":wheel_hits,"samples":rows}
	results.append(result)
	var brief:=result.duplicate();brief.erase("samples");print("EXIT_DIAGNOSIS ",brief)
	var expected_control:bool=mode in ["no_player_collision","one_step_pair_exception"]
	var observed:bool=(contacts==0 and before.position.y-minimum_y<.02) if expected_control else (contacts>0 and before.position.y-minimum_y>.4)
	if not observed:failures+=1;print("FAIL expected known-defect/control outcome ",mode," slope=",slope)
	world.free();await process_frame
func run()->void:
	for slope in [0.0,.15]:
		for mode in ["normal_exit","no_player_collision","keep_120hz","no_parking","flush_player_transform","one_step_pair_exception"]:await run_case(mode,slope)
	var report:=FileAccess.open("res://reports/vehicle_exit_diagnosis.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"scope":"Unchanged production vehicle and enter/exit adapter; static box floor; no saved world touched","cases":results},"  "));report.close()
	Engine.physics_ticks_per_second=60
	print("VEHICLE_EXIT_DIAGNOSIS failures=",failures)
	quit(1 if failures else 0)
