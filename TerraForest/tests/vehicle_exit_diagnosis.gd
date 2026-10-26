# SPDX-License-Identifier: 0BSD
# Regression for the measured exit contact and stale parking failure.
extends SceneTree
class ReadyProvider extends Node:
	var available:=true
	var focus:=Vector3.ZERO
	var travel_velocity:=Vector3.ZERO
	var require_collision:=true
	func is_collision_region_ready(_bounds:AABB)->bool:return available
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
		"exit_contact_guard":world.player in car.get_collision_exceptions(),
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
	if mode=="rough_ground":
		# Unequal supports put all four springs at different compression and leave
		# the checked player exit lower than the chassis, as on disturbed ground.
		for i in 4:
			var patch:=StaticBody3D.new();var patch_collision:=CollisionShape3D.new();var patch_shape:=BoxShape3D.new()
			var height:float=[.12,.22,.06,.17][i]
			patch_shape.size=Vector3(1.1,height,1.3);patch_collision.shape=patch_shape;patch.add_child(patch_collision)
			patch.position=Vector3(400+(.8438 if i%2==0 else -.8438),180+height*.5,400+(1.4279 if i<2 else -1.2981));world.add_child(patch)
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
	if mode=="host_exception":car.add_collision_exception_with(world.player)
	var message:String=session.exit_vehicle(world)
	var immediate:=sample(car,world,-2)
	if not message.begins_with("On foot"):failures+=1;print("FAIL exit ",mode," ",message);world.free();return
	if world.player.collision_layer!=2 or world.player.collision_mask!=7:failures+=1;print("FAIL exit preserves player world collision")
	# Render updates cannot park the car from the last seated observations.
	for render in 20:session.update(world,.01)
	if car.freeze:failures+=1;print("FAIL parked before post-exit physics")
	if mode=="keep_120hz":Engine.physics_ticks_per_second=120
	if mode=="no_parking":session.coasting.clear()
	if mode=="rapid_reentry":
		if not session.enter(world) or not session.exit_vehicle(world).begins_with("On foot"):failures+=1;print("FAIL immediate re-entry/exit")
	if mode=="stream_hold":world.terrain.available=false
	var rows:Array=[]
	for tick in Engine.physics_ticks_per_second*2:
		await physics_frame
		rows.append(sample(car,world,tick))
		if mode=="stream_hold" and tick==15:
			if not car.streaming.waiting or not session.coasting.has(session.car_identity):failures+=1;print("FAIL readiness hold counted as parked")
			world.terrain.available=true
		if tick==4:
			var exception_expected:bool=mode=="host_exception"
			if (world.player in car.get_collision_exceptions())!=exception_expected:failures+=1;print("FAIL exit exception ownership/lifetime")
	var minimum_y:float=before.position.y;var maximum_y:float=minimum_y;var first_frozen:=-1;var contacts:=0;var wheel_hits:=0
	for row:Dictionary in rows:
		minimum_y=minf(minimum_y,row.position.y);maximum_y=maxf(maximum_y,row.position.y)
		if row.freeze and first_frozen<0:first_frozen=row.tick
		if row.player_body_contact:contacts+=1
		wheel_hits+=row.player_wheel_hits
	var result:={"mode":mode,"slope_radians":slope,"before":before,"immediate":immediate,"after":rows[-1],"min_y":minimum_y,"max_y":maximum_y,"first_frozen_tick":first_frozen,"body_contact_ticks":contacts,"player_wheel_hits":wheel_hits,"samples":rows}
	results.append(result)
	var brief:=result.duplicate();brief.erase("samples");print("EXIT_DIAGNOSIS ",brief)
	if contacts>0 or before.position.y-minimum_y>.02:failures+=1;print("FAIL exit chassis shove ",mode," slope=",slope)
	if mode!="no_parking" and (first_frozen<0 or not session.coasting.is_empty()):failures+=1;print("FAIL stable car did not park")
	if mode not in ["no_parking","stream_hold"] and first_frozen<10:failures+=1;print("FAIL parked without a stable observation window")
	# Restore/removal while an exit is pending must not leave owned exceptions.
	if mode=="normal_exit":
		world.player.velocity=Vector3.LEFT*3
		for tick in 60:await physics_frame
		world.player.velocity=Vector3.ZERO
		if world.player.position.x-car.position.x<1.0 or world.player.position.x-car.position.x>2.2:
			failures+=1;print("FAIL player can walk through car after exit guard expires")
		else:print("PASS ordinary car/player collision blocks walking after exit")
		world.player.position=car.position+Vector3.RIGHT*2.8
		if not session.enter(world) or not session.exit_vehicle(world).begins_with("On foot"):failures+=1;print("FAIL restore lifecycle fixture")
		var saved:PackedByteArray=session.capture_snapshot()
		if session.restore_snapshot(PackedByteArray([0])) or session._exit_contacts.is_empty():failures+=1;print("FAIL invalid restore changed exit transition")
		if not session.restore_snapshot(saved) or not session._exit_contacts.is_empty() or world.player in car.get_collision_exceptions():failures+=1;print("FAIL restore leaves exit guard")
		if not session.enter(world) or not session.exit_vehicle(world).begins_with("On foot"):failures+=1;print("FAIL removal lifecycle fixture")
		session.remove_vehicle(session.car_identity)
		for tick in 4:await physics_frame
		if not session._exit_contacts.is_empty() or not session.coasting.is_empty():failures+=1;print("FAIL removed car leaves transition")
	world.free();await process_frame
func run()->void:
	for slope in [0.0,.15]:
		for mode in ["normal_exit","keep_120hz","no_parking","rapid_reentry","host_exception","stream_hold"]:await run_case(mode,slope)
	await run_case("rough_ground",0.0)
	var report:=FileAccess.open("res://reports/vehicle_exit_diagnosis.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"scope":"Corrected production exit on flat/sloped/unequal-height static supports, re-entry, holds, exception ownership and restore/removal; no saved world touched","cases":results},"  "));report.close()
	Engine.physics_ticks_per_second=60
	print("VEHICLE_EXIT_REGRESSION failures=",failures)
	quit(1 if failures else 0)
