# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var original_ticks:=Engine.physics_ticks_per_second
	var world:=Node3D.new();root.add_child(world)
	var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new()
	box.size=Vector3(200,1,200);collision.shape=box;floor.position.y=-0.5
	floor.add_child(collision);world.add_child(floor)
	var scene=load("res://vehicle_demo/scenes/car.tscn")
	for hz in [60,120]:
		Engine.physics_ticks_per_second=hz
		for initial_speed in [30.0,-15.0]:
			var car=scene.instantiate();car.position=Vector3(0,0.85,0);world.add_child(car)
			car.set_controls_enabled(false)
			for tick in hz: await physics_frame
			check(car.loaded_wheels>=2 and car._normal_mode,"fixture establishes loaded ground support")
			car._drive_speed=initial_speed;car.linear_velocity=-car.global_basis.z*initial_speed
			car.boost_active=true;car.boost_amount=1.0;car.set_controls_enabled(false)
			for code in [KEY_W,KEY_A,KEY_SHIFT,KEY_SPACE]: key(code,true)
			check(Input.is_key_pressed(KEY_W) and Input.is_key_pressed(KEY_SPACE),"fixture holds driving inputs")
			var start: Vector3=car.global_position
			var peak_speed:=0.0;var peak_steer:=0.0;var blocked:=true;var finite:=true
			for tick in int(hz*2.5):
				await physics_frame
				peak_speed=maxf(peak_speed,car.linear_velocity.slide(Vector3.UP).length())
				peak_steer=maxf(peak_steer,absf(car._steering_angle))
				blocked=blocked and not car.boost_active and car.boost_amount==0 and not car.handbrake_active
				finite=finite and car.global_position.is_finite() and car.linear_velocity.is_finite()
			var distance: float=car.global_position.distance_to(start)
			var final_speed: float=car.linear_velocity.slide(Vector3.UP).length()
			check(blocked and peak_steer<0.001,"disabled controls ignore throttle/steering/boost/handbrake keys")
			check(finite and peak_speed<=absf(initial_speed)+0.5,"disabled motion remains finite and does not accelerate")
			check(final_speed<0.15 and distance<(30.0 if initial_speed>0 else 9.0),"grounded vehicle stops within time and distance bounds")
			print("DISABLED_BRAKING ",{"physics_hz":hz,"initial_mps":initial_speed,"final_mps":final_speed,"travel_m":distance,"peak_mps":peak_speed})
			for code in [KEY_W,KEY_A,KEY_SHIFT,KEY_SPACE]: key(code,false)
			car.set_controls_enabled(true);key(KEY_W,true)
			for tick in int(hz/2): await physics_frame
			check(car._drive_speed>1.0,"enabled throttle drives again after braking")
			key(KEY_W,false);car.free();await process_frame
	world.free();Engine.physics_ticks_per_second=original_ticks
	print("VEHICLE_DISABLED_BRAKING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
