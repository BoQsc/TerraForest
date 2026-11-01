# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var car:RigidBody3D
var pilot:RefCounted
var command:Dictionary={}
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func _initialize()->void:run.call_deferred()
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func run()->void:
	var body:=StaticBody3D.new();body.collision_layer=1
	var floor_shape:=BoxShape3D.new();floor_shape.size=Vector3(250,1,250)
	var floor_collision:=CollisionShape3D.new();floor_collision.shape=floor_shape;floor_collision.position=Vector3(50,-.5,50);body.add_child(floor_collision);root.add_child(body)
	car=load("res://vehicle_demo/scenes/car.tscn").instantiate();car.position=Vector3(0,.85,0);root.add_child(car);car.set_controls_enabled(false)
	pilot=ClassDB.instantiate("NativeRoadJourney")
	var points:=PackedVector3Array([Vector3.ZERO,Vector3(0,0,50),Vector3(60,0,50),Vector3(60,0,100)])
	check(pilot.follow(points),"native driver accepts the fixture route")
	for tick in 120:await physics_frame
	check(not car.autonomous_controls.is_valid(),"ordinary cars have no autonomous owner")
	car.set_controls_enabled(true);key(KEY_W,true)
	for tick in 90:await physics_frame
	check(car.position.z>4 and car.linear_velocity.length()>3,"ordinary W still accelerates the physical car")
	key(KEY_A,true)
	for tick in 45:await physics_frame
	check(car.global_basis.z.x>.1,"ordinary A still steers the physical car")
	key(KEY_W,false);key(KEY_A,false);key(KEY_SPACE,true)
	var brake_deadline:=Time.get_ticks_msec()+8000
	while car.linear_velocity.length()>.15 and Time.get_ticks_msec()<brake_deadline:await physics_frame
	print("TRADER_RIDE_PLAYER_BRAKE speed_mps=",car.linear_velocity.length())
	check(car.linear_velocity.length()<.4,"ordinary handbrake still stops the car")
	key(KEY_SPACE,false);car.set_controls_enabled(false)
	# Fixture setup only, before any autonomous journey begins.
	car.reset_vehicle()
	for tick in 120:await physics_frame
	car.autonomous_controls=func(delta:float)->Dictionary:
		command=pilot.advance(car.global_transform,car.linear_velocity,delta,true,true)
		return command
	key(KEY_S,true);key(KEY_R,true)
	var deadline:=Time.get_ticks_msec()+60000
	var maximum_lane:=0.0;var samples:Array=[];var next_sample:=0
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		maximum_lane=maxf(maximum_lane,float(command.get("lane_error_m",0)))
		if Time.get_ticks_msec()>next_sample:
			samples.append({"position":car.position,"speed":car.linear_velocity.length(),"command":command});next_sample=Time.get_ticks_msec()+500
		if command.get("state","") in ["arrived","blocked","search_limit"]:break
	check(command.get("state","")=="arrived","physical chassis arrives through two road corners")
	check(car.position.distance_to(points[-1])<2 and car.linear_velocity.length()<.4,"arrival is physical and stopped")
	check(maximum_lane<=3.5,"car remains inside the declared road corridor")
	var stop:Vector3=car.position
	for tick in 120:await physics_frame
	check(car.position.distance_to(stop)<.25,"arrival service brake holds without reversing")
	key(KEY_S,false);key(KEY_R,false)
	DirAccess.make_dir_recursive_absolute("res://reports/trader_ride_physics")
	var result_path:="res://reports/trader_ride_physics/"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
	FileAccess.open(result_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"position":car.position,"command":command,"maximum_lane_m":maximum_lane,"samples":samples},"  "))
	print("TRADER_RIDE_PHYSICS_REPORT ",result_path)
	car.free();body.free();await process_frame
	print("TRADER_RIDE_PHYSICS checks=",checks," failures=",failures);quit(1 if failures else 0)
