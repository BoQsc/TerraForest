extends SceneTree

class ReadyTerrain extends Node:
	var focus:=Vector3.ZERO
	var travel_velocity:=Vector3.ZERO
	var require_collision:=true
	func is_collision_region_ready(_bounds:AABB)->bool:return true
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(accepted:bool,label:String)->void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event)
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var floor:=StaticBody3D.new();floor.position.y=-.5;stage.add_child(floor)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(80,1,80);collision.shape=shape;floor.add_child(collision)
	var terrain:=ReadyTerrain.new();stage.add_child(terrain)
	var scene:PackedScene=load("res://vehicle_demo/scenes/car.tscn")
	var car:RigidBody3D=scene.instantiate();car.position=Vector3(0,1,0);stage.add_child(car);car.bind_streamed_world(terrain)
	var parked:RigidBody3D=scene.instantiate();parked.position=Vector3(0,1,12);stage.add_child(parked);parked.bind_streamed_world(terrain);parked.freeze=true;parked.set_physics_process(false)
	car.set_controls_enabled(true)
	for frame in 120:await physics_frame
	check(car.loaded_wheels>=3 and car.position.y>0,"real vehicle suspension settles on static terrain")
	var start:Vector3=car.position;var parked_pose:Transform3D=parked.global_transform
	var contact:=false;var maximum_speed:=0.0
	key(KEY_W,true)
	for frame in 360:
		await physics_frame
		maximum_speed=maxf(maximum_speed,car.speed_kph)
		contact=contact or car.get_colliding_bodies().has(parked)
		if contact:break
	key(KEY_W,false)
	check(car.position.z-start.z>3 and maximum_speed>5,"actual native driver accelerates the chassis")
	check(contact and car.position.z<parked.position.z-1,"driven chassis hits rather than crosses a parked vehicle")
	key(KEY_SPACE,true)
	for frame in 240:
		await physics_frame
		if car.linear_velocity.length()<.15:break
	key(KEY_SPACE,false)
	check(car.linear_velocity.length()<.15,"handbrake settles the chassis after impact")
	check(parked.global_transform.is_equal_approx(parked_pose),"parked vehicle remains stationary")
	check(car.global_transform.is_finite() and car.position.y>0 and car.position.y<3,"collision response stays finite above the ground")
	stage.free();await process_frame
	print("VEHICLE_PHYSICS_COMPATIBILITY checks=",checks," failures=",failures);quit(1 if failures else 0)
