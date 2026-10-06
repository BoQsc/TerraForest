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
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func poll(car: Node) -> void:
	car._update_reset();car._update_visual_damage_controls();car._update_accessory_motion_controls()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var car=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.freeze=true;root.add_child(car);car.set_physics_process(false);car.set_process(false)
	car.position=Vector3(20,10,30)
	var pose: Transform3D=car.transform
	var damage: bool=car.visual_damage_enabled
	var accessories: bool=car.accessory_motion_enabled
	car.damage_dent_count=3
	car.set_controls_enabled(false)
	for code in [KEY_R,KEY_F8,KEY_F9,KEY_F10]: key(code,true)
	check(Input.is_key_pressed(KEY_R) and Input.is_key_pressed(KEY_F9),"fixture installs actual held key state")
	poll(car)
	check(car.transform==pose,"disabled reset shortcut cannot teleport vehicle")
	check(car.damage_dent_count==3 and car.visual_damage_enabled==damage,"disabled repair and damage toggle preserve vehicle state")
	check(car.accessory_motion_enabled==accessories,"disabled accessory toggle preserves setting")
	car.set_controls_enabled(true);poll(car)
	check(car.transform==pose and car.damage_dent_count==3 and car.visual_damage_enabled==damage and car.accessory_motion_enabled==accessories,"held shortcuts do not fire when controls resume")
	for code in [KEY_R,KEY_F8,KEY_F9,KEY_F10]: key(code,false)
	poll(car)
	for code in [KEY_R,KEY_F8,KEY_F9,KEY_F10]: key(code,true)
	poll(car)
	check(car.transform!=pose and car.damage_dent_count==0,"fresh enabled reset and repair work")
	check(car.visual_damage_enabled!=damage and car.accessory_motion_enabled!=accessories,"fresh enabled toggle presses work")
	for code in [KEY_R,KEY_F8,KEY_F9,KEY_F10]: key(code,false)
	car.free();await process_frame
	print("VEHICLE_DISABLED_SHORTCUTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
