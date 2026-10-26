# SPDX-License-Identifier: 0BSD
# Diagnostic, not a regression expectation or a production fix.
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
	var app_focused:=true
	var session:Node
	func _process(delta:float)->void:
		if is_instance_valid(session):
			var boost_before:float=session.car.boost_amount if session.driving else 0.0
			session.update(self,delta)
			# DummyDisplayServer cannot capture the mouse. Simulate the foreground
			# input contract for this headless fixture, never an unoccupied car.
			if session.driving:
				session.car.set_controls_enabled(true)
				session.car.boost_amount=boost_before
	func _physics_process(delta:float)->void:
		if is_instance_valid(session) and not session.driving:
			player.velocity.x=0;player.velocity.z=0;player.velocity.y-=20*delta;player.move_and_slide()
var results:Array=[]
var failures:=0
var scene:PackedScene
var observer:Camera3D
func _initialize()->void:run.call_deferred()
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func sample(world:Fixture,tick:int)->Dictionary:
	var car:RigidBody3D=world.session.car
	return {"tick":tick,"position":car.position,"velocity":car.linear_velocity,"angular":car.angular_velocity,
		"loaded":car.loaded_wheels,"freeze":car.freeze,"waiting":car.streaming.waiting,
		"driving":world.session.driving,"coasting":world.session.coasting.has(world.session.car_identity),
		"player_contact":world.player in car.get_colliding_bodies(),"reset_events":car.return_events.size()}
func floor_for(world:Fixture,kind:String)->void:
	if kind=="box":
		var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new()
		shape.size=Vector3(100,2,2400);collision.shape=shape;floor.add_child(collision);floor.position=Vector3(400,179,1300);world.add_child(floor)
	else:
		for z in range(288,2416,16):
			var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new()
			shape.set_faces(PackedVector3Array([Vector3(350,180,z),Vector3(450,180,z),Vector3(350,180,z+16),Vector3(450,180,z),Vector3(450,180,z+16),Vector3(350,180,z+16)]))
			collision.shape=shape;body.add_child(collision);world.add_child(body)
func run_case(kind:String,speed:float,keep_rate:bool=false)->void:
	Engine.physics_ticks_per_second=60
	var world:=Fixture.new();root.add_child(world)
	world.add_child(world.terrain);world.add_child(world.structures);world.add_child(world.player);world.player.add_child(world.camera)
	world.player.collision_layer=2;world.player.collision_mask=7
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	shape.shape=capsule;shape.position.y=.9;world.player.add_child(shape)
	floor_for(world,kind)
	world.session=load("res://addons/vehicle_runtime/world_vehicle.gd").new();world.add_child(world.session)
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	world.session.prepare(world,persistence)
	while not world.session.scene_ready():await process_frame
	world.session._vehicle_scene=scene
	world.session._install_vehicle(world,Transform3D(Basis.IDENTITY,Vector3(400,180.85,400)))
	var car:RigidBody3D=world.session.car
	world.player.position=car.position+Vector3.RIGHT*2.8
	for tick in 3:await physics_frame
	if not world.session.enter(world):failures+=1;print("FAIL entry fixture");world.free();return
	for tick in 120:await physics_frame
	if car.loaded_wheels<3:
		failures+=1;print("FAIL initial fixture wheel support ",kind);world.free();return
	var start:=car.position;var rows:Array=[]
	car.set_controls_enabled(true)
	if speed==0:key(KEY_W,true);key(KEY_SHIFT,true)
	else:car._drive_speed=speed;car.linear_velocity=car.basis.z*speed
	var peak:=0.0;var travel_ticks:=0
	for tick in 120*30:
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		await physics_frame;travel_ticks+=1;peak=maxf(peak,car.linear_velocity.length())
		if tick%30==0:rows.append(sample(world,tick))
		if car.position.z-start.z>=128 and (speed>0 or peak>=60):break
	key(KEY_W,false);key(KEY_SHIFT,false)
	var exit_state:=sample(world,-1)
	if exit_state.position.distance_to(start)<128 or (speed==0 and peak<60):
		failures+=1;print("FAIL requested long/high-speed drive not achieved")
	var message:String=world.session.exit_vehicle(world)
	if not message.begins_with("On foot"):failures+=1;print("FAIL supported exit ",message);world.free();return
	if keep_rate:Engine.physics_ticks_per_second=120
	var minimum_y:float=car.position.y;var largest_jump:=0.0;var previous:Vector3=car.position;var body_contacts:=0
	for tick in Engine.physics_ticks_per_second*9:
		await physics_frame
		var row:=sample(world,tick);rows.append(row)
		minimum_y=minf(minimum_y,car.position.y);largest_jump=maxf(largest_jump,previous.distance_to(car.position));previous=car.position
		if row.player_contact:body_contacts+=1
	var result:={"floor":kind,"speed_mode":"W+Shift" if speed==0 else "injected_coasting_speed","requested_mps":speed,"keep_120hz":keep_rate,
		"departure":start,"exit":exit_state,"after":sample(world,-2),"distance_before_exit":exit_state.position.distance_to(start),
		"peak_speed_mps":peak,"drive_ticks":travel_ticks,"minimum_post_exit_y":minimum_y,"largest_tick_displacement":largest_jump,
		"player_contact_ticks":body_contacts,"return_events":car.return_events.duplicate(),"samples":rows}
	results.append(result);var brief:=result.duplicate();brief.erase("samples");print("FAST_EXIT_RETURN ",brief)
	world.free();await process_frame
func run()->void:
	var model=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	model.set_script(load("res://tests/vehicle_return_trace_car.gd"));scene=PackedScene.new();scene.pack(model);model.free()
	var kinds:Array=["triangles"] if "--triangles-only" in OS.get_cmdline_user_args() else ["box","triangles"]
	for kind in kinds:
		for speed:float in [30.0,72.0,100.0]:await run_case(kind,speed)
	await run_case("triangles",0)
	var report:=FileAccess.open("res://reports/vehicle_fast_exit_return.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"scope":"Unchanged production vehicle/session, traced reset/restore wrappers, simulated foreground capture for headless driving, actual 128m+ driving on resident box and segmented concave floors; injected speed cases separate from real W+Shift case","cases":results},"  "));report.close()
	Engine.physics_ticks_per_second=60
	print("VEHICLE_FAST_EXIT_DIAGNOSIS failures=",failures," cases=",results.size());quit(1 if failures else 0)
